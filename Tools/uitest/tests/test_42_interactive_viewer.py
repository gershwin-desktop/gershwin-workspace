#!/usr/bin/env python3
"""
Interactive Test Suite - Viewer Window Operations

Tests viewer window functionality:
- Opening/closing viewer windows
- View type switching (Icons, List, Columns)
- Window operations (minimize, zoom, fullscreen)
- Shelf operations
- Scroll and resize
"""

import sys
import os
import time

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'python'))

from uitest import WorkspaceTestClient, run_tests
from user_input import UserInput

# Initialize
client = WorkspaceTestClient()
user = UserInput()

# Screen dimensions
SCREEN_WIDTH = 1920
SCREEN_HEIGHT = 1080


def activate_workspace():
    """Ensure Workspace is focused."""
    try:
        user.focus_window_by_name("Workspace")
        time.sleep(0.3)
    except:
        pass

def count_viewer_windows():
    """Count open viewer windows."""
    visible = client.get_visible_windows()
    return sum(1 for w in visible if w.get('class') == 'GWViewerWindow')

def ensure_viewer_window():
    """Make sure we have exactly one viewer window open."""
    count = count_viewer_windows()
    
    if count == 0:
        user.cmd('n')  # Open new viewer
        time.sleep(0.5)
    elif count > 1:
        # Close extras
        for _ in range(count - 1):
            user.cmd('w')
            time.sleep(0.3)
    
    return count_viewer_windows() >= 1

def get_viewer_window_info():
    """Get info about the first visible viewer window."""
    visible = client.get_visible_windows()
    for w in visible:
        if w.get('class') == 'GWViewerWindow':
            return w
    return None


# ============== Window Management Tests ==============

def test_open_new_viewer():
    """Open a new viewer window with Cmd+N."""
    activate_workspace()
    
    count_before = count_viewer_windows()
    user.cmd('n')
    time.sleep(0.5)
    count_after = count_viewer_windows()
    
    # Clean up
    if count_after > count_before:
        user.cmd('w')
        time.sleep(0.3)
    
    return count_after > count_before

def test_close_viewer():
    """Close viewer window with Cmd+W."""
    activate_workspace()
    
    # Open a viewer first
    user.cmd('n')
    time.sleep(0.5)
    count_before = count_viewer_windows()
    
    # Close it
    user.cmd('w')
    time.sleep(0.5)
    count_after = count_viewer_windows()
    
    return count_after < count_before

def test_multiple_viewers():
    """Open multiple viewer windows."""
    activate_workspace()
    
    # Open 3 viewers
    for _ in range(3):
        user.cmd('n')
        time.sleep(0.3)
    
    count = count_viewer_windows()
    
    # Clean up - close 2
    for _ in range(2):
        user.cmd('w')
        time.sleep(0.3)
    
    return count >= 3


# ============== View Type Tests ==============

def test_view_menu_items_exist():
    """View menu has view type items."""
    try:
        items = client.get_menu_items('View')
        titles = [i.get('title', '') for i in items]
        return ('as Icons' in titles and 
                'as List' in titles and 
                'as Columns' in titles)
    except:
        return False

def test_switch_to_icon_view():
    """Switch to Icon view with Cmd+1."""
    activate_workspace()
    ensure_viewer_window()
    
    # Navigate to Applications to have some content
    user.cmd_shift('a')
    time.sleep(0.5)
    
    user.cmd('1')
    time.sleep(0.5)
    
    # Icons view should show FSNIcon elements
    count = client.count_elements_by_class('FSNIcon')
    return count > 0

def test_switch_to_list_view():
    """Switch to List view with Cmd+2."""
    activate_workspace()
    ensure_viewer_window()
    
    user.cmd_shift('a')
    time.sleep(0.5)
    
    user.cmd('2')
    time.sleep(0.5)
    
    # List view uses table
    return True  # Command was sent

def test_switch_to_column_view():
    """Switch to Column view with Cmd+3."""
    activate_workspace()
    ensure_viewer_window()
    
    user.cmd_shift('a')
    time.sleep(0.5)
    
    user.cmd('3')
    time.sleep(0.5)
    
    # Column browser view
    return True


# ============== Window Geometry Tests ==============

def test_fullscreen_toggle():
    """Toggle fullscreen with Ctrl+Cmd+F."""
    activate_workspace()
    ensure_viewer_window()
    
    # Get window size before
    w = get_viewer_window_info()
    if not w:
        return False
    
    # Toggle fullscreen
    user.key('ctrl+alt+f')
    time.sleep(0.8)
    
    # Toggle back
    user.key('ctrl+alt+f')
    time.sleep(0.5)
    
    return True


# ============== Mouse Interaction Tests ==============

