"""
Per-user temporary directory management for secure file isolation.
Provides user-specific temp directories with automatic cleanup.
"""
import os
import shutil
import tempfile
import threading
import time
from pathlib import Path
from datetime import datetime, timedelta
from typing import Optional, Dict
import logging

logger = logging.getLogger(__name__)

class TempManager:
    """
    Manages per-user temporary directories for secure file isolation.
    Automatically cleans up old directories and files.
    """

    def __init__(self, base_temp_dir: str = None, cleanup_interval_minutes: int = 5,
                 max_age_hours: int = 1, user_timeout_hours: int = 2):
        """
        Initialize the temp manager.

        Args:
            base_temp_dir: Base directory for temp files (default: system temp)
            cleanup_interval_minutes: How often to run cleanup
            max_age_hours: Maximum age of files to keep
            user_timeout_hours: Hours before user dirs are cleaned
        """
        self.base_temp_dir = Path(base_temp_dir or tempfile.gettempdir()) / 'heatwave'
        self.users_dir = self.base_temp_dir / 'users'
        self.users_dir.mkdir(parents=True, exist_ok=True)

        self.max_age = timedelta(hours=max_age_hours)
        self.user_timeout = timedelta(hours=user_timeout_hours)
        self.cleanup_interval = cleanup_interval_minutes * 60

        # Track active users and their last access
        self._active_users: Dict[str, datetime] = {}
        self._lock = threading.Lock()

        # Start cleanup daemon
        self._cleanup_daemon = threading.Thread(
            target=self._cleanup_worker,
            daemon=True,
            name="TempCleanupDaemon"
        )
        self._cleanup_daemon.start()

        logger.info(f"TempManager initialized: base_dir={self.base_temp_dir}")

    def get_user_temp_dir(self, user_id: str) -> Path:
        """
        Get or create a user's temporary directory.

        Args:
            user_id: Unique user identifier

        Returns:
            Path to user's temp directory
        """
        user_dir = self.users_dir / user_id

        with self._lock:
            user_dir.mkdir(parents=True, exist_ok=True)
            self._active_users[user_id] = datetime.now()

        return user_dir

    def cleanup_user_temp_dir(self, user_id: str) -> bool:
        """
        Immediately clean up a user's temporary directory.

        Args:
            user_id: User ID to clean up

        Returns:
            True if successful, False otherwise
        """
        user_dir = self.users_dir / user_id

        try:
            if user_dir.exists():
                shutil.rmtree(user_dir)
                logger.info(f"Cleaned up temp directory for user: {user_id}")

            with self._lock:
                self._active_users.pop(user_id, None)

            return True
        except Exception as e:
            logger.error(f"Error cleaning up temp dir for user {user_id}: {e}")
            return False

    def cleanup_old_files(self, user_dir: Path) -> int:
        """
        Clean up old files in a user's directory.

        Args:
            user_dir: User directory to clean

        Returns:
            Number of files deleted
        """
        if not user_dir.exists():
            return 0

        deleted_count = 0
        cutoff_time = datetime.now() - self.max_age

        try:
            # Clean up PDF files
            for pdf_file in user_dir.glob("*.pdf"):
                try:
                    mtime = datetime.fromtimestamp(pdf_file.stat().st_mtime)
                    if mtime < cutoff_time:
                        pdf_file.unlink()
                        deleted_count += 1
                        logger.debug(f"Deleted old PDF: {pdf_file}")
                except Exception as e:
                    logger.warning(f"Could not delete {pdf_file}: {e}")

            # Clean up temp files
            for temp_file in user_dir.glob("tmp_*"):
                try:
                    mtime = datetime.fromtimestamp(temp_file.stat().st_mtime)
                    if mtime < cutoff_time:
                        temp_file.unlink()
                        deleted_count += 1
                        logger.debug(f"Deleted old temp file: {temp_file}")
                except Exception as e:
                    logger.warning(f"Could not delete {temp_file}: {e}")

        except Exception as e:
            logger.error(f"Error during cleanup of {user_dir}: {e}")

        return deleted_count

    def _cleanup_worker(self):
        """Background cleanup worker."""
        logger.info("Temp cleanup daemon started")

        while True:
            try:
                self._perform_cleanup()
            except Exception as e:
                logger.error(f"Error in cleanup worker: {e}")

            time.sleep(self.cleanup_interval)

    def _perform_cleanup(self):
        """Perform cleanup operations."""
        total_deleted = 0
        users_cleaned = 0

        # Clean up inactive user directories
        with self._lock:
            current_time = datetime.now()
            inactive_users = []

            for user_id, last_access in self._active_users.items():
                if current_time - last_access > self.user_timeout:
                    inactive_users.append(user_id)

        for user_id in inactive_users:
            if self.cleanup_user_temp_dir(user_id):
                users_cleaned += 1

        # Clean up old files in remaining user directories
        try:
            for user_dir in self.users_dir.iterdir():
                if user_dir.is_dir():
                    deleted = self.cleanup_old_files(user_dir)
                    total_deleted += deleted

                    # Remove empty directories
                    try:
                        if not any(user_dir.iterdir()):
                            user_dir.rmdir()
                    except Exception as e:
                        logger.debug(f"Could not remove empty dir {user_dir}: {e}")

        except Exception as e:
            logger.error(f"Error during directory cleanup: {e}")

        if total_deleted > 0 or users_cleaned > 0:
            logger.info(f"Cleanup: removed {total_deleted} files, {users_cleaned} user dirs")

    def get_stats(self) -> Dict[str, int]:
        """
        Get statistics about temp directory usage.

        Returns:
            Dict with stats
        """
        try:
            total_users = 0
            total_files = 0
            total_size = 0

            for user_dir in self.users_dir.iterdir():
                if user_dir.is_dir():
                    total_users += 1
                    for file_path in user_dir.rglob("*"):
                        if file_path.is_file():
                            total_files += 1
                            try:
                                total_size += file_path.stat().st_size
                            except Exception:
                                pass

            return {
                'active_users': len(self._active_users),
                'total_user_dirs': total_users,
                'total_files': total_files,
                'total_size_mb': total_size / (1024 * 1024)
            }
        except Exception as e:
            logger.error(f"Error getting stats: {e}")
            return {'error': str(e)}


# Backwards-compatible module-level singleton used by worker tasks.
# (Some modules import `temp_manager` directly.)
temp_manager = TempManager()