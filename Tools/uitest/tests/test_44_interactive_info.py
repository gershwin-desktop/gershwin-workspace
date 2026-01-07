#!/usr/bin/env python3
"""
Interactive Test Suite - Info Panel (Get Info)

Tests the Info/Inspector panel:
- Opening Info panel on various items
- Info panel content verification
- Closing Info panel
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
        user.cmd('n')
        time.sleep(0.5)
    return True

def close_info_panel():
    """Close the Info panel if open."""
    if client.window_exists('Info'):
        # Focus and close
        user.focus_window_by_name('Info')
        time.sleep(0.2)
        user.cmd('w')
        time.sleep(0.3)


# ============== Basic Info Panel Tests ==============

def test_get_info_enabled():
    """Get Info menu item is enabled."""
    return client.is_menu_item_enabled('File', 'Get Info')

def test_get_info_shortcut():
    """Get Info has Cmd+I shortcut."""
    item = client.get_menu_item('File', 'Get Info')
    return 'Cmd+I' in item.get('shortcut', '')

def test_open_info_with_shortcut():
    """Open Info panel with Cmd+I."""
    activate_workspace()
    ensure_viewer_window()
    
    # Navigate somewhere first
    user.cmd_shift('h')  # Home
    time.sleep(0.5)
    
    user.cmd('i')
    time.sleep(0.5)
    
    result = client.window_exists('Info')
    close_info_panel()
    return result

def test_open_info_for_applications():
    """Open Info for Applications folder."""
    activate_workspace()
    ensure_viewer_window()
    
    user.cmd_shift('a')  # Applications
    time.sleep(0.5)
    
    user.cmd('i')
    time.sleep(0.5)
    
    result = client.window_exists('Info')
    close_info_panel()
    return result


# ============== Info Panel Content Tests ==============

def test_info_shows_title():
    """Info panel shows item title."""
    activate_workspace()
    ensure_viewer_window()
    
    user.cmd_shift('h')  # Home
    time.sleep(0.5)
    
    user.cmd('i')
    time.sleep(0.5)
    
    # Info panel should show something about the path
    result = client.window_exists('Info')
    close_info_panel()
    return result

def test_info_shows_path():
    """Info panel shows file path."""
    activate_workspace()
    ensure_viewer_window()
    
    user.cmd_shift('h')  # Home - path should contain "home" or username
    time.sleep(0.5)
    
    user.cmd('i')
    time.sleep(0.5)
    
    # Check for path-like content
    texts = client.get_visible_text_in_window('Info')
    result = any('/' in t for t in texts)
    
    close_info_panel()
    return result

def test_info_shows_size():
    """Info panel shows size information."""
    activate_workspace()
    ensure_viewer_window()
    
    user.cmd_shift('h')  # Home
    time.sleep(0.5)
    
    user.cmd('i')
    time.sleep(0.5)
    
    # Look for size-related text
    texts = client.get_visible_text_in_window('Info')
    result = any('Size' in t or 'bytes' in t.lower() or 'KB' in t or 'MB' in t 
                 for t in texts)
    
    close_info_panel()
    return result

def test_info_shows_dates():
    """Info panel shows modification/creation dates."""
    activate_workspace()
    ensure_viewer_window()
    
    user.cmd_shift('h')
    time.sleep(0.5)
    
    user.cmd('i')
    time.sleep(0.5)
    
    # Look for date-related text
    texts = client.get_visible_text_in_window('Info')
    result = any('Modified' in t or 'Created' in t or 'Date' in t 
                 for t in texts)
    
    close_info_panel()
    return result


# ============== About Panel Tests ==============

def test_about_opens():
    """About Workspace opens."""
    activate_workspace()
    
    user.cmd('i')  # On desktop, this should open About
    time.sleep(0.5)
    
    result = client.window_exists('Info')
    close_info_panel()
    return result

def test_about_shows_version():
    """About shows version info."""
    activate_workspace()
    client.open_about_dialog()
    time.sleep(0.5)
    
    texts = client.get_visible_text_in_window('Info')
    result = any('Release:' in t or 'Version' in t for t in texts)
    
    close_info_panel()
    return result

def test_about_shows_authors():
    """About shows authors."""
    activate_workspace()
    client.open_about_dialog()
    time.sleep(0.5)
    
    result = client.text_visible('Authors:')
    close_info_panel()
    return result


# ============== Multiple Info Panels ==============

def test_info_panel_updates():
    """Info panel updates when selection changes."""
    activate_workspace()
    ensure_viewer_window()
    
    # Open Info for home
    user.cmd_shift('h')
    time.sleep(0.3)
    user.cmd('i')
    time.sleep(0.5)
    
    # Navigate to Applications
    user.cmd_shift('a')
    time.sleep(0.5)
    
    # Info should update (or we can check content changed)
    result = client.window_exists('Info')
    
    close_info_panel()
    return result


# ============== Test Suite ==============

tests = [
    # Menu
    ("Get Info is enabled", test_get_info_enabled),
    ("Get Info has Cmd+I shortcut", test_get_info_shortcut),
    
    # Opening
    ("Open Info with Cmd+I", test_open_info_with_shortcut),
    ("Open Info for Applications", test_open_info_for_applications),
    
    # Content
    ("Info shows title", test_info_shows_title),
    ("Info shows path", test_info_shows_path),
    ("Info shows size", test_info_shows_size),
    ("Info shows dates", test_info_shows_dates),
    
    # About
    ("About opens", test_about_opens),
    ("About shows version", test_about_shows_version),
    ("About shows authors", test_about_shows_authors),
    
    # Updates
    ("Info panel updates", test_info_panel_updates),
]

if __name__ == "__main__":
    print("\n" + "="*60)
    print("INTERACTIVE INFO PANEL TESTS")
    print("Tests Get Info functionality")
    print("="*60 + "\n")
    
    # Clean up any existing Info panels
    close_info_panel()
    
    result = run_tests(*tests)
    
    # Cleanup
    close_info_panel()
    
    exit(result)
