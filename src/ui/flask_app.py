"""
heatWave Flask backend — lightweight replacement for Streamlit.
Provides JSON API routes for PDF upload, parsing, seeding, and generation.
Works both as a regular Python app and inside a PyInstaller .exe.
"""
import io
import sys
import os
import json
import math
import tempfile
from pathlib import Path
from datetime import datetime

from flask import Flask, request, jsonify, send_file, render_template, make_response
from werkzeug.middleware.proxy_fix import ProxyFix
from flask_limiter import Limiter
from flask_limiter.util import get_remote_address
from dotenv import load_dotenv

import logging
load_dotenv()  # Load environment variables from .env

# Configure logging
logging.basicConfig(level=logging.DEBUG)
logging.getLogger('werkzeug').setLevel(logging.ERROR)
logging.getLogger('pdfminer').setLevel(logging.WARNING)
app_logger = logging.getLogger('heatwave')

# Queue and tasks
from src.ui.queue_manager import task_queue, get_job_status, redis_conn, user_queue_manager
from src.ui.tasks import parse_pdf_task, seeding_task, generate_pdf_task

# User and temp management
from src.core.user_manager import UserManager
from src.core.temp_manager import TempManager

# ---------------------------------------------------------------------------
# Resolve paths for both dev and frozen (PyInstaller) mode
# ---------------------------------------------------------------------------
if getattr(sys, 'frozen', False):
    # Running as PyInstaller exe — _MEIPASS or _internal contains bundled data
    _BASE_DIR = Path(sys._MEIPASS) if hasattr(sys, '_MEIPASS') else Path(os.path.dirname(sys.executable)) / '_internal'
    _TEMPLATE_DIR = _BASE_DIR / 'src' / 'ui' / 'templates'
    _STATIC_DIR = _BASE_DIR / 'assets'
else:
    _BASE_DIR = Path(__file__).resolve().parent.parent.parent  # project root
    _TEMPLATE_DIR = Path(__file__).resolve().parent / 'templates'
    _STATIC_DIR = _BASE_DIR / 'assets'

app = Flask(__name__, template_folder=str(_TEMPLATE_DIR), static_folder=str(_STATIC_DIR))
app.config['MAX_CONTENT_LENGTH'] = 50 * 1024 * 1024  # 50 MB max upload

# ---------------------------------------------------------------------------
# Reverse Proxy Support
# ---------------------------------------------------------------------------
app.wsgi_app = ProxyFix(app.wsgi_app, x_for=1, x_proto=1, x_host=1, x_prefix=1)

# ---------------------------------------------------------------------------
# Rate Limiting
# ---------------------------------------------------------------------------
limiter = Limiter(
    get_remote_address,
    app=app,
    default_limits=["200 per day", "50 per hour"],
    storage_uri=os.environ.get('REDIS_URL', 'memory://'),
)

# ---------------------------------------------------------------------------
# Initialize User and Temp Managers
# ---------------------------------------------------------------------------
# Configure user manager with Redis if available
user_manager = UserManager(redis_conn=redis_conn)

# Configure temp manager
temp_manager = TempManager()


# ---------------------------------------------------------------------------
# Import project modules (same ones Streamlit used)
# ---------------------------------------------------------------------------
from src.parser.extractor import extract_text_from_pdf, parse_events_from_text
from src.seeding.seeder import seed_event, format_heat_sheet
from src.core.pdf_generator import generate_full_meet_pdf, generate_heat_sheet_pdf
from src.models.schemas import Entry, RelayEntry

