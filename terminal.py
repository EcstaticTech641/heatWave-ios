#!/usr/bin/env python
"""
heatWave Terminal Interface

Command-line interface for power users and AI agents.
Provides direct access to heatWave functionality without the web UI.

Usage:
    python terminal.py --help
    python terminal.py upload path/to/psych.pdf
    python terminal.py generate --lanes 8
    python terminal.py download full
    python terminal.py status
"""
import sys
import os
import argparse
import requests
import json
import time
from pathlib import Path
from typing import Optional, Dict, Any

# Add project root to path
project_root = os.path.dirname(os.path.abspath(__file__))
if project_root not in sys.path:
    sys.path.insert(0, project_root)


class HeatWaveTerminal:
    """Terminal interface for heatWave operations."""

    def __init__(self, host: str = '127.0.0.1', port: int = 5000, verbose: bool = False):
        self.base_url = f'http://{host}:{port}'
        self.session = requests.Session()
        self.verbose = verbose
        self.user_id: Optional[str] = None

        # Get or create user session
        self._init_session()

    def _apply_job(self, job_id: str) -> None:
        """Apply a finished job result to the user's server-side session."""
        resp = self.session.post(f'{self.base_url}/api/jobs/{job_id}/apply')
        if resp.status_code != 200 and self.verbose:
            print(f"⚠️  Could not apply job result to session (HTTP {resp.status_code})")

    def _init_session(self):
        """Initialize user session."""
        try:
            response = self.session.get(f'{self.base_url}/api/status')
            if response.status_code == 200:
                data = response.json()
                self.user_id = data.get('user_id')
                if self.verbose:
                    print(f"🔑 User session: {self.user_id}")
            else:
                print(f"❌ Failed to initialize session: {response.status_code}")
        except Exception as e:
            print(f"❌ Cannot connect to server at {self.base_url}")
            print(f"   Make sure the server is running: python run_server_headless.py")
            sys.exit(1)

    def _wait_for_job(self, job_id: str, timeout: int = 300) -> Dict[str, Any]:
        """Wait for a job to complete."""
        start_time = time.time()

        while time.time() - start_time < timeout:
            response = self.session.get(f'{self.base_url}/api/jobs/{job_id}')
            if response.status_code != 200:
                return {'status': 'error', 'error': f'HTTP {response.status_code}'}

            job_data = response.json()
            status = job_data.get('status')

            if status == 'finished':
                return job_data
            elif status == 'failed':
                return job_data
            elif status == 'not_found':
                return job_data

            if self.verbose:
                print(f"⏳ Job {job_id}: {status}")
            time.sleep(1)

        return {'status': 'timeout', 'error': 'Job timed out'}

    def upload_pdf(self, pdf_path: str) -> bool:
        """Upload and parse a PDF file."""
        pdf_file = Path(pdf_path)
        if not pdf_file.exists():
            print(f"❌ File not found: {pdf_path}")
            return False

        print(f"📤 Uploading: {pdf_file.name}")

        with open(pdf_file, 'rb') as f:
            # Flask expects request.files['file'] (matches browser UI)
            files = {'file': (pdf_file.name, f, 'application/pdf')}
            response = self.session.post(f'{self.base_url}/api/upload', files=files)

        if response.status_code != 200:
            print(f"❌ Upload failed: {response.status_code}")
            print(response.text)
            return False

        data = response.json()
        if data.get('async'):
            job_id = data.get('job_id')
            print(f"🔄 Processing asynchronously (Job ID: {job_id})")

            # Wait for completion
            job_result = self._wait_for_job(job_id)
            if job_result.get('status') == 'finished':
                result = job_result.get('result', {})
                if result.get('success'):
                    self._apply_job(job_id)
                    print("✅ PDF parsed successfully!")
                    print(f"   Events: {result.get('event_count', 0)}")
                    print(f"   Entries: {result.get('total_entries', 0)}")
                    return True
                else:
                    print(f"❌ Processing failed: {result.get('error', 'Unknown error')}")
                    return False
            else:
                print(f"❌ Job failed: {job_result.get('status')}")
                return False
        else:
            # Synchronous result
            if data.get('success'):
                print("✅ PDF parsed successfully!")
                print(f"   Events: {data.get('event_count', 0)}")
                print(f"   Entries: {data.get('total_entries', 0)}")
                return True
            else:
                print(f"❌ Processing failed: {data.get('error', 'Unknown error')}")
                return False

    def generate_heats(self, lanes: int = 8) -> bool:
        """Generate heat sheets."""
        print(f"🏊 Generating heat sheets (lanes: {lanes})")

        payload = {'lanes': lanes}
        response = self.session.post(f'{self.base_url}/api/generate', json=payload)

        if response.status_code != 200:
            print(f"❌ Generation failed: {response.status_code}")
            print(response.text)
            return False

        data = response.json()
        if data.get('async'):
            job_id = data.get('job_id')
            print(f"🔄 Generating asynchronously (Job ID: {job_id})")

            # Wait for completion
            job_result = self._wait_for_job(job_id)
            if job_result.get('status') == 'finished':
                result = job_result.get('result', {})
                if result.get('success'):
                    self._apply_job(job_id)
                    print("✅ Heat sheets generated successfully!")
                    print(f"   Events: {result.get('event_count', 0)}")
                    print(f"   Heats: {result.get('total_heats', 0)}")
                    print(f"   Entries: {result.get('total_entries', 0)}")
                    return True
                else:
                    print(f"❌ Generation failed: {result.get('error', 'Unknown error')}")
                    return False
            else:
                print(f"❌ Job failed: {job_result.get('status')}")
                return False
        else:
            # Synchronous result
            if data.get('success'):
                print("✅ Heat sheets generated successfully!")
                print(f"   Events: {data.get('event_count', 0)}")
                print(f"   Heats: {data.get('total_heats', 0)}")
                print(f"   Entries: {data.get('total_entries', 0)}")
                return True
            else:
                print(f"❌ Generation failed: {data.get('error', 'Unknown error')}")
                return False

    def download_full(self, output_path: Optional[str] = None) -> bool:
        """Download the full meet PDF."""
        if output_path:
            output_file = Path(output_path)
        else:
            output_file = Path(f"Full_Meet_Heatsheets_{self.user_id[:8]}.pdf")

        print(f"📥 Downloading full meet PDF to: {output_file}")

        response = self.session.get(f'{self.base_url}/api/download/full')

        if response.status_code != 200:
            print(f"❌ Download failed: {response.status_code}")
            print(response.text)
            return False

        with open(output_file, 'wb') as f:
            f.write(response.content)

        print(f"✅ Downloaded {len(response.content)} bytes")
        return True

    def download_event(self, event_num: int, output_path: Optional[str] = None) -> bool:
        """Download a specific event PDF."""
        if output_path:
            output_file = Path(output_path)
        else:
            output_file = Path(f"Event_{event_num:02d}_Heatsheet_{self.user_id[:8]}.pdf")

        print(f"📥 Downloading event {event_num} PDF to: {output_file}")

        response = self.session.get(f'{self.base_url}/api/download/event/{event_num}')

        if response.status_code != 200:
            print(f"❌ Download failed: {response.status_code}")
            print(response.text)
            return False

        with open(output_file, 'wb') as f:
            f.write(response.content)

        print(f"✅ Downloaded {len(response.content)} bytes")
        return True

    def get_status(self) -> Dict[str, Any]:
        """Get current session status."""
        response = self.session.get(f'{self.base_url}/api/status')
        if response.status_code == 200:
            return response.json()
        else:
            return {'error': f'HTTP {response.status_code}'}

    def cancel_job(self, job_id: str) -> bool:
        """Cancel a job."""
        response = self.session.post(f'{self.base_url}/api/jobs/{job_id}/cancel')
        if response.status_code == 200:
            data = response.json()
            if data.get('success'):
                print(f"✅ Job {job_id} cancelled")
                return True
            else:
                print(f"❌ Failed to cancel job: {data.get('error')}")
                return False
        else:
            print(f"❌ Cancel failed: {response.status_code}")
            return False

    def cleanup_queue(self) -> bool:
        """Clean up old jobs."""
        response = self.session.post(f'{self.base_url}/api/queue/cleanup')
        if response.status_code == 200:
            data = response.json()
            cleaned = data.get('jobs_cleaned', 0)
            print(f"🧹 Cleaned up {cleaned} old jobs")
            return True
        else:
            print(f"❌ Cleanup failed: {response.status_code}")
            return False


