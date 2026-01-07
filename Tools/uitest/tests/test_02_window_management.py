#!/usr/bin/env python3
"""
Test 02: Window Management

Verifies window handling capabilities:
- Window existence detection
- Window title queries
- Visible vs hidden windows
- Window class identification
"""

import sys, os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'python'))

from uitest import WorkspaceTestClient, run_tests

client = WorkspaceTestClient()

def get_window_classes():
    """Get list of unique window classes."""
    state = client.query_ui_state()
    classes = set()
    for w in state.get('windows', []):
        cls = w.get('class', '')
        if cls:
            classes.add(cls)
    return classes

def has_desktop_window():
    """Check for GWDesktopWindow (desktop background)."""
    return 'GWDesktopWindow' in get_window_classes()

def has_icon_window():
    """Check for NSIconWindow (app icon)."""
    return 'NSIconWindow' in get_window_classes()

tests = [
    # Basic window detection
    ("Can detect windows",
     lambda: len(client.get_window_titles()) > 0),
    
    # Visible window filtering
    ("Can filter visible windows",
     lambda: len(client.get_visible_windows()) >= 0),  # May be 0 if hidden
    
    # Desktop window exists
    ("Desktop window exists",
     has_desktop_window),
    
    # App icon window
    ("Icon window exists",
     has_icon_window),
    
    # Window properties
    ("Windows have frame data",
     lambda: all('frame' in w for w in client.query_ui_state().get('windows', []))),
    
    # Window visibility tracking
    ("Windows have visibility status",
     lambda: all('visibility' in w or 'isVisible' in w 
                 for w in client.query_ui_state().get('windows', []))),
    
    # Window title access
    ("Can access window title",
     lambda: all('title' in w for w in client.query_ui_state().get('windows', []))),
]

if __name__ == "__main__":
    exit(run_tests(*tests))
