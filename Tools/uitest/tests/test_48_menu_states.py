#!/usr/bin/env python3
"""
Interactive Test Suite - Menu State Verification

Comprehensive test of all menu items and their enabled/disabled states.
This test documents which features are implemented and which are not.

Uses the list-menus capability to inspect menu state without clicking.
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


# ============== Menu State API Tests ==============

def test_list_menus_available():
    """The list-menus API is available."""
    state = client.get_menu_state()
    return state.get('success', False)

def test_all_menus_present():
    """All expected menus are present."""
    state = client.get_menu_state()
    menus = state.get('menus', [])
    menu_names = [m.get('title') for m in menus]
    
    expected = ['Workspace', 'File', 'Edit', 'View', 'Go', 'Tools', 'Window', 'Help']
    
    for exp in expected:
        if exp not in menu_names:
            print(f"  Missing menu: {exp}")
            return False
    return True


# ============== Workspace Menu Tests ==============

def test_workspace_about_enabled():
    """About Workspace is enabled."""
    return client.is_menu_item_enabled('Workspace', 'About Workspace')

def test_workspace_preferences_enabled():
    """Preferences is enabled."""
    return client.is_menu_item_enabled('Workspace', 'Preferences...')

def test_workspace_hide_enabled():
    """Hide Workspace is enabled."""
    return client.is_menu_item_enabled('Workspace', 'Hide Workspace')

def test_workspace_logout_enabled():
    """Logout is enabled."""
    return client.is_menu_item_enabled('Workspace', 'Logout')


# ============== File Menu Tests ==============

def test_file_new_window_enabled():
    """New Workspace Window is enabled."""
    return client.is_menu_item_enabled('File', 'New Workspace Window')

def test_file_new_folder_disabled():
    """New Folder is disabled (not implemented)."""
    return not client.is_menu_item_enabled('File', 'New Folder')

def test_file_open_enabled():
    """Open is enabled."""
    return client.is_menu_item_enabled('File', 'Open')

def test_file_close_enabled():
    """Close Window is enabled."""
    return client.is_menu_item_enabled('File', 'Close Window')

def test_file_get_info_enabled():
    """Get Info is enabled."""
    return client.is_menu_item_enabled('File', 'Get Info')

def test_file_find_enabled():
    """Find is enabled."""
    return client.is_menu_item_enabled('File', 'Find')

def test_file_duplicate_state():
    """Duplicate state is contextual."""
    # Duplicate should be disabled when nothing is selected
    item = client.get_menu_item('File', 'Duplicate')
    return item is not None  # Item exists


# ============== Edit Menu Tests ==============

def test_edit_undo_enabled():
    """Undo is enabled."""
    return client.is_menu_item_enabled('Edit', 'Undo')

def test_edit_copy_enabled():
    """Copy is enabled."""
    return client.is_menu_item_enabled('Edit', 'Copy')

def test_edit_paste_state():
    """Paste state depends on clipboard."""
    item = client.get_menu_item('Edit', 'Paste')
    return item is not None


# ============== View Menu Tests ==============

def test_view_as_icons_exists():
    """as Icons view exists."""
    item = client.get_menu_item('View', 'as Icons')
    return item.get('action') == 'setViewerType:'

def test_view_as_list_exists():
    """as List view exists."""
    item = client.get_menu_item('View', 'as List')
    return item.get('action') == 'setViewerType:'

def test_view_as_columns_exists():
    """as Columns view exists."""
    item = client.get_menu_item('View', 'as Columns')
    return item.get('action') == 'setViewerType:'

def test_view_fullscreen_enabled():
    """Enter Full Screen is enabled."""
    return client.is_menu_item_enabled('View', 'Enter Full Screen')


# ============== Go Menu Tests ==============

def test_go_back_enabled():
    """Back is enabled."""
    return client.is_menu_item_enabled('Go', 'Back')

def test_go_forward_enabled():
    """Forward is enabled."""
    return client.is_menu_item_enabled('Go', 'Forward')

def test_go_home_enabled():
    """Home is enabled."""
    return client.is_menu_item_enabled('Go', 'Home')

def test_go_computer_enabled():
    """Computer is enabled."""
    return client.is_menu_item_enabled('Go', 'Computer')

def test_go_applications_enabled():
    """Applications is enabled."""
    return client.is_menu_item_enabled('Go', 'Applications')

def test_go_to_folder_enabled():
    """Go to Folder is enabled."""
    return client.is_menu_item_enabled('Go', 'Go to Folder...')


# ============== Tools Menu Tests ==============

def test_tools_run_enabled():
    """Run... is enabled."""
    return client.is_menu_item_enabled('Tools', 'Run...')


# ============== Window Menu Tests ==============

def test_window_minimize_state():
    """Minimize exists."""
    item = client.get_menu_item('Window', 'Minimize')
    return item is not None

def test_window_bring_all_enabled():
    """Bring All to Front is enabled."""
    return client.is_menu_item_enabled('Window', 'Bring All to Front')


# ============== Help Menu Tests ==============

def test_help_workspace_help_enabled():
    """Workspace Help is enabled."""
    return client.is_menu_item_enabled('Help', 'Workspace Help')


# ============== Summary Report ==============

def test_generate_report():
    """Generate summary of enabled/disabled items."""
    print("\n  --- Menu State Summary ---")
    
    enabled = client.get_enabled_menu_items()
    disabled = client.get_disabled_menu_items()
    
    print(f"\n  Enabled items: {len(enabled)}")
    print(f"  Disabled items: {len(disabled)}")
    
    if disabled:
        print("\n  Disabled items:")
        for item in disabled:
            menu = item.get('menu', '?')
            title = item.get('title', '?')
            action = item.get('action', 'no action')
            print(f"    {menu} > {title} ({action})")
    
    return True


# ============== Test Suite ==============

tests = [
    # API
    ("Menu state API available", test_list_menus_available),
    ("All menus present", test_all_menus_present),
    
    # Workspace menu
    ("Workspace > About enabled", test_workspace_about_enabled),
    ("Workspace > Preferences enabled", test_workspace_preferences_enabled),
    ("Workspace > Hide enabled", test_workspace_hide_enabled),
    ("Workspace > Logout enabled", test_workspace_logout_enabled),
    
    # File menu
    ("File > New Window enabled", test_file_new_window_enabled),
    ("File > New Folder disabled", test_file_new_folder_disabled),
    ("File > Open enabled", test_file_open_enabled),
    ("File > Close enabled", test_file_close_enabled),
    ("File > Get Info enabled", test_file_get_info_enabled),
    ("File > Find enabled", test_file_find_enabled),
    ("File > Duplicate exists", test_file_duplicate_state),
    
    # Edit menu
    ("Edit > Undo enabled", test_edit_undo_enabled),
    ("Edit > Copy enabled", test_edit_copy_enabled),
    ("Edit > Paste exists", test_edit_paste_state),
    
    # View menu
    ("View > as Icons exists", test_view_as_icons_exists),
    ("View > as List exists", test_view_as_list_exists),
    ("View > as Columns exists", test_view_as_columns_exists),
    ("View > Fullscreen enabled", test_view_fullscreen_enabled),
    
    # Go menu
    ("Go > Back enabled", test_go_back_enabled),
    ("Go > Forward enabled", test_go_forward_enabled),
    ("Go > Home enabled", test_go_home_enabled),
    ("Go > Computer enabled", test_go_computer_enabled),
    ("Go > Applications enabled", test_go_applications_enabled),
    ("Go > Go to Folder enabled", test_go_to_folder_enabled),
    
    # Tools menu
    ("Tools > Run enabled", test_tools_run_enabled),
    
    # Window menu
    ("Window > Minimize exists", test_window_minimize_state),
    ("Window > Bring All to Front enabled", test_window_bring_all_enabled),
    
    # Help menu
    ("Help > Workspace Help enabled", test_help_workspace_help_enabled),
    
    # Summary
    ("Generate state report", test_generate_report),
]

if __name__ == "__main__":
    print("\n" + "="*60)
    print("MENU STATE VERIFICATION")
    print("Tests which menu items are enabled/disabled")
    print("="*60 + "\n")
    exit(run_tests(*tests))