# ---------------------------------------------------------------------------
# Helper Functions
# ---------------------------------------------------------------------------
def get_or_create_user_id() -> str:
    """
    Get user ID from request headers/cookies, or create a new one.
    Returns the user ID string.
    """
    # Try to get from header first (for API clients)
    user_id = request.headers.get('X-User-ID') or request.headers.get('X-User-Id')
    client_ip = request.remote_addr
    user_agent = request.headers.get('User-Agent')

    # If a client provides an ID, ensure a matching session exists and use it.
    if user_id:
        return user_manager.ensure_user_session(user_id, client_ip=client_ip, user_agent=user_agent)

    # Try to get from cookie
    if not user_id:
        user_id = request.cookies.get('heatwave_user_id')

    # Validate existing user
    if user_id:
        user_session = user_manager.get_user_session(user_id)
        if user_session:
            return user_id

    # Create new user session
    new_user_id = user_manager.create_user_session(client_ip, user_agent)

    return new_user_id

def get_user_temp_dir(user_id: str) -> Path:
    """Get the user's temporary directory."""
    return temp_manager.get_user_temp_dir(user_id)

def _attach_user_cookie(resp, user_id: str):
    """
    Ensure the browser keeps a stable user_id across requests.
    We set/refresh the cookie on JSON responses where we also return `user_id`.
    """
    existing = request.cookies.get('heatwave_user_id')
    if user_id and existing != user_id:
        resp.headers['X-Heatwave-UserId'] = user_id
        resp.set_cookie(
            'heatwave_user_id',
            user_id,
            httponly=True,
            samesite='Lax',
        )
    return resp

# ---------------------------------------------------------------------------
# Routes
# ---------------------------------------------------------------------------
@app.route('/favicon.ico')
def favicon():
    """Serve the favicon."""
    return app.send_static_file('icon.ico')

@app.route('/')
def index():
    """Serve the single-page UI."""
    resp = make_response(render_template('index.html'))
    # Avoid stale JS/HTML when iterating quickly (and reduces proxy caching risk).
    resp.headers['Cache-Control'] = 'no-store'
    return resp


@app.route('/api/upload', methods=['POST'])
@limiter.limit("10 per minute")
def upload_pdf():
    """Upload and parse a psych-sheet PDF."""
    if 'file' not in request.files:
        return jsonify({'error': 'No file uploaded'}), 400

    pdf_file = request.files['file']
    if pdf_file.filename == '':
        return jsonify({'error': 'Empty filename'}), 400

    user_id = get_or_create_user_id()

    try:
        pdf_bytes = pdf_file.read()

        if user_queue_manager.redis_conn:
            # Asynchronous mode (Server) - User-specific queue
            job_id = user_queue_manager.enqueue_user_job(
                user_id,
                parse_pdf_task,
                args=(pdf_bytes, pdf_file.filename, user_id)
            )
            if job_id:
                resp = jsonify({
                    'success': True,
                    'async': True,
                    'job_id': job_id,
                    'user_id': user_id
                })
                return _attach_user_cookie(resp, user_id)
            else:
                return jsonify({'error': 'Too many active jobs or queue unavailable'}), 429
        elif task_queue:
            # Fallback to global queue if user queues not available
            job = task_queue.enqueue(
                parse_pdf_task,
                args=(pdf_bytes, pdf_file.filename, user_id),
                job_timeout='5m'
            )
            resp = jsonify({
                'success': True,
                'async': True,
                'job_id': job.get_id(),
                'user_id': user_id
            })
            return _attach_user_cookie(resp, user_id)
        else:
            # Synchronous fallback (Desktop)
            result = parse_pdf_task(pdf_bytes, pdf_file.filename, user_id)
            if not result['success']:
                return jsonify({'error': result.get('error', 'Unknown error')}), 500

            # Store parsed events in user session
            user_manager.update_user_session(user_id,
                events=result['raw_events'],
                heat_sheets=None
            )

            resp = jsonify({
                'success': True,
                'async': False,
                'filename': result['filename'],
                'event_count': result['event_count'],
                'total_entries': result['total_entries'],
                'events': result['events_summary'],
                'user_id': user_id
            })
            return _attach_user_cookie(resp, user_id)

    except Exception as exc:
        return jsonify({'error': str(exc)}), 500


