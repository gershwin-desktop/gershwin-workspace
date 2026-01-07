#!/usr/bin/env python3
"""
Interactive Menu Test - Demonstrates driving the UI through menus.

This test:
1. Opens the About dialog via the Info menu
2. Verifies the About window appears
3. Checks for expected content
4. Closes the window
5. Verifies it closed

Run with: python3 test_interactive_menu.py

While running, you will SEE the UI being driven - windows opening,
menus activating, etc.
"""

import sys, os, time
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'python'))

from uitest import WorkspaceTestClient, run_interactive_tests

# Create test client
client = WorkspaceTestClient()

# Clear any previous highlight overlays
client.clear_highlights()


def test_open_about_via_menu():
    """Open the About dialog through the Info menu."""
    result = client.menu("Info > About")
    return result.get('success', False)


def test_about_window_appeared():
    """Wait for the About window to appear."""
    result = client.wait_for_window("About", timeout=3.0)
    return result.get('success', False)


def test_about_has_workspace_title():
    """Check that the About dialog contains 'Workspace' text."""
    # First check if text is visible anywhere
    if client.text_visible("Workspace"):
        return True
    # Otherwise try to find it in the About window
    result = client.find_element("About", "Workspace")
    return result.get('found', False)


def test_close_about_window():
    """Close the About window."""
    result = client.close_window("About")
    return result.get('success', False)


def test_about_window_gone():
    """Verify the About window is no longer visible."""
    time.sleep(0.3)  # Brief pause for window to close
    return not client.window_exists("About")


# Run the interactive test suite
# - stop_on_failure=True (default for run_interactive_tests)
# - highlight_failures=True (default for run_interactive_tests)
# - Brief pause between tests for visual feedback
if __name__ == '__main__':
    print("=" * 60)
    print("Interactive Menu Test")
    print("Watch the UI as tests execute!")
    print("=" * 60)
    print()
    
    result = run_interactive_tests(
        ("Open About via Info menu", test_open_about_via_menu),
        ("About window appeared", test_about_window_appeared),
        ("About shows 'Workspace'", test_about_has_workspace_title),
        ("Close About window", test_close_about_window),
        ("About window closed", test_about_window_gone),
        client=client,
        pause_between=0.5
    )
    
    # Clean up highlights
    client.clear_highlights()
    
    sys.exit(result)
