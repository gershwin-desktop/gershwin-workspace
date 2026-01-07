#!/usr/bin/env python3
"""
test_utils.py - Shared utilities for interactive tests

Common functions used across all interactive test suites:
- Modal dialog handling (non-blocking via xdotool)
- Window management
- State cleanup
- Test setup/teardown
- Failure capture with screenshots

IMPORTANT: Modal detection uses xdotool, NOT uitest queries.
This ensures detection works even when the UI is blocked.
"""

import sys
import os
import time
import traceback
from typing import Optional, Dict, Any, Callable
from functools import wraps

# Add python directory to path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'python'))

from uitest import WorkspaceTestClient
from user_input import UserInput
from modal_handler import ModalHandler, get_handler, check_before_click
from test_failure_capture import FailureCapture, get_capture, on_test_failure

# Global instances
_client = None
_user = None
_modal_handler = None
_failure_capture = None


def get_client() -> WorkspaceTestClient:
    """Get or create the WorkspaceTestClient instance."""
    global _client
    if _client is None:
        _client = WorkspaceTestClient()
    return _client


def get_user() -> UserInput:
    """Get or create the UserInput instance."""
    global _user
    if _user is None:
        _user = UserInput()
    return _user


def get_modal_handler() -> ModalHandler:
    """Get or create the ModalHandler instance (non-blocking)."""
    global _modal_handler
    if _modal_handler is None:
        _modal_handler = ModalHandler()
    return _modal_handler


def get_failure_capture() -> FailureCapture:
    """Get or create the FailureCapture instance."""
    global _failure_capture
    if _failure_capture is None:
        _failure_capture = FailureCapture("/tmp/uitest_failures")
    return _failure_capture


def activate_workspace():
    """Ensure Workspace is focused."""
    handler = get_modal_handler()
    handler.ensure_workspace_focused()
    time.sleep(0.2)


def dismiss_all_modals(max_attempts: int = 5) -> int:
    """
    Dismiss any modal dialogs on screen.
    
    Uses xdotool-based detection (non-blocking) instead of uitest queries.
    
    Args:
        max_attempts: Maximum number of attempts
        
    Returns:
        Number of dismissal attempts made
    """
    handler = get_modal_handler()
    user = get_user()
    
    dismissed = 0
    for i in range(max_attempts):
        # Use non-blocking modal detection
        modal = handler.detect_modal_dialog()
        if not modal:
            break
        
        # Try to dismiss
        if handler.dismiss_focus_stealer():
            dismissed += 1
        else:
            # Just press escape as fallback
            user.press_escape()
            time.sleep(0.15)
            dismissed += 1
    
    return dismissed


def close_utility_windows():
    """Close common utility windows (Info, Finder, Preferences, etc.)."""
    user = get_user()
    handler = get_modal_handler()
    
    windows_to_close = ['Info', 'Finder', 'Workspace Preferences', 'Run', 
                        'Open With', 'Go to Folder']
    
    # Use xdotool to check for windows (non-blocking)
    all_windows = handler.get_all_visible_windows()
    for window in all_windows:
        for title in windows_to_close:
            if title.lower() in window.name.lower():
                try:
                    user.focus_window_by_name(window.name)
                    time.sleep(0.2)
                    user.cmd('w')
                    time.sleep(0.3)
                except:
                    pass
                break


def ensure_clean_state():
    """
    Ensure the UI is in a clean state for testing.
    
    This will:
    - Dismiss any modal dialogs
    - Close utility windows
    - Focus Workspace
    """
    dismiss_all_modals()
    close_utility_windows()
    activate_workspace()
    time.sleep(0.3)


def ensure_viewer_window() -> bool:
    """
    Make sure we have at least one viewer window open.
    
    Returns:
        True if viewer is available
    """
    user = get_user()
    client = get_client()
    
    visible = client.get_visible_windows()
    has_viewer = any(w.get('class') == 'GWViewerWindow' for w in visible)
    
    if not has_viewer:
        activate_workspace()
        user.cmd('n')  # Open new viewer
        time.sleep(0.5)
    
    return True


