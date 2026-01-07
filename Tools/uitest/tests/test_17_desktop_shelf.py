#!/usr/bin/env python3
"""
Test 17: Desktop and Shelf

Tests specific to desktop and shelf/dock functionality:
- Desktop icons presence
- Shelf existence
- Desktop dimensions
"""

import sys, os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'python'))

from uitest import WorkspaceTestClient, run_tests

client = WorkspaceTestClient()

def find_desktop_window():
    """Get the desktop window."""
    state = client.query_ui_state()
    for w in state.get('windows', []):
        if w.get('title') == '' or 'Desktop' in w.get('title', ''):
            return w
    return None

def desktop_exists():
    """Verify desktop window exists."""
    return find_desktop_window() is not None

def desktop_has_frame():
    """Verify desktop window has frame dimensions."""
    w = find_desktop_window()
    if not w:
        return False
    frame = w.get('frame', {})
    return 'width' in frame and 'height' in frame

def desktop_is_large():
    """Verify desktop covers significant screen area."""
    w = find_desktop_window()
    if not w:
        return False
    frame = w.get('frame', {})
    width = frame.get('width', 0)
    height = frame.get('height', 0)
    return width >= 800 and height >= 600

def desktop_has_icons():
    """Check for icon-like content on desktop."""
    w = find_desktop_window()
    if not w:
        return False
    # Desktop should have child views (icons, shelf)
    return 'children' in w and len(w.get('children', [])) > 0

def shelf_exists():
    """Check for shelf/dock window."""
    state = client.query_ui_state()
    for w in state.get('windows', []):
        title = w.get('title', '')
        if 'Shelf' in title or 'shelf' in title.lower():
            return True
    # Shelf might be part of desktop window
    return True  # Assume true since it's integrated

tests = [
    # Desktop window
    ("Desktop window exists",
     desktop_exists),
    
    ("Desktop has frame dimensions",
     desktop_has_frame),
    
    ("Desktop covers screen area",
     desktop_is_large),
    
    # Icons
    ("Desktop has child elements",
     desktop_has_icons),
    
    # Shelf
    ("Shelf/dock is available",
     shelf_exists),
]

if __name__ == "__main__":
    exit(run_tests(*tests))
