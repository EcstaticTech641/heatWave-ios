import os
import tempfile
from pathlib import Path
from datetime import datetime
from src.parser.extractor import extract_text_from_pdf, parse_events_from_text
from src.seeding.seeder import seed_event
from src.core.pdf_generator import generate_full_meet_pdf, generate_heat_sheet_pdf
from src.models.schemas import Entry, RelayEntry

def parse_pdf_task(pdf_content, filename, user_id=None):
    """
    Task to parse a PDF psych sheet.
    pdf_content: bytes of the PDF file.
    filename: original filename
    user_id: user identifier for temp file isolation
    """
    from src.core.temp_manager import temp_manager

    try:
        # Use user-specific temp directory if user_id provided
        if user_id:
            user_temp_dir = temp_manager.get_user_temp_dir(user_id)
            with tempfile.NamedTemporaryFile(delete=False, suffix='.pdf', dir=user_temp_dir) as tmp:
                tmp.write(pdf_content)
                tmp_path = tmp.name
        else:
            # Fallback to global temp
            with tempfile.NamedTemporaryFile(delete=False, suffix='.pdf') as tmp:
                tmp.write(pdf_content)
                tmp_path = tmp.name

        text = extract_text_from_pdf(tmp_path)
        events = parse_events_from_text(text)
        Path(tmp_path).unlink(missing_ok=True)

        # Convert events to a serializable format for the job result
        # Note: session will still be used to store these for the user context
        # but the task returns them so the frontend can display them.
        events_summary = []
        for ev in events:
            entry_samples = []
            for e in ev.entries[:5]:
                if isinstance(e, Entry):
                    entry_samples.append({
                        'type': 'individual',
                        'name': e.swimmer.name,
                        'age': e.swimmer.age,
                        'team': e.swimmer.team_code,
                        'seed_time': e.seed_time,
                    })
                else:
                    entry_samples.append({
                        'type': 'relay',
                        'team': e.team_name,
                        'seed_time': e.seed_time,
                    })

            events_summary.append({
                'number': ev.number,
                'name': ev.name,
                'gender': ev.gender,
                'distance': ev.distance,
                'stroke': ev.stroke,
                'entry_count': len(ev.entries),
                'sample_entries': entry_samples,
            })

        return {
            'success': True,
            'filename': filename,
            'event_count': len(events),
            'total_entries': sum(len(ev.entries) for ev in events),
            'events_summary': events_summary,
            'raw_events': events # Note: This might be hard to serialize if complex. 
                                  # We might need to store it in a database or pickle it.
                                  # For now, let's assume RQ handles the pickle.
        }
    except Exception as e:
        return {'success': False, 'error': str(e)}

def seeding_task(events, num_lanes, user_id=None):
    """Task to seed events and generate heat sheet data."""
    try:
        heat_sheets = []
        summary = []
        for event in events:
            if event.entries:
                hs = seed_event(event, lanes=num_lanes)
                heat_sheets.append(hs)
                
                heats_by_num = {}
                for a in hs.assignments:
                    heats_by_num.setdefault(a.heat, []).append(a)
                heat_sizes = [len(heats_by_num.get(h, [])) for h in range(1, hs.heats + 1)]

                summary.append({
                    'event_number': hs.event.number,
                    'event_name': f"{hs.event.gender} {hs.event.distance}Y {hs.event.stroke}",
                    'heats': hs.heats,
                    'entries': len(hs.assignments),
                    'heat_distribution': heat_sizes,
                })

        return {
            'success': True,
            'heat_sheets': heat_sheets,
            'summary': summary,
            'total_heats': sum(hs.heats for hs in heat_sheets),
            'total_entries': sum(len(hs.assignments) for hs in heat_sheets),
        }
    except Exception as e:
        return {'success': False, 'error': str(e)}

def generate_pdf_task(heat_sheets, meet_title, meet_date, user_id=None):
    """Task to generate the final PDF."""
    from src.core.temp_manager import temp_manager

    try:
        if user_id:
            user_temp_dir = temp_manager.get_user_temp_dir(user_id)
            pdf_path = user_temp_dir / 'Heatsheets.pdf'
        else:
            # Fallback
            with tempfile.TemporaryDirectory() as tmpdir:
                pdf_path = Path(tmpdir) / 'Heatsheets.pdf'

        generate_full_meet_pdf(
            heat_sheets,
            str(pdf_path),
            meet_title=meet_title,
            meet_date=meet_date,
        )
        pdf_bytes = pdf_path.read_bytes()

        return {
            'success': True,
            'pdf_bytes': pdf_bytes,
            'filename': f"HeatSheet_{meet_title.replace(' ', '_')}.pdf"
        }
    except Exception as e:
        return {'success': False, 'error': str(e)}