def close_extra_viewers(keep: int = 1):
    """
    Close extra viewer windows, keep specified number.
    
    Args:
        keep: Number of viewer windows to keep open
    """
    user = get_user()
    client = get_client()
    
    visible = client.get_visible_windows()
    viewers = [w for w in visible if w.get('class') == 'GWViewerWindow']
    
    while len(viewers) > keep:
        user.cmd('w')
        time.sleep(0.3)
        visible = client.get_visible_windows()
        viewers = [w for w in visible if w.get('class') == 'GWViewerWindow']


def count_viewer_windows() -> int:
    """Count open viewer windows."""
    client = get_client()
    visible = client.get_visible_windows()
    return sum(1 for w in visible if w.get('class') == 'GWViewerWindow')


def close_window_by_title(title: str) -> bool:
    """
    Close a window by its title.
    
    Returns:
        True if window was closed
    """
    user = get_user()
    client = get_client()
    
    if not client.window_exists(title):
        return False
    
    try:
        user.focus_window_by_name(title)
        time.sleep(0.2)
        user.cmd('w')
        time.sleep(0.3)
        return not client.window_exists(title)
    except:
        return False


def wait_for_window(title: str, timeout: float = 5.0) -> bool:
    """
    Wait for a window to appear.
    
    Args:
        title: Window title to wait for
        timeout: Maximum seconds to wait
        
    Returns:
        True if window appeared
    """
    client = get_client()
    
    start = time.time()
    while time.time() - start < timeout:
        if client.window_exists(title):
            return True
        time.sleep(0.2)
    return False


def wait_for_no_modals(timeout: float = 3.0) -> bool:
    """
    Wait for all modal dialogs to be dismissed.
    Uses non-blocking xdotool detection.
    
    Returns:
        True if no modals remain
    """
    handler = get_modal_handler()
    
    start = time.time()
    while time.time() - start < timeout:
        if not handler.detect_modal_dialog():
            return True
        time.sleep(0.2)
    return False


# Screen dimensions (can be overridden)
SCREEN_WIDTH = 1920
SCREEN_HEIGHT = 1080
MENU_BAR_Y = 11

# Menu bar X positions
MENU_POSITIONS = {
    'Workspace': 60,
    'File': 150,
    'Edit': 220,
    'View': 280,
    'Go': 330,
    'Tools': 390,
    'Window': 470,
    'Help': 540
}


def safe_click(x: int, y: int, smooth: bool = True, check_focus: bool = True) -> Dict[str, Any]:
    """
    Click at coordinates with pre-click modal/focus check.
    
    This is the SAFE way to click - always checks for focus stealers first.
    
    Args:
        x: X coordinate
        y: Y coordinate
        smooth: Use smooth mouse movement
        check_focus: Check for focus stealers before clicking
        
    Returns:
        Dictionary with click result and any modal handling info
    """
    user = get_user()
    handler = get_modal_handler()
    result = {'ok': True, 'modal_dismissed': False, 'details': []}
    
    if check_focus:
        # Check for modals/focus stealers BEFORE clicking
        check = handler.pre_click_check()
        if check['modal_detected']:
            result['modal_dismissed'] = True
            result['details'].append(f"Dismissed modal: {check['modal_detected']}")
        if not check['ok']:
            result['ok'] = False
            result['details'].append("Could not clear focus stealer")
    
    # Perform the click
    if smooth:
        user.click_smooth(x, y)
    else:
        user.click(x, y)
    
    return result


def safe_click_menu(menu_name: str, smooth: bool = True) -> Dict[str, Any]:
    """
    Click on a menu in the menu bar with pre-click focus check.
    
    Args:
        menu_name: Name of menu to click
        smooth: Use smooth mouse movement
        
    Returns:
        Dictionary with click result
    """
    x = MENU_POSITIONS.get(menu_name, 100)
    result = safe_click(x, MENU_BAR_Y, smooth=smooth)
    time.sleep(0.3)
    return result


def click_menu(menu_name: str, smooth: bool = True):
    """Click on a menu in the menu bar (with focus check)."""
    safe_click_menu(menu_name, smooth)


