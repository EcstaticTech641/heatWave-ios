"""
User session management for multi-user server isolation.
Provides secure user identification and session handling.
"""
import os
import uuid
import hashlib
import json
import pickle
from datetime import datetime, timedelta
from typing import Optional, Dict, Any
import logging
from pathlib import Path
import tempfile

logger = logging.getLogger(__name__)

class UserManager:
    """
    Manages user sessions and identification for the heatWave server.
    Provides secure, anonymous user isolation.
    """

    def __init__(self, redis_conn=None, session_timeout_hours: int = 2):
        """
        Initialize the user manager.

        Args:
            redis_conn: Redis connection for distributed sessions (optional)
            session_timeout_hours: Hours before session expires
        """
        self.redis_conn = redis_conn
        self.session_timeout = timedelta(hours=session_timeout_hours)

        # Fallback storage if no Redis
        self._local_sessions = {}
        self._local_storage_path = Path(tempfile.gettempdir()) / 'heatwave_sessions'
        self._local_storage_path.mkdir(exist_ok=True)

    def create_user_session(self, client_ip: str = None, user_agent: str = None) -> str:
        """
        Create a new user session and return the user ID.

        Args:
            client_ip: Client IP address for logging
            user_agent: User agent string for logging

        Returns:
            Unique user ID string
        """
        user_id = str(uuid.uuid4())
        session_data = {
            'user_id': user_id,
            'created_at': datetime.now().isoformat(),
            'last_accessed': datetime.now().isoformat(),
            'client_ip': client_ip,
            'user_agent': user_agent,
            'events': None,
            'heat_sheets': None
        }

        self._store_session(user_id, session_data)
        logger.info(f"Created new user session: {user_id}")
        return user_id

    def ensure_user_session(self, user_id: str, client_ip: str = None, user_agent: str = None) -> str:
        """
        Ensure a session exists for a specific user_id.
        Useful when clients provide a stable ID via headers/cookies.
        """
        session_data = self.get_user_session(user_id)
        if session_data:
            return user_id

        # Create new if not found or expired
        session_data = {
            'user_id': user_id,
            'created_at': datetime.now().isoformat(),
            'last_accessed': datetime.now().isoformat(),
            'client_ip': client_ip,
            'user_agent': user_agent,
            'events': None,
            'heat_sheets': None
        }
        self._store_session(user_id, session_data)
        logger.info(f"Initialized fresh user session: {user_id}")
        return user_id

    def get_user_session(self, user_id: str) -> Optional[Dict[str, Any]]:
        """
        Retrieve user session data.

        Args:
            user_id: User ID to retrieve

        Returns:
            Session data dict or None if not found/expired
        """
        session_data = self._load_session(user_id)
        if not session_data:
            return None

        # Check if session expired (sliding window based on last_accessed)
        last_accessed = datetime.fromisoformat(session_data.get('last_accessed', session_data['created_at']))
        if datetime.now() - last_accessed > self.session_timeout:
            logger.info(f"Session expired: {user_id}")
            self.delete_user_session(user_id)
            return None

        # Update last accessed time
        session_data['last_accessed'] = datetime.now().isoformat()
        self._store_session(user_id, session_data)

        return session_data

    def update_user_session(self, user_id: str, **updates) -> bool:
        """
        Update user session data.

        Args:
            user_id: User ID to update
            **updates: Key-value pairs to update

        Returns:
            True if successful, False otherwise
        """
        session_data = self._load_session(user_id)
        if not session_data:
            return False

        # Update the session
        session_data.update(updates)
        session_data['last_accessed'] = datetime.now().isoformat()

        self._store_session(user_id, session_data)
        return True

    def delete_user_session(self, user_id: str) -> bool:
        """
        Delete a user session.

        Args:
            user_id: User ID to delete

        Returns:
            True if successful, False otherwise
        """
        if self.redis_conn:
            try:
                self.redis_conn.delete(f"heatwave:session:{user_id}")
                logger.info(f"Deleted Redis session: {user_id}")
                return True
            except Exception as e:
                logger.error(f"Error deleting Redis session {user_id}: {e}")
                return False
        else:
            # Local storage
            session_file_json = self._local_storage_path / f"{user_id}.json"
            session_file_pkl = self._local_storage_path / f"{user_id}.pkl"
            try:
                if session_file_json.exists():
                    session_file_json.unlink()
                if session_file_pkl.exists():
                    session_file_pkl.unlink()
                
                # Also remove from memory
                if user_id in self._local_sessions:
                    del self._local_sessions[user_id]
                    
                logger.info(f"Deleted local session: {user_id}")
                return True
            except Exception as e:
                logger.error(f"Error deleting local session {user_id}: {e}")
                return False

        return False

    def cleanup_expired_sessions(self) -> int:
        """
        Clean up expired sessions.

        Returns:
            Number of sessions cleaned up
        """
        cleaned = 0

        if self.redis_conn:
            try:
                # Get all session keys
                keys = self.redis_conn.keys("heatwave:session:*")
                for key in keys:
                    user_id = key.decode().split(":")[-1]
                    session_data = self._load_session(user_id)
                    if session_data:
                        last_accessed = datetime.fromisoformat(session_data.get('last_accessed', session_data['created_at']))
                        if datetime.now() - last_accessed > self.session_timeout:
                            self.redis_conn.delete(key)
                            cleaned += 1
            except Exception as e:
                logger.error(f"Error cleaning Redis sessions: {e}")
        else:
            # Local cleanup
            try:
                # Clean up both .json and .pkl
                for session_file in self._local_storage_path.glob("*"):
                    if session_file.suffix not in ('.json', '.pkl'):
                        continue
                        
                    try:
                        # Use file modification time as a proxy for last activity
                        mtime = datetime.fromtimestamp(session_file.stat().st_mtime)
                        if datetime.now() - mtime > self.session_timeout:
                            session_file.unlink()
                            cleaned += 1
                    except Exception as e:
                        logger.warning(f"Error cleaning session file {session_file}: {e}")
            except Exception as e:
                logger.error(f"Error cleaning local sessions: {e}")

        if cleaned > 0:
            logger.info(f"Cleaned up {cleaned} expired sessions")

        return cleaned

    def _store_session(self, user_id: str, session_data: Dict[str, Any]):
        """Store session data."""
        if self.redis_conn:
            try:
                # Use pickle for Redis to preserve complex object graphs (Pydantic models)
                # which are not directly JSON-serializable.
                self.redis_conn.setex(
                    f"heatwave:session:{user_id}",
                    int(self.session_timeout.total_seconds()),
                    pickle.dumps(session_data)
                )
            except Exception as e:
                logger.error(f"Error storing Redis session {user_id}: {e}")
        else:
            # In-process storage (primary for no-Redis mode)
            self._local_sessions[user_id] = session_data

            # Save full pickle snapshot and a best-effort JSON for debugging
            session_file_json = self._local_storage_path / f"{user_id}.json"
            session_file_pkl = self._local_storage_path / f"{user_id}.pkl"
            
            try:
                # Store full state in pickle
                with open(session_file_pkl, 'wb') as f:
                    pickle.dump(session_data, f)
                
                # Store metadata-only in JSON for human inspection
                snapshot = {k: v for k, v in session_data.items() if k not in ('events', 'heat_sheets')}
                with open(session_file_json, 'w', encoding='utf-8') as f:
                    json.dump(snapshot, f, indent=2)
            except Exception as e:
                logger.error(f"Error storing local session snapshot {user_id}: {e}")

    def _load_session(self, user_id: str) -> Optional[Dict[str, Any]]:
        """Load session data."""
        if self.redis_conn:
            try:
                data = self.redis_conn.get(f"heatwave:session:{user_id}")
                return pickle.loads(data) if data else None
            except Exception as e:
                logger.error(f"Error loading Redis session {user_id}: {e}")
                return None
        else:
            # In-process storage (preferred)
            session_data = self._local_sessions.get(user_id)
            if session_data:
                return session_data

            # Fallback: full pickle snapshot
            session_file_pkl = self._local_storage_path / f"{user_id}.pkl"
            if session_file_pkl.exists():
                try:
                    with open(session_file_pkl, 'rb') as f:
                        return pickle.load(f)
                except Exception as e:
                    logger.error(f"Error loading local pickle session {user_id}: {e}")

            # Last resort: JSON metadata (note: does not include events/heat_sheets)
            session_file_json = self._local_storage_path / f"{user_id}.json"
            try:
                if session_file_json.exists():
                    with open(session_file_json, 'r', encoding='utf-8') as f:
                        return json.load(f)
            except Exception as e:
                logger.error(f"Error loading local session metadata {user_id}: {e}")
                return None

        return None