@app.route('/api/generate', methods=['POST'])
@limiter.limit("5 per minute")
def generate():
    """Seed events and generate heat sheets."""
    user_id = get_or_create_user_id()
    user_session = user_manager.get_user_session(user_id)

    if not user_session or user_session.get('events') is None:
        return jsonify({'error': 'No events parsed yet. Upload a PDF first.'}), 400

    data = request.get_json(silent=True) or {}
    num_lanes = int(data.get('lanes', 8))

    try:
        if user_queue_manager.redis_conn:
            # Asynchronous mode - User-specific queue
            job_id = user_queue_manager.enqueue_user_job(
                user_id,
                seeding_task,
                args=(user_session['events'], num_lanes, user_id)
            )
            if job_id:
                resp = jsonify({
                    'success': True,
                    'async': True,
                    'job_id': job_id,
                    'user_id': user_id
                })
                return _attach_user_cookie(resp, user_id)
            else:
                return jsonify({'error': 'Too many active jobs or queue unavailable'}), 429
        elif task_queue:
            # Fallback to global queue if user queues not available
            job = task_queue.enqueue(
                seeding_task,
                args=(user_session['events'], num_lanes, user_id),
                job_timeout='5m'
            )
            resp = jsonify({
                'success': True,
                'async': True,
                'job_id': job.get_id(),
                'user_id': user_id
            })
            return _attach_user_cookie(resp, user_id)
        else:
            # Synchronous fallback
            result = seeding_task(user_session['events'], num_lanes, user_id)
            if not result['success']:
                return jsonify({'error': result.get('error', 'Unknown error')}), 500

            user_manager.update_user_session(user_id, heat_sheets=result['heat_sheets'])

            resp = jsonify({
                'success': True,
                'async': False,
                'total_heats': result['total_heats'],
                'total_entries': result['total_entries'],
                'events': result['summary'],
                'user_id': user_id
            })
            return _attach_user_cookie(resp, user_id)

    except Exception as exc:
        return jsonify({'error': str(exc)}), 500


@app.route('/api/download/full', methods=['GET'])
def download_full_pdf():
    """Download the full meet heat-sheet PDF."""
    user_id = get_or_create_user_id()
    user_session = user_manager.get_user_session(user_id)

    if not user_session or user_session.get('heat_sheets') is None:
        return jsonify({'error': 'No heat sheets generated yet.'}), 400

    meet_title = request.args.get('title', 'Swimming Meet')
    meet_date = request.args.get('date', datetime.now().strftime('%m/%d/%Y'))

    try:
        user_temp_dir = get_user_temp_dir(user_id)
        pdf_path = user_temp_dir / 'Full_Meet_Heatsheets.pdf'
        generate_full_meet_pdf(
            user_session['heat_sheets'],
            str(pdf_path),
            meet_title=meet_title,
            meet_date=meet_date,
        )
        pdf_bytes = pdf_path.read_bytes()

        safe_title = meet_title.replace(' ', '_')
        return send_file(
            io.BytesIO(pdf_bytes),
            mimetype='application/pdf',
            as_attachment=True,
            download_name=f'HeatSheet_{safe_title}.pdf',
        )

    except Exception as exc:
        return jsonify({'error': str(exc)}), 500


