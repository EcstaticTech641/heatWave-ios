# Deployment and Distribution Guide

This guide covers how to deploy **heatWave** as a public-facing web app and how to package it for desktop distribution.

## 1. Public Web Deployment (Linux / Windows Server)

For a secure, public-facing web app, we recommend using a reverse proxy (like Nginx) and a WSGI server (`waitress`).

### Prerequisites
- Python 3.10+
- **Redis Server** (for task queuing and sessions)
- (Optional but recommended) Nginx or Apache for reverse proxy.

### Steps
1. **Clone and Setup**:
   ```bash
   git clone <your-repo-url>
   cd heatWave
   python -m venv .venv
   source .venv/bin/activate  # or .venv\Scripts\activate on Windows
   pip install -r requirements.txt
   ```

2. **Configuration**:
   Create a `.env` file in the root directory:
   ```env
   SECRET_KEY=your-random-secret-key-here
   PORT=8080
   HOST=0.0.0.0
   REDIS_URL=redis://localhost:6379/0
   ```

3. **Run the Services**:
   You need to run both the web server and at least one worker process.

   **Terminal 1 (Web Server):**
   ```bash
   python run_server.py
   ```

   **Terminal 2 (Worker):**
   ```bash
   python run_worker.py
   ```

4. **Reverse Proxy (Nginx Example)**:
   Configure Nginx to forward requests to port 8080. Ensure you handle large file uploads (max 50MB is set in the app).
   ```nginx
   server {
       listen 80;
       server_name your-domain.com;
       client_max_body_size 50M;

       location / {
           proxy_pass http://127.0.0.1:8080;
           proxy_set_header Host $host;
           proxy_set_header X-Real-IP $remote_addr;
           proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
           proxy_set_header X-Forwarded-Proto $scheme;
       }
   }
   ```

---

## 2. Portable Desktop Release (Windows)

We use PyInstaller to package the app into a standalone folder that can be zipped and shared.

### Steps
1. **Setup Environment**:
   Ensure you are in a Windows environment with the dependencies installed.
   ```powershell
   pip install -r requirements.txt
   pip install pyinstaller
   ```

2. **Build the Executable**:
   Run PyInstaller using the provided `.spec` file:
   ```powershell
   pyinstaller --clean heatWave.spec
   ```

3. **Distribution**:
   - The output will be in the `dist/heatWave/` directory.
   - Zip the `heatWave` folder and share it with users.
   - Users can run `heatWave.exe` to launch the application.

### Debugging the Build
If the application fails to launch or behaves unexpectedly:
1. Edit `heatWave.spec` and set `console=True`.
2. Re-run `pyinstaller --clean heatWave.spec`.
3. Launch the `.exe` from a terminal to see error logs.

---

## Security & Robustness
- **Data Privacy**: This app stores temporary session data in Redis or the system's temp folder. Ensure Redis is secured (e.g., password protected, not exposed publicly).
- **HTTPS**: Always serve the public web app over HTTPS. The app is configured with `ProxyFix` to respect headers from your load balancer.
- **Queue Fairness & CPU Protection**: 
  - Each job has a 5-minute timeout to prevent runaway processes.
  - Rate limiting is enforced via `Flask-Limiter` to prevent API abuse.
  - To increase throughput, start multiple `run_worker.py` instances.
  - To protect CPU, limit the number of worker instances to your available core count.
