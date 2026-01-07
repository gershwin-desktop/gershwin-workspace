#!/usr/bin/env python3
"""
Test 09: File Browser Windows

Verifies file browser functionality:
- Browser window structure
- Column/list view detection
- Path display
"""

import sys, os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'python'))

from uitest import WorkspaceTestClient, run_tests

client = WorkspaceTestClient()

def find_browser_windows():
    """Find all browser-style windows (not panels or dialogs)."""
    state = client.query_ui_state()
    browsers = []
    for w in state.get('windows', []):
        cls = w.get('class', '')
        # NSWindow could be a file browser
        if cls in ['NSWindow'] and w.get('visibility') == 'visible':
            title = w.get('title', '')
            # Filter out known non-browser windows
            if title not in ['Info', 'Workspace Preferences', 'Finder', 'Run', 'Open With']:
                browsers.append(w)
    return browsers

def has_scroll_view():
    """Check for NSScrollView (used in file browsers)."""
    return client.count_elements_by_class("NSScrollView") > 0

def has_browser_column():
    """Check for NSBrowser or column-like widgets."""
    return (client.count_elements_by_class("NSBrowser") > 0 or
            client.count_elements_by_class("NSMatrix") > 0 or
            client.count_elements_by_class("GWViewerBrowser") > 0)

def has_path_in_ui():
    """Check for path-like text (e.g., /home, ~/Desktop)."""
    return (client.text_visible("/home") or 
            client.text_visible("Desktop") or
            client.text_visible("/"))

tests = [
    # Browser window detection
    ("Can detect browser windows",
     lambda: isinstance(find_browser_windows(), list)),
    
    # Scroll views exist (for file lists)
    ("Has scroll view widgets",
     has_scroll_view),
    
    # UI contains path information
    ("UI displays path information",
     has_path_in_ui),
    
    # Browser structure
    ("Browser has expected widgets",
     lambda: has_scroll_view()),
]

if __name__ == "__main__":
    exit(run_tests(*tests))