def dismiss_menu():
    """Dismiss any open menu by pressing Escape."""
    user = get_user()
    user.press_escape()
    time.sleep(0.2)


class TestContext:
    """
    Context manager for test setup and teardown.
    
    Features:
    - Clean state before/after tests
    - Automatic failure capture (screenshot + log)
    - Non-blocking modal handling
    
    Usage:
        with TestContext() as ctx:
            # Run test
            ctx.user.cmd('n')
            assert ctx.client.window_exists('...')
    """
    
    def __init__(self, test_name: str = "unknown", 
                 clean_before: bool = True, 
                 clean_after: bool = True,
                 capture_on_failure: bool = True):
        self.test_name = test_name
        self.clean_before = clean_before
        self.clean_after = clean_after
        self.capture_on_failure = capture_on_failure
        self.client = get_client()
        self.user = get_user()
        self.modal_handler = get_modal_handler()
        self.capture = get_failure_capture()
    
    def __enter__(self):
        self.capture.set_test_name(self.test_name)
        self.capture.log(f"Starting test context: {self.test_name}")
        
        if self.clean_before:
            ensure_clean_state()
        return self
    
    def __exit__(self, exc_type, exc_val, exc_tb):
        if exc_type is not None and self.capture_on_failure:
            # Test failed - capture everything
            self.capture.log(f"Test FAILED: {exc_type.__name__}: {exc_val}")
            self.capture.log(f"Traceback:\n{traceback.format_exc()}")
            self.capture.take_screenshot(f"FAIL_{self.test_name}")
            self.capture.save_log(str(exc_val))
        
        if self.clean_after:
            try:
                ensure_clean_state()
            except:
                pass  # Don't mask original exception
        
        return False  # Don't suppress exceptions


def test_with_capture(test_name: str):
    """
    Decorator to wrap a test function with failure capture.
    
    Usage:
        @test_with_capture("test_open_viewer")
        def test_open_viewer():
            ...
    """
    def decorator(func: Callable) -> Callable:
        @wraps(func)
        def wrapper(*args, **kwargs):
            capture = get_failure_capture()
            capture.set_test_name(test_name)
            capture.log(f"Starting test: {test_name}")
            
            # Check for modals before test
            handler = get_modal_handler()
            modal = handler.detect_modal_dialog()
            if modal:
                capture.log(f"WARNING: Modal detected before test: {modal.name}")
                handler.dismiss_focus_stealer()
            
            try:
                result = func(*args, **kwargs)
                capture.log(f"Test PASSED: {test_name}")
                return result
            except Exception as e:
                capture.log(f"Test FAILED: {test_name}")
                capture.log(f"Error: {type(e).__name__}: {e}")
                capture.log(f"Traceback:\n{traceback.format_exc()}")
                capture.take_screenshot(f"FAIL_{test_name}")
                capture.save_log(traceback.format_exc())
                raise
        
        return wrapper
    return decorator


# Convenience function for running tests with full error capture
def run_test_safely(func: Callable, test_name: Optional[str] = None) -> bool:
    """
    Run a test function with full error capture.
    
    Args:
        func: Test function to run
        test_name: Name for the test (default: function name)
        
    Returns:
        True if test passed, False if failed
    """
    name = test_name or func.__name__
    capture = get_failure_capture()
    capture.set_test_name(name)
    capture.log(f"Running test: {name}")
    
    # Pre-test modal check
    handler = get_modal_handler()
    modal = handler.detect_modal_dialog()
    if modal:
        capture.log(f"Pre-test: dismissing modal '{modal.name}'")
        handler.dismiss_focus_stealer()
    
    try:
        func()
        capture.log(f"PASSED: {name}")
        return True
    except Exception as e:
        capture.log(f"FAILED: {name}")
        capture.log(f"Error: {type(e).__name__}: {e}")
        capture.take_screenshot(f"FAIL_{name}")
        capture.save_log(traceback.format_exc())
        print(f"  FAILED: {name} - {e}")
        return False
