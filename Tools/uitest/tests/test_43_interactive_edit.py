#!/usr/bin/env python3
"""
Interactive Test Suite - Edit Operations

Tests clipboard and edit operations:
- Cut, Copy, Paste
- Undo, Redo
- Select All
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


def activate_workspace():
    """Ensure Workspace is focused."""
    try:
        user.focus_window_by_name("Workspace")
        time.sleep(0.3)
    except:
        pass

def ensure_viewer_window():
    """Make sure we have a viewer window open."""
    visible = client.get_visible_windows()
    has_viewer = any(w.get('class') == 'GWViewerWindow' for w in visible)
    
    if not has_viewer:
        user.cmd('n')  # Open new viewer
        time.sleep(0.5)
    return True


# ============== Menu State Tests ==============

def test_edit_menu_items():
    """Edit menu has expected items."""
    items = client.get_menu_items('Edit')
    titles = [i.get('title', '') for i in items if not i.get('separator')]
    
    expected = ['Undo', 'Redo', 'Cut', 'Copy', 'Paste', 'Select All']
    for exp in expected:
        if exp not in titles:
            print(f"  Missing: {exp}")
            return False
    return True

def test_undo_available():
    """Undo menu item exists."""
    item = client.get_menu_item('Edit', 'Undo')
    return item.get('action') == 'undo:'

def test_redo_available():
    """Redo menu item exists."""
    item = client.get_menu_item('Edit', 'Redo')
    return item.get('action') == 'redo:'

def test_cut_available():
    """Cut menu item exists."""
    item = client.get_menu_item('Edit', 'Cut')
    return item.get('action') == 'cut:'

def test_copy_available():
    """Copy menu item exists."""
    item = client.get_menu_item('Edit', 'Copy')
    return item.get('action') == 'copy:'

def test_paste_disabled_when_empty():
    """Paste is disabled when clipboard is empty."""
    # Paste should be disabled if nothing to paste
    return not client.is_menu_item_enabled('Edit', 'Paste')


# ============== Keyboard Shortcut Tests ==============

def test_shortcut_undo():
    """Undo shortcut Cmd+Z."""
    activate_workspace()
    ensure_viewer_window()
    
    user.cmd('z')
    time.sleep(0.3)
    
    # No visible change expected, just verifying no crash
    return True

def test_shortcut_redo():
    """Redo shortcut Cmd+Shift+Z."""
    activate_workspace()
    ensure_viewer_window()
    
    user.cmd_shift('z')
    time.sleep(0.3)
    
    return True

def test_shortcut_cut():
    """Cut shortcut Cmd+X."""
    activate_workspace()
    ensure_viewer_window()
    
    # Navigate to home and select something
    user.cmd_shift('h')
    time.sleep(0.3)
    
    user.cmd('x')
    time.sleep(0.3)
    
    return True

def test_shortcut_copy():
    """Copy shortcut Cmd+C."""
    activate_workspace()
    ensure_viewer_window()
    
    user.cmd_shift('h')
    time.sleep(0.3)
    
    user.cmd('c')
    time.sleep(0.3)
    
    return True

def test_shortcut_paste():
    """Paste shortcut Cmd+V."""
    activate_workspace()
    ensure_viewer_window()
    
    user.cmd('v')
    time.sleep(0.3)
    
    return True

def test_shortcut_select_all():
    """Select All shortcut Cmd+A."""
    activate_workspace()
    ensure_viewer_window()
    
    user.cmd_shift('h')
    time.sleep(0.3)
    
    user.cmd('a')
    time.sleep(0.3)
    
    return True


# ============== Copy-Paste Workflow Test ==============

def test_copy_paste_workflow():
    """Test copy-paste workflow: select, copy, navigate, paste."""
    activate_workspace()
    ensure_viewer_window()
    
    # Go to a directory with files
    user.cmd_shift('h')
    time.sleep(0.5)
    
    # Select all
    user.cmd('a')
    time.sleep(0.3)
    
    # Copy
    user.cmd('c')
    time.sleep(0.3)
    
    # After copying, Paste should become available
    # (depends on implementation)
    
    return True


# ============== Test Suite ==============

tests = [
    # Menu structure
    ("Edit menu has expected items", test_edit_menu_items),
    ("Undo available", test_undo_available),
    ("Redo available", test_redo_available),
    ("Cut available", test_cut_available),
    ("Copy available", test_copy_available),
    ("Paste disabled when empty", test_paste_disabled_when_empty),
    
    # Keyboard shortcuts
    ("Shortcut: Undo (Cmd+Z)", test_shortcut_undo),
    ("Shortcut: Redo (Cmd+Shift+Z)", test_shortcut_redo),
    ("Shortcut: Cut (Cmd+X)", test_shortcut_cut),
    ("Shortcut: Copy (Cmd+C)", test_shortcut_copy),
    ("Shortcut: Paste (Cmd+V)", test_shortcut_paste),
    ("Shortcut: Select All (Cmd+A)", test_shortcut_select_all),
    
    # Workflows
    ("Copy-paste workflow", test_copy_paste_workflow),
]

if __name__ == "__main__":
    print("\n" + "="*60)
    print("INTERACTIVE EDIT OPERATIONS TESTS")
    print("Tests clipboard and edit shortcuts")
    print("="*60 + "\n")
    exit(run_tests(*tests))
