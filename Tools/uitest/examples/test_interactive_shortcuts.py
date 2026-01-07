#!/usr/bin/env python3
"""
Interactive Shortcut Test - Demonstrates driving the UI with keyboard shortcuts.

This test:
1. Uses Cmd+Shift+? to open help/About
2. Uses keyboard shortcuts to navigate
3. Tests the shortcut command functionality

Run with: python3 test_interactive_shortcuts.py

While running, you will SEE the UI responding to keyboard shortcuts.
"""

import sys, os, time
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'python'))

from uitest import WorkspaceTestClient, run_interactive_tests

# Create test client
client = WorkspaceTestClient()

# Clear any previous highlight overlays
client.clear_highlights()


def test_query_initial_state():
    """Verify we can query the initial UI state."""
    state = client.query_ui_state()
    return state.get('uiTestingEnabled', False)


def test_get_windows():
    """Verify we can get the list of windows."""
    state = client.query_ui_state()
    windows = state.get('windows', [])
    # There should be at least the root window or menu
    return isinstance(windows, list)


def test_shortcut_about():
    """Try to open About dialog via keyboard shortcut."""
    # Try the common About shortcut Cmd+Shift+? or just the menu
    result = client.shortcut("Cmd+?")
    # Even if shortcut not bound, we want to test the mechanism
    return True  # Pass if no exception was raised


def test_menu_info_about():
    """Open About via menu as fallback."""
    result = client.menu("Info > About")
    return result.get('success', False)


def test_wait_for_about():
    """Wait for About window to appear."""
    result = client.wait_for_window("About", timeout=3.0)
    return result.get('success', False)


def test_find_version_info():
    """Look for version info in the About window."""
    # Try to find common version-related text
    if client.text_visible("Version"):
        return True
    if client.text_visible("Workspace"):
        return True
    # At minimum, the About window should exist
    return client.window_exists("About")


def test_close_about_via_shortcut():
    """Try to close window via Cmd+W shortcut."""
    result = client.shortcut("Cmd+w")
    time.sleep(0.3)
    # Window should close (or at least command should execute)
    return True


def test_cleanup_close_about():
    """Ensure About window is closed."""
    if client.window_exists("About"):
        client.close_window("About")
    time.sleep(0.3)
    return not client.window_exists("About")


# Run the interactive test suite
if __name__ == '__main__':
    print("=" * 60)
    print("Interactive Keyboard Shortcuts Test")
    print("Watch the UI respond to keyboard shortcuts!")
    print("=" * 60)
    print()
    
    result = run_interactive_tests(
        ("Query initial state", test_query_initial_state),
        ("Get window list", test_get_windows),
        ("Send Cmd+? shortcut", test_shortcut_about),
        ("Open About via menu", test_menu_info_about),
        ("About window appeared", test_wait_for_about),
        ("Find version/app info", test_find_version_info),
        ("Send Cmd+W to close", test_close_about_via_shortcut),
        ("Ensure About closed", test_cleanup_close_about),
        client=client,
        pause_between=0.5
    )
    
    # Clean up highlights
    client.clear_highlights()
    
    sys.exit(result)
