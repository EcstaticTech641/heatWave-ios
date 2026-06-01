
import requests
import os
import sys
import json
import time

BASE_URL = "http://127.0.0.1:5000"
SAMPLE_PDF = r"r:\aaron\programs\heatWave\data\samples\1769543968773-7a7qa8q6s.pdf"

def debug_cycle():
    print(f"--- Starting Debug Cycle ---")
    session = requests.Session()
    
    # 1. Get initial status / session
    print("1. Fetching initial status...")
    resp = session.get(f"{BASE_URL}/api/status")
    print(f"Status Code: {resp.status_code}")
    data = resp.json()
    user_id = data.get('user_id')
    server_pid = data.get('server_pid')
    print(f"User ID: {user_id}")
    print(f"Server PID: {server_pid}")
    print(f"Initial State: has_events={data.get('has_events')}")

    # 2. Upload PDF
    print("\n2. Uploading PDF...")
    with open(SAMPLE_PDF, 'rb') as f:
        files = {'file': (os.path.basename(SAMPLE_PDF), f, 'application/pdf')}
        resp = session.post(f"{BASE_URL}/api/upload", files=files)
    
    print(f"Status Code: {resp.status_code}")
    upload_data = resp.json()
    if resp.status_code != 200:
        print(f"Upload failed: {upload_data}")
        return

    # Handle async if necessary
    if upload_data.get('async'):
        job_id = upload_data.get('job_id')
        print(f"Async job started: {job_id}. Polling...")
        while True:
            job_resp = session.get(f"{BASE_URL}/api/jobs/{job_id}")
            job_status = job_resp.json()
            print(f"Job Status: {job_status.get('status')}")
            if job_status.get('status') == 'finished':
                # Apply
                session.post(f"{BASE_URL}/api/jobs/{job_id}/apply")
                break
            if job_status.get('status') in ['failed', 'error']:
                print(f"Job failed: {job_status}")
                return
            time.sleep(1)

    # 3. Check status again
    print("\n3. Verifying status after upload...")
    resp = session.get(f"{BASE_URL}/api/status")
    data = resp.json()
    print(f"Status Code: {resp.status_code}")
    print(f"Server PID: {data.get('server_pid')}")
    print(f"Post-Upload State: has_events={data.get('has_events')}, event_count={data.get('event_count')}")

    if not data.get('has_events'):
        print("ERROR: Session does not have events after successful upload!")
        return

    # 4. Try to generate
    print("\n4. Calling /api/generate...")
    resp = session.post(f"{BASE_URL}/api/generate", json={'lanes': 8})
    print(f"Status Code: {resp.status_code}")
    gen_data = resp.json()
    if resp.status_code == 200:
        print("SUCCESS: Heat sheets generated!")
    else:
        print(f"FAILURE: {gen_data}")

if __name__ == "__main__":
    try:
        debug_cycle()
    except Exception as e:
        print(f"Script error: {e}")
