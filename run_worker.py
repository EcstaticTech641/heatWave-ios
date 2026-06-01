#!/usr/bin/env python
import os
import sys

# Add the project root to the python path
project_root = os.path.dirname(os.path.abspath(__file__))
if project_root not in sys.path:
    sys.path.insert(0, project_root)

from rq import Worker, Queue, Connection
from src.ui.queue_manager import redis_conn

def main():
    if not redis_conn:
        print("Error: Redis is not connected. Cannot start worker.")
        sys.exit(1)

    # Tell RQ what queue to listen to
    listen = ['heatwave-tasks']

    print(f"🚀 Starting RQ worker listening on {listen}")
    with Connection(redis_conn):
        worker = Worker(list(map(Queue, listen)))
        worker.work()

if __name__ == '__main__':
    main()
