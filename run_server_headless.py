#!/usr/bin/env python
"""
Headless server launcher for heatWave.

Runs the Flask server without GUI, perfect for server deployment.
Opens browser automatically for easy access.

Usage:
    python run_server_headless.py          # development
    python run_server_headless.py --port 8080  # custom port
    python run_server_headless.py --host 0.0.0.0  # bind to all interfaces
"""
import sys
import os
import argparse
import threading
import logging
import webbrowser
import time
import socket
from urllib.request import urlopen
from urllib.error import URLError
from pathlib import Path

# Suppress noisy logs
logging.getLogger('werkzeug').setLevel(logging.WARNING)


def _resolve_paths():
    """Set the working directory correctly for both dev and frozen modes."""
    if getattr(sys, 'frozen', False):
        # Running as PyInstaller .exe — chdir to the exe's folder
        app_dir = os.path.dirname(sys.executable)
        os.chdir(app_dir)

        # Ensure the project root is importable (for `from src.…` imports)
        internal_dir = os.path.join(app_dir, '_internal')
        if internal_dir not in sys.path:
            sys.path.insert(0, internal_dir)
    else:
        # Running as script — make sure project root is on sys.path
        project_root = os.path.dirname(os.path.abspath(__file__))
        if project_root not in sys.path:
            sys.path.insert(0, project_root)


def _startup_banner(host: str, port: int) -> None:
    print(f"Starting heatWave server on http://{host}:{port}")
    print(f"Working directory: {os.getcwd()}")
    print("User isolation: Enabled")
    print("Queue management: Enabled")
    print()


def _start_flask(host='127.0.0.1', port=5000):
    """Start the Flask development server (dev only)."""
    from src.ui.flask_app import app
    _startup_banner(host, port)
    app.run(host=host, port=port, debug=False, use_reloader=False)

def _start_waitress(host='127.0.0.1', port=5000, threads: int = 4):
    """Start a production WSGI server (good behind reverse proxies)."""
    from waitress import serve
    from src.ui.flask_app import app
    _startup_banner(host, port)
    serve(app, host=host, port=port, threads=threads)


def _is_port_open(host: str, port: int) -> bool:
    try:
        with socket.create_connection((host, port), timeout=0.2):
            return True
    except OSError:
        return False


def _wait_until_ready(url: str, timeout_s: float = 15.0) -> bool:
    """
    Wait until the server is reachable.
    We first wait for the TCP port, then for an HTTP endpoint to respond.
    """
    deadline = time.time() + timeout_s

    # TCP readiness
    host = url.split("://", 1)[-1].split("/", 1)[0].split(":", 1)[0]
    port_str = url.split("://", 1)[-1].split("/", 1)[0].split(":", 1)[1]
    port = int(port_str)
    while time.time() < deadline:
        if _is_port_open(host, port):
            break
        time.sleep(0.1)

    # HTTP readiness (prefer a cheap JSON endpoint)
    probe = url.rstrip("/") + "/api/status"
    while time.time() < deadline:
        try:
            with urlopen(probe, timeout=0.5) as resp:
                if 200 <= resp.status < 500:
                    return True
        except URLError:
            pass
        time.sleep(0.15)

    return False


def main():
    parser = argparse.ArgumentParser(description='heatWave Headless Server')
    parser.add_argument('--host', default='127.0.0.1',
                       help='Host to bind to (default: 127.0.0.1)')
    parser.add_argument('--port', type=int, default=5000,
                       help='Port to bind to (default: 5000)')
    parser.add_argument('--dev', action='store_true',
                       help='Use Flask development server (default: auto)')
    parser.add_argument('--threads', type=int, default=int(os.environ.get('THREADS', 4)),
                       help='Waitress thread count (default: $THREADS or 4)')
    parser.add_argument('--no-browser', action='store_true',
                       help='Do not open browser automatically')
    parser.add_argument('--quiet', action='store_true',
                       help='Suppress startup messages')

    args = parser.parse_args()

    _resolve_paths()

    # Check for icon
    icon_path = Path('assets/icon.ico')
    if icon_path.exists():
        print(f"Found icon: {icon_path.absolute()}")
    else:
        print(f"Icon not found: {icon_path}")

    if not args.quiet:
        print("heatWave - Heat Sheet Generator (Headless Server)")
        print("=" * 55)
        print(f"Host: {args.host}")
        print(f"Port: {args.port}")
        print(f"Server: {'Flask (dev)' if args.dev else 'Waitress (auto)'}")
        print()

    # Decide server implementation.
    # - Default to Waitress for non-local binds (reverse proxy / hosted)
    # - Allow forcing Flask for local dev with --dev
    use_waitress = (not args.dev) and (args.host not in ('127.0.0.1', 'localhost'))

    # Start server
    server_thread = threading.Thread(
        target=_start_waitress if use_waitress else _start_flask,
        args=(args.host, args.port, args.threads) if use_waitress else (args.host, args.port),
        daemon=True,
    )
    server_thread.start()

    # Open browser
    if not args.no_browser:
        # If binding to all interfaces, opening 0.0.0.0 is not useful in a browser
        browser_host = '127.0.0.1' if args.host in ('0.0.0.0', '::') else args.host
        url = f'http://{browser_host}:{args.port}'
        if not args.quiet:
            print("Waiting for server...")
        ready = _wait_until_ready(url, timeout_s=20.0)
        if not args.quiet:
            if ready:
                print(f"Opening browser to {url}")
            else:
                print(f"Server not ready yet, opening anyway: {url}")
        try:
            webbrowser.open(url)
        except Exception as e:
            print(f"Could not open browser: {e}")

    if not args.quiet:
        print("Server started successfully!")
        print("Press Ctrl+C to stop the server")
        print()

    try:
        server_thread.join()   # keep alive
    except KeyboardInterrupt:
        print("\nServer stopped.")


if __name__ == '__main__':
    main()