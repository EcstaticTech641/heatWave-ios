import os
import redis
import json
from rq import Queue
from datetime import datetime, timedelta
from typing import Optional, Dict, Any, List
from dotenv import load_dotenv

load_dotenv()

# Redis Configuration
REDIS_URL = os.environ.get('REDIS_URL', 'redis://localhost:6379/0')

# Initialize Redis connection
try:
    redis_conn = redis.from_url(REDIS_URL)
    # Ping to verify connection
    redis_conn.ping()
    print(f"Connected to Redis at {REDIS_URL}")
except Exception as e:
    print(f"Warning: Could not connect to Redis: {e}")
    redis_conn = None

# Queue Configuration
DEFAULT_QUEUE_NAME = 'heatwave-tasks'
MAX_JOBS_PER_USER = int(os.environ.get('MAX_JOBS_PER_USER', 3))
JOB_TIMEOUT_SECONDS = int(os.environ.get('JOB_TIMEOUT_SECONDS', 300))  # 5 minutes
JOB_RESULT_TTL_SECONDS = int(os.environ.get('JOB_RESULT_TTL_SECONDS', 3600))  # 1 hour

# Initialize default RQ Queue (for backward compatibility)
task_queue = Queue(DEFAULT_QUEUE_NAME, connection=redis_conn) if redis_conn else None

