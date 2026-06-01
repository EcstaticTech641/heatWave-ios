#!/usr/bin/env python
"""
Test script for Point 1: User Isolation (Temp Dirs, Sessions)
Tests the new user management and temp directory isolation features.
"""
import os
import sys
import tempfile
import shutil
import json
from pathlib import Path
import time
from datetime import datetime, timedelta

# Add project root to path
project_root = Path(__file__).resolve().parent
if str(project_root) not in sys.path:
    sys.path.insert(0, str(project_root))

def test_user_manager():
    """Test UserManager functionality."""
    print("🧪 Testing UserManager...")

    from src.core.user_manager import UserManager

    # Test with local storage (no Redis)
    user_mgr = UserManager(redis_conn=None)

    # Test user creation
    user_id = user_mgr.create_user_session("127.0.0.1", "TestAgent/1.0")
    print(f"✅ Created user session: {user_id}")
    assert user_id, "User ID should not be empty"

    # Test session retrieval
    session = user_mgr.get_user_session(user_id)
    print(f"✅ Retrieved session: {session}")
    assert session, "Session should exist"
    assert session['user_id'] == user_id, "User ID should match"
    assert session['client_ip'] == "127.0.0.1", "IP should be stored"

    # Test session update
    success = user_mgr.update_user_session(user_id, events=["test_event"], heat_sheets=["test_sheet"])
    assert success, "Session update should succeed"

    session = user_mgr.get_user_session(user_id)
    assert session['events'] == ["test_event"], "Events should be updated"
    assert session['heat_sheets'] == ["test_sheet"], "Heat sheets should be updated"

    # Test session cleanup
    cleaned = user_mgr.cleanup_expired_sessions()
    print(f"✅ Cleaned {cleaned} expired sessions")

    # Test session deletion
    success = user_mgr.delete_user_session(user_id)
    assert success, "Session deletion should succeed"

    session = user_mgr.get_user_session(user_id)
    assert session is None, "Session should not exist after deletion"

    print("✅ UserManager tests passed!")
    return True

def test_temp_manager():
    """Test TempManager functionality."""
    print("🧪 Testing TempManager...")

    from src.core.temp_manager import TempManager

    # Create temp manager with short cleanup interval for testing
    temp_mgr = TempManager(cleanup_interval_minutes=0.1, max_age_hours=0.001)  # Very short for testing

    # Test user temp dir creation
    user_id = "test_user_123"
    user_dir = temp_mgr.get_user_temp_dir(user_id)
    print(f"✅ Created user temp dir: {user_dir}")
    assert user_dir.exists(), "User temp dir should exist"
    assert user_id in str(user_dir), "User ID should be in path"

    # Test file creation in user dir
    test_file = user_dir / "test.pdf"
    test_file.write_bytes(b"test pdf content")
    assert test_file.exists(), "Test file should be created"

    # Test stats
    stats = temp_mgr.get_stats()
    print(f"✅ Temp manager stats: {stats}")
    assert stats['active_users'] >= 1, "Should have at least one active user"

    # Test cleanup (wait a bit for cleanup daemon)
    time.sleep(1)  # Wait for cleanup daemon
    temp_mgr._perform_cleanup()  # Manual cleanup trigger

    # Test user cleanup
    success = temp_mgr.cleanup_user_temp_dir(user_id)
    assert success, "User cleanup should succeed"
    assert not user_dir.exists(), "User temp dir should be deleted after cleanup"

    print("✅ TempManager tests passed!")
    return True

def test_flask_app_imports():
    """Test that Flask app can be imported and initialized."""
    print("🧪 Testing Flask app imports...")

    try:
        from src.ui.flask_app import app, user_manager, temp_manager, get_or_create_user_id, get_user_temp_dir
        print("✅ Flask app imports successful")

        # Test that managers are initialized
        assert user_manager is not None, "User manager should be initialized"
        assert temp_manager is not None, "Temp manager should be initialized"

        print("✅ Flask app initialization successful")
        return True
    except Exception as e:
        print(f"❌ Flask app import failed: {e}")
        return False

def test_task_functions():
    """Test that task functions accept user_id parameter."""
    print("🧪 Testing task functions...")

    from src.ui.tasks import parse_pdf_task, seeding_task, generate_pdf_task

    # Test that functions accept user_id parameter (should not raise TypeError)
    try:
        # These should not raise errors due to unexpected keyword arguments
        # We're just testing that the signatures accept user_id
        import inspect

        sig = inspect.signature(parse_pdf_task)
        assert 'user_id' in sig.parameters, "parse_pdf_task should accept user_id"

        sig = inspect.signature(seeding_task)
        assert 'user_id' in sig.parameters, "seeding_task should accept user_id"

        sig = inspect.signature(generate_pdf_task)
        assert 'user_id' in sig.parameters, "generate_pdf_task should accept user_id"

        print("✅ Task functions accept user_id parameter")
        return True
    except Exception as e:
        print(f"❌ Task function test failed: {e}")
        return False

def test_integration():
    """Test integration between components."""
    print("🧪 Testing integration...")

    from src.core.user_manager import UserManager
    from src.core.temp_manager import TempManager

    # Create managers
    user_mgr = UserManager()
    temp_mgr = TempManager()

    # Create user and temp dir
    user_id = user_mgr.create_user_session("127.0.0.1", "TestAgent/1.0")
    user_dir = temp_mgr.get_user_temp_dir(user_id)

    # Simulate Flask-style usage
    user_session = user_mgr.get_user_session(user_id)
    assert user_session, "Should be able to get user session"

    # Update session with data
    user_mgr.update_user_session(user_id, events=["event1"], heat_sheets=None)

    # Verify temp dir exists
    assert user_dir.exists(), "User temp dir should exist"

    # Clean up
    temp_mgr.cleanup_user_temp_dir(user_id)
    user_mgr.delete_user_session(user_id)

    print("✅ Integration test passed!")
    return True

def run_all_tests():
    """Run all tests."""
    print("🚀 Starting Point 1 User Isolation Tests\n")

    tests = [
        test_user_manager,
        test_temp_manager,
        test_flask_app_imports,
        test_task_functions,
        test_integration
    ]

    passed = 0
    failed = 0

    for test in tests:
        try:
            if test():
                passed += 1
            else:
                failed += 1
        except Exception as e:
            print(f"❌ Test {test.__name__} failed with exception: {e}")
            failed += 1
        print()

    print(f"📊 Test Results: {passed} passed, {failed} failed")

    if failed == 0:
        print("🎉 All tests passed! User isolation implementation is functional.")
        return True
    else:
        print("⚠️  Some tests failed. Please review the implementation.")
        return False

if __name__ == "__main__":
    success = run_all_tests()
    sys.exit(0 if success else 1)