def main():
    parser = argparse.ArgumentParser(
        description='heatWave Terminal Interface',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  python terminal.py upload psych_sheet.pdf
  python terminal.py generate --lanes 8
  python terminal.py download full --output meet.pdf
  python terminal.py download event 5 --output event5.pdf
  python terminal.py status
  python terminal.py cancel job_123
  python terminal.py cleanup
        """
    )

    parser.add_argument('--host', default='127.0.0.1', help='Server host (default: 127.0.0.1)')
    parser.add_argument('--port', type=int, default=5000, help='Server port (default: 5000)')
    parser.add_argument('--verbose', '-v', action='store_true', help='Verbose output')

    subparsers = parser.add_subparsers(dest='command', help='Available commands')

    # Upload command
    upload_parser = subparsers.add_parser('upload', help='Upload and parse PDF')
    upload_parser.add_argument('pdf_path', help='Path to PDF file')

    # Generate command
    generate_parser = subparsers.add_parser('generate', help='Generate heat sheets')
    generate_parser.add_argument('--lanes', type=int, default=8, help='Number of lanes (default: 8)')

    # Download command
    download_parser = subparsers.add_parser('download', help='Download PDFs')
    download_parser.add_argument('type', choices=['full', 'event'], help='Download type')
    download_parser.add_argument('event_num', type=int, nargs='?', help='Event number (for event downloads)')
    download_parser.add_argument('--output', '-o', help='Output file path')

    # Status command
    subparsers.add_parser('status', help='Show session status')

    # Cancel command
    cancel_parser = subparsers.add_parser('cancel', help='Cancel a job')
    cancel_parser.add_argument('job_id', help='Job ID to cancel')

    # Cleanup command
    subparsers.add_parser('cleanup', help='Clean up old jobs')

    args = parser.parse_args()

    if not args.command:
        parser.print_help()
        return

    # Initialize terminal interface
    terminal = HeatWaveTerminal(host=args.host, port=args.port, verbose=args.verbose)

    # Execute command
    try:
        if args.command == 'upload':
            success = terminal.upload_pdf(args.pdf_path)
        elif args.command == 'generate':
            success = terminal.generate_heats(args.lanes)
        elif args.command == 'download':
            if args.type == 'full':
                success = terminal.download_full(args.output)
            elif args.type == 'event':
                if not args.event_num:
                    print("❌ Event number required for event downloads")
                    return
                success = terminal.download_event(args.event_num, args.output)
        elif args.command == 'status':
            status = terminal.get_status()
            print("📊 Session Status:")
            print(json.dumps(status, indent=2))
            success = True
        elif args.command == 'cancel':
            success = terminal.cancel_job(args.job_id)
        elif args.command == 'cleanup':
            success = terminal.cleanup_queue()

        sys.exit(0 if success else 1)

    except KeyboardInterrupt:
        print("\n👋 Cancelled by user")
        sys.exit(1)
    except Exception as e:
        print(f"❌ Error: {e}")
        sys.exit(1)


if __name__ == '__main__':
    main()