@app.route('/api/download/event/<int:event_num>', methods=['GET'])
def download_event_pdf(event_num):
    """Download the heat-sheet PDF for a single event."""
    user_id = get_or_create_user_id()
    user_session = user_manager.get_user_session(user_id)

    if not user_session or user_session.get('heat_sheets') is None:
        return jsonify({'error': 'No heat sheets generated yet.'}), 400

    meet_title = request.args.get('title', 'Swimming Meet')
    meet_date = request.args.get('date', datetime.now().strftime('%m/%d/%Y'))

    hs = next((h for h in user_session['heat_sheets'] if h.event.number == event_num), None)
    if hs is None:
        return jsonify({'error': f'Event {event_num} not found.'}), 404

    try:
        user_temp_dir = get_user_temp_dir(user_id)
        pdf_path = user_temp_dir / f'Event_{event_num:02d}_Heatsheet.pdf'
        generate_heat_sheet_pdf(
            hs,
            str(pdf_path),
            meet_title=meet_title,
            meet_date=meet_date,
        )
        pdf_bytes = pdf_path.read_bytes()

        return send_file(
            io.BytesIO(pdf_bytes),
            mimetype='application/pdf',
            as_attachment=True,
            download_name=f'Event_{event_num:02d}_Heatsheet.pdf',
        )

    except Exception as exc:
        return jsonify({'error': str(exc)}), 500


@app.route('/api/status', methods=['GET'])
def status():
    """Return current session status for the frontend."""
    user_id = get_or_create_user_id()
    user_session = user_manager.get_user_session(user_id)

    has_events = user_session and user_session.get('events') is not None
    has_heats = user_session and user_session.get('heat_sheets') is not None

    resp = jsonify({
        'has_events': has_events,
        'has_heats': has_heats,
        'event_count': len(user_session['events']) if has_events else 0,
        'heat_sheet_count': len(user_session['heat_sheets']) if has_heats else 0,
        'user_id': user_id
    })
    return _attach_user_cookie(resp, user_id)


@app.route('/api/jobs/<job_id>', methods=['GET'])
def job_status(job_id):
    """Check the status of a background job."""
    user_id = get_or_create_user_id()

    # Try user-specific job first, fallback to global
    status_info = user_queue_manager.get_user_job_status(user_id, job_id)
    if status_info['status'] == 'not_found' and task_queue:
        # Fallback to global queue
        status_info = get_job_status(job_id)

    return jsonify(status_info)


@app.route('/api/jobs/<job_id>/apply', methods=['POST'])
def apply_job_result(job_id):
    """
    Take the result of a finished job and apply it to the user's session.
    This is necessary because workers don't share the Flask session.
    """
    user_id = get_or_create_user_id()

    # Try user-specific job first, fallback to global
    status_info = user_queue_manager.get_user_job_status(user_id, job_id)
    if status_info['status'] == 'not_found' and task_queue:
        # Fallback to global queue
        status_info = get_job_status(job_id)

    if status_info['status'] != 'finished':
        return jsonify({'error': 'Job not finished or not found'}), 400

    result = status_info['result']
    if not result.get('success'):
        return jsonify({'error': result.get('error', 'Job failed')}), 500

    # Apply based on what kind of job it was
    if 'raw_events' in result:
        user_manager.update_user_session(user_id,
            events=result['raw_events'],
            heat_sheets=None
        )
    elif 'heat_sheets' in result:
        user_manager.update_user_session(user_id, heat_sheets=result['heat_sheets'])
    
    return jsonify({'success': True, 'user_id': user_id})


@app.route('/api/jobs/<job_id>/cancel', methods=['POST'])
def cancel_job(job_id):
    """Cancel a user's job."""
    user_id = get_or_create_user_id()

    success = user_queue_manager.cancel_user_job(user_id, job_id)
    if success:
        return jsonify({'success': True, 'message': 'Job cancelled'})
    else:
        return jsonify({'error': 'Job not found or could not be cancelled'}), 400


@app.route('/api/queue/stats', methods=['GET'])
def queue_stats():
    """Get queue statistics for the current user."""
    user_id = get_or_create_user_id()

    stats = user_queue_manager.get_user_queue_stats(user_id)
    return jsonify(stats)


@app.route('/api/queue/cleanup', methods=['POST'])
def cleanup_user_queue():
    """Clean up old jobs for the current user."""
    user_id = get_or_create_user_id()

    cleaned = user_queue_manager.cleanup_user_jobs(user_id)
    return jsonify({'success': True, 'jobs_cleaned': cleaned})

