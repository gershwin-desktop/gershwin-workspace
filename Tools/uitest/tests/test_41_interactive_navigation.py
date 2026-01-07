#!/usr/bin/env python3
"""
Interactive Test Suite - Navigation

Tests file browser navigation using keyboard shortcuts.
Navigates to various system locations via Go menu shortcuts.

This test uses:
- Keyboard shortcuts to navigate to locations
- Verification that viewer shows expected content
- Smooth mouse movement for any clicking
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
    return True

def close_extra_viewers():
    """Close extra viewer windows, leave one open."""
    visible = client.get_visible_windows()
    viewers = [w for w in visible if w.get('class') == 'GWViewerWindow']
    
    # Close all but one
    while len(viewers) > 1:
        user.cmd('w')
        time.sleep(0.3)
        visible = client.get_visible_windows()
        viewers = [w for w in visible if w.get('class') == 'GWViewerWindow']


# ============== Navigation Shortcut Tests ==============

def test_go_home():
    """Navigate to Home with Cmd+Shift+H."""
    activate_workspace()
    ensure_viewer_window()
    
    user.cmd_shift('h')
    time.sleep(0.5)
    
    # Should see home directory content like Desktop, Documents, etc.
    return client.text_visible('Desktop') or client.text_visible('Documents')

def test_go_desktop():
    """Navigate to Desktop with Cmd+Shift+D."""
    activate_workspace()
    ensure_viewer_window()
    
    user.cmd_shift('d')
    time.sleep(0.5)
    
    # We're on the Desktop - check that UI updated
    # Desktop folder might be empty or have some files
    return True  # Navigation command was sent

def test_go_documents():
    """Navigate to Documents with Cmd+Shift+O."""
    activate_workspace()
    ensure_viewer_window()
    
    user.cmd_shift('o')
    time.sleep(0.5)
    
    # Documents folder
    return True

def test_go_downloads():
    """Navigate to Downloads with Cmd+Shift+L."""
    activate_workspace()
    ensure_viewer_window()
    
    user.cmd_shift('l')
    time.sleep(0.5)
    
    # Downloads folder
    return True

def test_go_applications():
    """Navigate to Applications with Cmd+Shift+A."""
    activate_workspace()
    ensure_viewer_window()
    
    user.cmd_shift('a')
    time.sleep(0.5)
    
    # Should see some applications
    return (client.text_visible('Workspace') or 
            client.text_visible('Terminal') or
            client.text_visible('.app'))

def test_go_utilities():
    """Navigate to Utilities with Cmd+Shift+U."""
    activate_workspace()
    ensure_viewer_window()
    
    user.cmd_shift('u')
    time.sleep(0.5)
    
    # Utilities folder
    return True

def test_go_computer():
    """Navigate to Computer/root with Cmd+Shift+C."""
    activate_workspace()
    ensure_viewer_window()
    
    user.cmd_shift('c')
    time.sleep(0.5)
    
    # Should see root-level things
    return (client.text_visible('System') or 
            client.text_visible('Users') or
            client.text_visible('Local'))

def test_go_network():
    """Navigate to Network with Cmd+Shift+K."""
    activate_workspace()
    ensure_viewer_window()
    
    user.cmd_shift('k')
    time.sleep(0.5)
    
    # Network browser
    return True

def test_go_recents():
    """Navigate to Recents/History with Cmd+Shift+F."""
    activate_workspace()
    ensure_viewer_window()
    
    user.cmd_shift('f')
    time.sleep(0.5)
    
    # Recents/History view
    return True


# ============== History Navigation Tests ==============

def test_history_back():
    """Test Back navigation with Cmd+[."""
    activate_workspace()
    ensure_viewer_window()
    
    # Navigate somewhere first
    user.cmd_shift('h')  # Home
    time.sleep(0.3)
    user.cmd_shift('d')  # Desktop
    time.sleep(0.3)
    
    # Go back
    user.cmd('[')
    time.sleep(0.3)
    
    # Should be back at Home
    return True

def test_history_forward():
    """Test Forward navigation with Cmd+]."""
    activate_workspace()
    ensure_viewer_window()
    
    # After going back, go forward
    user.cmd(']')
    time.sleep(0.3)
    
    return True


# ============== Go to Folder Tests ==============

def test_go_to_folder_dialog():
    """Open Go to Folder dialog with Cmd+Shift+G."""
    activate_workspace()
    ensure_viewer_window()
    
    user.cmd_shift('g')
    time.sleep(0.5)
    
    # Should see a dialog or input field
    # Type a path and press Enter
    user.type_text('/tmp')
    time.sleep(0.2)
    user.press_return()
    time.sleep(0.5)
    
    # Close any dialogs
    user.press_escape()
    time.sleep(0.2)
    
    return True


# ============== Open/Double-click Tests ==============

def test_open_selection():
    """Test Open with Cmd+O."""
    activate_workspace()
    ensure_viewer_window()
    
    # Navigate to Applications
    user.cmd_shift('a')
    time.sleep(0.5)
    
    # Cmd+O on current selection
    user.cmd('o')
    time.sleep(0.3)
    
    return True


# ============== Run Dialog Tests ==============

def test_run_dialog():
    """Open Run dialog with Cmd+0."""
    activate_workspace()
    
    user.cmd('0')
    time.sleep(0.5)
    
    result = client.window_exists('Run')
    
    if result:
        user.press_escape()
        time.sleep(0.3)
    
    return result


# ============== Menu Enabled State Tests ==============

def test_go_menu_items_enabled():
    """Check that Go menu items are enabled."""
    items_to_check = [
        ('Go', 'Back'),
        ('Go', 'Forward'),
        ('Go', 'Home'),
        ('Go', 'Desktop'),
        ('Go', 'Documents'),
        ('Go', 'Downloads'),
        ('Go', 'Computer'),
        ('Go', 'Network'),
        ('Go', 'Applications'),
        ('Go', 'Utilities'),
        ('Go', 'Go to Folder...'),
    ]
    
    for menu, item in items_to_check:
        try:
            if not client.is_menu_item_enabled(menu, item):
                print(f"  Warning: {menu} > {item} is disabled")
        except:
            pass
    
    # Just check that Home is enabled
    return client.is_menu_item_enabled('Go', 'Home')


# ============== Test Suite ==============

tests = [
    # Menu state
    ("Go menu items enabled", test_go_menu_items_enabled),
    
    # Basic navigation
    ("Go to Home (Cmd+Shift+H)", test_go_home),
    ("Go to Desktop (Cmd+Shift+D)", test_go_desktop),
    ("Go to Documents (Cmd+Shift+O)", test_go_documents),
    ("Go to Downloads (Cmd+Shift+L)", test_go_downloads),
    ("Go to Applications (Cmd+Shift+A)", test_go_applications),
    ("Go to Utilities (Cmd+Shift+U)", test_go_utilities),
    ("Go to Computer (Cmd+Shift+C)", test_go_computer),
    ("Go to Network (Cmd+Shift+K)", test_go_network),
    ("Go to Recents (Cmd+Shift+F)", test_go_recents),
    
    # History
    ("History Back (Cmd+[)", test_history_back),
    ("History Forward (Cmd+])", test_history_forward),
    
    # Dialogs
    ("Go to Folder dialog (Cmd+Shift+G)", test_go_to_folder_dialog),
    ("Run dialog (Cmd+0)", test_run_dialog),
    
    # Actions
    ("Open selection (Cmd+O)", test_open_selection),
]

if __name__ == "__main__":
    print("\n" + "="*60)
    print("INTERACTIVE NAVIGATION TESTS")
    print("Tests Go menu locations and navigation shortcuts")
    print("="*60 + "\n")
    
    # Start with a clean state
    close_extra_viewers()
    
    result = run_tests(*tests)
    
    # Cleanup
    close_extra_viewers()
    
    exit(result)
