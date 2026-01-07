#!/usr/bin/env python3
"""
Test 20: Frame and Geometry

Tests window frame and geometry calculations:
- Frame coordinates
- Window dimensions
- Position validation
"""

import sys, os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'python'))

from uitest import WorkspaceTestClient, run_tests

client = WorkspaceTestClient()

def all_windows_have_frames():
    """Verify all windows have frame data."""
    state = client.query_ui_state()
    for w in state.get('windows', []):
        if 'frame' not in w:
            return False
    return True

def frames_have_four_values():
    """Verify frames have x, y, width, height."""
    state = client.query_ui_state()
    for w in state.get('windows', []):
        frame = w.get('frame', {})
        if not all(k in frame for k in ['x', 'y', 'width', 'height']):
            return False
    return True

def dimensions_are_positive():
    """Verify width and height are positive."""
    state = client.query_ui_state()
    for w in state.get('windows', []):
        frame = w.get('frame', {})
        if frame.get('width', 0) < 0 or frame.get('height', 0) < 0:
            return False
    return True

def coordinates_are_reasonable():
    """Verify coordinates are in reasonable screen range."""
    state = client.query_ui_state()
    for w in state.get('windows', []):
        frame = w.get('frame', {})
        x, y = frame.get('x', 0), frame.get('y', 0)
        # Coordinates should be within reasonable screen bounds
        # Allow negative for off-screen windows
        if abs(x) > 10000 or abs(y) > 10000:
            return False
    return True

def info_panel_has_reasonable_size():
    """Verify About dialog has expected dimensions."""
    client.open_about_dialog()
    state = client.query_ui_state()
    for w in state.get('windows', []):
        if w.get('title') == 'Info':
            frame = w.get('frame', {})
            width = frame.get('width', 0)
            height = frame.get('height', 0)
            # About panel should be a reasonable size
            return width >= 200 and height >= 150
    return False

tests = [
    # Frame existence
    ("All windows have frame",
     all_windows_have_frames),
    
    # Frame structure
    ("Frames have x/y/width/height",
     frames_have_four_values),
    
    # Dimension validation
    ("Dimensions are positive",
     dimensions_are_positive),
    
    # Coordinate validation
    ("Coordinates are reasonable",
     coordinates_are_reasonable),
    
    # Specific window size
    ("About dialog has expected size",
     info_panel_has_reasonable_size),
]

if __name__ == "__main__":
    exit(run_tests(*tests))