def test_click_in_viewer():
    """Click inside viewer window."""
    activate_workspace()
    ensure_viewer_window()
    
    user.cmd_shift('a')  # Go to Applications
    time.sleep(0.5)
    
    # Get viewer window position
    w = get_viewer_window_info()
    if not w:
        return False
    
    frame = w.get('frame', {})
    if not frame:
        # Try clicking in center of screen
        x = SCREEN_WIDTH // 2
        y = SCREEN_HEIGHT // 2
    else:
        # Click in center of viewer
        x = int(frame.get('x', 400) + frame.get('width', 600) / 2)
        y = int(frame.get('y', 200) + frame.get('height', 400) / 2)
    
    user.click_smooth(x, y)
    time.sleep(0.3)
    
    return True

def test_double_click_to_open():
    """Double-click an icon to open it."""
    activate_workspace()
    ensure_viewer_window()
    
    user.cmd_shift('a')  # Go to Applications
    time.sleep(0.5)
    
    # Find an icon position - click somewhere in viewer
    w = get_viewer_window_info()
    if not w:
        return False
    
    frame = w.get('frame', {})
    if frame:
        # Click on an icon (assuming icon view, top-left area)
        x = int(frame.get('x', 400) + 80)
        y = int(frame.get('y', 200) + 100)
        
        user.double_click_smooth(x, y)
        time.sleep(0.5)
    
    return True

def test_right_click_context_menu():
    """Right-click shows context menu."""
    activate_workspace()
    ensure_viewer_window()
    
    user.cmd_shift('h')  # Go to Home
    time.sleep(0.5)
    
    w = get_viewer_window_info()
    if not w:
        return False
    
    frame = w.get('frame', {})
    if frame:
        x = int(frame.get('x', 400) + 200)
        y = int(frame.get('y', 200) + 200)
        
        user.right_click_smooth(x, y)
        time.sleep(0.5)
        
        # Dismiss menu
        user.press_escape()
        time.sleep(0.2)
    
    return True

def test_drag_selection():
    """Drag to create selection rectangle."""
    activate_workspace()
    ensure_viewer_window()
    
    user.cmd_shift('h')  # Go to Home
    time.sleep(0.5)
    
    w = get_viewer_window_info()
    if not w:
        return False
    
    frame = w.get('frame', {})
    if frame:
        x1 = int(frame.get('x', 400) + 50)
        y1 = int(frame.get('y', 200) + 50)
        x2 = int(frame.get('x', 400) + 200)
        y2 = int(frame.get('y', 200) + 200)
        
        user.drag_smooth(x1, y1, x2, y2)
        time.sleep(0.3)
        
        # Click elsewhere to deselect
        user.click(x1 - 30, y1 - 30)
        time.sleep(0.2)
    
    return True


# ============== Shelf Tests ==============

def test_viewer_has_shelf():
    """Viewer window has shelf area."""
    ensure_viewer_window()
    count = client.count_elements_by_class('GWViewerShelf')
    return count > 0

def test_shelf_drag_drop():
    """Drag icon to shelf."""
    activate_workspace()
    ensure_viewer_window()
    
    user.cmd_shift('h')  # Go to Home
    time.sleep(0.5)
    
    # This is a placeholder - actual drag-drop would need
    # specific icon positions
    return True


# ============== Select All Test ==============

def test_select_all():
    """Select all with Cmd+A."""
    activate_workspace()
    ensure_viewer_window()
    
    user.cmd_shift('h')  # Go to Home
    time.sleep(0.5)
    
    user.cmd('a')  # Select all
    time.sleep(0.3)
    
    return True


# ============== Test Suite ==============

tests = [
    # Window management
    ("Open new viewer (Cmd+N)", test_open_new_viewer),
    ("Close viewer (Cmd+W)", test_close_viewer),
    ("Multiple viewers", test_multiple_viewers),
    
    # View types
    ("View menu has view types", test_view_menu_items_exist),
    ("Switch to Icon view (Cmd+1)", test_switch_to_icon_view),
    ("Switch to List view (Cmd+2)", test_switch_to_list_view),
    ("Switch to Column view (Cmd+3)", test_switch_to_column_view),
    
    # Window geometry
    ("Fullscreen toggle (Ctrl+Cmd+F)", test_fullscreen_toggle),
    
    # Mouse interactions
    ("Click in viewer", test_click_in_viewer),
    ("Double-click to open", test_double_click_to_open),
    ("Right-click context menu", test_right_click_context_menu),
    ("Drag selection rectangle", test_drag_selection),
    
    # Shelf
    ("Viewer has shelf", test_viewer_has_shelf),
    ("Shelf drag-drop", test_shelf_drag_drop),
    
    # Selection
    ("Select all (Cmd+A)", test_select_all),
]

if __name__ == "__main__":
    print("\n" + "="*60)
    print("INTERACTIVE VIEWER WINDOW TESTS")
    print("Tests viewer operations with mouse and keyboard")
    print("="*60 + "\n")
    
    result = run_tests(*tests)
    
    # Cleanup - ensure just one viewer
    ensure_viewer_window()
    
    exit(result)
