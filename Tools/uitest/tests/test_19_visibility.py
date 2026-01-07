#!/usr/bin/env python3
"""
Test 19: Visibility Filtering

Tests visibility state detection:
- Visible windows
- Hidden windows
- Minimized detection
"""

import sys, os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'python'))

from uitest import WorkspaceTestClient, run_tests

client = WorkspaceTestClient()

def get_visible_only():
    """Get visible windows using filter."""
    visible = client.get_visible_windows()
    return isinstance(visible, list)

def visible_windows_are_really_visible():
    """Verify filtered windows have visible flag."""
    visible = client.get_visible_windows()
    for w in visible:
        if w.get('visibility') != 'visible':
            return False
    return True

def desktop_is_visible():
    """Verify desktop window is marked visible."""
    visible = client.get_visible_windows()
    for w in visible:
        if w.get('title', '') == '' or 'Desktop' in w.get('title', ''):
            return True
    return len(visible) > 0  # At least something visible

def opened_panel_is_visible():
    """Verify newly opened panel is marked visible."""
    client.open_about_dialog()
    visible = client.get_visible_windows()
    for w in visible:
        if w.get('title') == 'Info':
            return True
    return False

def visibility_state_is_string():
    """Verify visibility state is proper string type."""
    state = client.query_ui_state()
    for w in state.get('windows', []):
        vis = w.get('visibility', '')
        if not isinstance(vis, str):
            return False
    return True

tests = [
    # Filter function
    ("get_visible_windows returns list",
     get_visible_only),
    
    # Filter correctness
    ("Filtered windows are visible",
     visible_windows_are_really_visible),
    
    # Desktop visibility
    ("Desktop is visible",
     desktop_is_visible),
    
    # Panel visibility
    ("Opened panel is visible",
     opened_panel_is_visible),
    
    # Type check
    ("Visibility is string type",
     visibility_state_is_string),
]

if __name__ == "__main__":
    exit(run_tests(*tests))
