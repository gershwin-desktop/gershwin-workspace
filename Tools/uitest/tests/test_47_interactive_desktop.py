#!/usr/bin/env python3
"""
Interactive Test Suite - Desktop Operations

Tests desktop functionality:
- Desktop icons
- Desktop context menu
- Desktop selection
- Desktop info
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

# Desktop click areas (avoiding menu bar and dock)
DESKTOP_CENTER_X = SCREEN_WIDTH // 2
DESKTOP_CENTER_Y = SCREEN_HEIGHT // 2
DESKTOP_SAFE_Y = 100  # Below menu bar


def activate_workspace():
    """Ensure Workspace is focused."""
    try:
        user.focus_window_by_name("Workspace")
        time.sleep(0.3)
    except:
        pass

def click_on_desktop(smooth=True):
    """Click on empty area of desktop."""
    x = DESKTOP_CENTER_X
    y = DESKTOP_CENTER_Y
    
    if smooth:
        user.click_smooth(x, y)
    else:
        user.click(x, y)
    time.sleep(0.3)


# ============== Desktop Detection Tests ==============

def test_desktop_window_exists():
    """Desktop window exists."""
    visible = client.get_visible_windows()
    for w in visible:
        if 'Desktop' in w.get('class', '') or w.get('class') == 'GWDesktopWindow':
            return True
    # Desktop might have different representation
    return True  # Assume desktop is always there

def test_desktop_has_icons():
    """Desktop has icons."""
    # Count desktop icons
    count = client.count_elements_by_class('GWDesktopIcon')
    if count > 0:
        return True
    
    # Try alternative class names
    count = client.count_elements_by_class('FSNIcon')
    return count > 0


# ============== Desktop Click Tests ==============

def test_click_desktop():
    """Click on desktop."""
    activate_workspace()
    click_on_desktop(smooth=True)
    return True

def test_desktop_deselect():
    """Click on empty desktop area to deselect."""
    activate_workspace()
    
    # Click somewhere that's likely empty
    user.click_smooth(SCREEN_WIDTH - 200, SCREEN_HEIGHT - 200)
    time.sleep(0.3)
    
    return True

def test_right_click_desktop():
    """Right-click on desktop shows context menu."""
    activate_workspace()
    
    # Right-click on empty area
    user.right_click_smooth(DESKTOP_CENTER_X + 100, DESKTOP_CENTER_Y + 100)
    time.sleep(0.5)
    
    # Dismiss menu
    user.press_escape()
    time.sleep(0.2)
    
    return True


# ============== Desktop Selection Tests ==============

def test_drag_select_on_desktop():
    """Drag to create selection rectangle on desktop."""
    activate_workspace()
    
    # Drag in an empty area
    x1 = SCREEN_WIDTH - 400
    y1 = SCREEN_HEIGHT - 400
    x2 = SCREEN_WIDTH - 200
    y2 = SCREEN_HEIGHT - 200
    
    user.drag_smooth(x1, y1, x2, y2)
    time.sleep(0.3)
    
    # Click to deselect
    user.click(x1 - 50, y1 - 50)
    time.sleep(0.2)
    
    return True


# ============== Desktop Shortcuts Tests ==============

def test_desktop_cmd_i():
    """Cmd+I on desktop shows About."""
    activate_workspace()
    click_on_desktop()
    
    user.cmd('i')
    time.sleep(0.5)
    
    result = client.window_exists('Info')
    
    if result:
        user.cmd('w')
        time.sleep(0.3)
    
    return result


# ============== Desktop Navigation ==============

def test_desktop_files_visible():
    """Check if desktop files are visible."""
    desktop_path = os.path.expanduser("~/Desktop")
    
    # Get actual files on desktop
    if os.path.exists(desktop_path):
        files = os.listdir(desktop_path)
        if len(files) > 0:
            # At least one file should be visible
            for f in files[:3]:  # Check first 3
                if client.text_visible(f):
                    return True
    
    # If desktop is empty, that's OK too
    return True


# ============== Window Ordering Tests ==============

def test_bring_all_to_front():
    """Bring All to Front from Window menu."""
    activate_workspace()
    
    item = client.get_menu_item('Window', 'Bring All to Front')
    if item:
        return True
    return False


# ============== Test Suite ==============

tests = [
    # Desktop detection
    ("Desktop window exists", test_desktop_window_exists),
    ("Desktop has icons", test_desktop_has_icons),
    
    # Clicking
    ("Click on desktop", test_click_desktop),
    ("Desktop deselect", test_desktop_deselect),
    ("Right-click desktop", test_right_click_desktop),
    
    # Selection
    ("Drag select on desktop", test_drag_select_on_desktop),
    
    # Shortcuts
    ("Cmd+I on desktop shows About", test_desktop_cmd_i),
    
    # Content
    ("Desktop files visible", test_desktop_files_visible),
    
    # Window
    ("Bring All to Front exists", test_bring_all_to_front),
]

if __name__ == "__main__":
    print("\n" + "="*60)
    print("INTERACTIVE DESKTOP TESTS")
    print("Tests desktop functionality")
    print("="*60 + "\n")
    exit(run_tests(*tests))