class UserQueueManager:
    """
    Manages user-specific queues and jobs for multi-user isolation.
    """

    def __init__(self, redis_conn=None):
        self.redis_conn = redis_conn
        self._queues = {}  # Cache for RQ Queue objects

    def get_user_queue(self, user_id: str) -> Optional[Queue]:
        """
        Get or create a user-specific queue.

        Args:
            user_id: User identifier

        Returns:
            RQ Queue object or None if Redis not available
        """
        if not self.redis_conn:
            return None

        queue_name = f"heatwave-user-{user_id}"

        if queue_name not in self._queues:
            self._queues[queue_name] = Queue(queue_name, connection=self.redis_conn)

        return self._queues[queue_name]

    def enqueue_user_job(self, user_id: str, func, args=None, kwargs=None,
                        timeout=JOB_TIMEOUT_SECONDS, **job_kwargs) -> Optional[str]:
        """
        Enqueue a job for a specific user.

        Args:
            user_id: User identifier
            func: Function to execute
            args: Positional arguments
            kwargs: Keyword arguments
            timeout: Job timeout in seconds
            **job_kwargs: Additional RQ job parameters

        Returns:
            Job ID if successful, None otherwise
        """
        queue = self.get_user_queue(user_id)
        if not queue:
            return None

        # Check user's active job count
        active_jobs = self.get_user_active_jobs(user_id)
        if len(active_jobs) >= MAX_JOBS_PER_USER:
            return None  # User has too many active jobs

        try:
            job = queue.enqueue(
                func,
                args=args or [],
                kwargs=kwargs or {},
                job_timeout=timeout,
                **job_kwargs
            )
            return job.get_id()
        except Exception as e:
            print(f"Error enqueueing job for user {user_id}: {e}")
            return None

    def get_user_active_jobs(self, user_id: str) -> List[str]:
        """
        Get list of active job IDs for a user.

        Args:
            user_id: User identifier

        Returns:
            List of active job IDs
        """
        if not self.redis_conn:
            return []

        queue = self.get_user_queue(user_id)
        if not queue:
            return []

        try:
            # Get jobs from queue (this is approximate)
            jobs = queue.get_jobs()
            return [job.get_id() for job in jobs if job.get_status() in ['queued', 'started']]
        except Exception as e:
            print(f"Error getting active jobs for user {user_id}: {e}")
            return []

    def cancel_user_job(self, user_id: str, job_id: str) -> bool:
        """
        Cancel a user's job.

        Args:
            user_id: User identifier
            job_id: Job ID to cancel

        Returns:
            True if cancelled successfully, False otherwise
        """
        if not self.redis_conn:
            return False

        queue = self.get_user_queue(user_id)
        if not queue:
            return False

        try:
            job = queue.fetch_job(job_id)
            if job and job.get_status() in ['queued', 'started']:
                job.cancel()
                return True
        except Exception as e:
            print(f"Error cancelling job {job_id} for user {user_id}: {e}")

        return False

    def get_user_job_status(self, user_id: str, job_id: str) -> Dict[str, Any]:
        """
        Get status of a user's job.

        Args:
            user_id: User identifier
            job_id: Job ID

        Returns:
            Job status dictionary
        """
        if not self.redis_conn:
            return {'status': 'error', 'message': 'Redis not connected'}

        queue = self.get_user_queue(user_id)
        if not queue:
            return {'status': 'error', 'message': 'Queue not available'}

        try:
            job = queue.fetch_job(job_id)
            if not job:
                return {'status': 'not_found'}

            return {
                'id': job.get_id(),
                'status': job.get_status(),
                'result': job.result,
                'enqueued_at': job.enqueued_at.isoformat() if job.enqueued_at else None,
                'started_at': job.started_at.isoformat() if job.started_at else None,
                'ended_at': job.ended_at.isoformat() if job.ended_at else None,
                'exc_info': job.exc_info,
                'user_id': user_id
            }
        except Exception as e:
            return {'status': 'error', 'message': str(e)}

    def cleanup_user_jobs(self, user_id: str, max_age_hours: int = 24) -> int:
        """
        Clean up old completed jobs for a user.

        Args:
            user_id: User identifier
            max_age_hours: Maximum age of jobs to keep

        Returns:
            Number of jobs cleaned up
        """
        if not self.redis_conn:
            return 0

        queue = self.get_user_queue(user_id)
        if not queue:
            return 0

        try:
            jobs = queue.get_jobs()
            cutoff_time = datetime.now() - timedelta(hours=max_age_hours)
            cleaned = 0

            for job in jobs:
                if job.ended_at and job.ended_at < cutoff_time:
                    # Remove old completed job
                    job.delete()
                    cleaned += 1

            return cleaned
        except Exception as e:
            print(f"Error cleaning up jobs for user {user_id}: {e}")
            return 0

    def get_user_queue_stats(self, user_id: str) -> Dict[str, Any]:
        """
        Get statistics for a user's queue.

        Args:
            user_id: User identifier

        Returns:
            Queue statistics
        """
        if not self.redis_conn:
            return {'error': 'Redis not connected'}

        queue = self.get_user_queue(user_id)
        if not queue:
            return {'error': 'Queue not available'}

        try:
            jobs = queue.get_jobs()
            stats = {
                'user_id': user_id,
                'total_jobs': len(jobs),
                'queued_jobs': len([j for j in jobs if j.get_status() == 'queued']),
                'started_jobs': len([j for j in jobs if j.get_status() == 'started']),
                'finished_jobs': len([j for j in jobs if j.get_status() == 'finished']),
                'failed_jobs': len([j for j in jobs if j.get_status() == 'failed']),
            }
            return stats
        except Exception as e:
            return {'error': str(e)}

# Global user queue manager instance
user_queue_manager = UserQueueManager(redis_conn=redis_conn)

# Backward compatibility functions
def get_job_status(job_id):
    """Retrieve job status and results (backward compatibility)."""
    if not redis_conn:
        return {'status': 'error', 'message': 'Redis not connected'}

    job = task_queue.fetch_job(job_id)
    if not job:
        return {'status': 'not_found'}

    return {
        'id': job.get_id(),
        'status': job.get_status(),
        'result': job.result,
        'enqueued_at': job.enqueued_at.isoformat() if job.enqueued_at else None,
        'started_at': job.started_at.isoformat() if job.started_at else None,
        'ended_at': job.ended_at.isoformat() if job.ended_at else None,
        'exc_info': job.exc_info
    }
