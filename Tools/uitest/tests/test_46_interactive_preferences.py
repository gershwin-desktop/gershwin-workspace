#!/usr/bin/env python3
"""
Interactive Test Suite - Preferences

Tests the Preferences panel:
- Opening Preferences
- Navigating preference panes
- Closing Preferences
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

def close_preferences():
    """Close Preferences window if open."""
    if client.window_exists('Workspace Preferences'):
        user.focus_window_by_name('Workspace Preferences')
        time.sleep(0.2)
        user.cmd('w')
        time.sleep(0.3)


# ============== Menu Tests ==============

def test_preferences_menu_enabled():
    """Preferences menu item is enabled."""
    return client.is_menu_item_enabled('Workspace', 'Preferences...')

def test_preferences_shortcut():
    """Preferences has Cmd+, shortcut."""
    item = client.get_menu_item('Workspace', 'Preferences...')
    return 'Cmd+,' in item.get('shortcut', '')


# ============== Opening Tests ==============

def test_open_preferences_shortcut():
    """Open Preferences with Cmd+,."""
    activate_workspace()
    close_preferences()
    
    user.cmd('comma')
    time.sleep(0.5)
    
    result = client.window_exists('Workspace Preferences')
    return result

def test_preferences_has_content():
    """Preferences window has content."""
    activate_workspace()
    
    if not client.window_exists('Workspace Preferences'):
        user.cmd('comma')
        time.sleep(0.5)
    
    # Should have some preferences UI
    texts = client.get_visible_text_in_window('Workspace Preferences')
    return len(texts) > 0


# ============== Preference Pane Tests ==============

def test_preferences_has_icons():
    """Preferences has toolbar icons."""
    activate_workspace()
    
    if not client.window_exists('Workspace Preferences'):
        user.cmd('comma')
        time.sleep(0.5)
    
    # Look for icons or toolbar
    icons = client.count_elements_by_class('NSImageView')
    buttons = client.count_elements_by_class('NSButton')
    
    return icons > 0 or buttons > 0

def test_click_preference_pane():
    """Click on a preference pane."""
    activate_workspace()
    
    if not client.window_exists('Workspace Preferences'):
        user.cmd('comma')
        time.sleep(0.5)
    
    user.focus_window_by_name('Workspace Preferences')
    time.sleep(0.3)
    
    # Click somewhere in the preferences window
    # Typically preference icons are in a toolbar at top
    user.click_smooth(200, 100)
    time.sleep(0.5)
    
    return True


# ============== Close Tests ==============

def test_close_preferences_shortcut():
    """Close Preferences with Cmd+W."""
    activate_workspace()
    
    if not client.window_exists('Workspace Preferences'):
        user.cmd('comma')
        time.sleep(0.5)
    
    user.focus_window_by_name('Workspace Preferences')
    time.sleep(0.3)
    
    user.cmd('w')
    time.sleep(0.5)
    
    return not client.window_exists('Workspace Preferences')

def test_reopen_preferences():
    """Close and reopen Preferences."""
    activate_workspace()
    close_preferences()
    
    user.cmd('comma')
    time.sleep(0.5)
    
    result = client.window_exists('Workspace Preferences')
    close_preferences()
    return result


# ============== Test Suite ==============

tests = [
    # Menu
    ("Preferences menu enabled", test_preferences_menu_enabled),
    ("Preferences has Cmd+, shortcut", test_preferences_shortcut),
    
    # Opening
    ("Open Preferences with Cmd+,", test_open_preferences_shortcut),
    ("Preferences has content", test_preferences_has_content),
    
    # Content
    ("Preferences has icons", test_preferences_has_icons),
    ("Click preference pane", test_click_preference_pane),
    
    # Closing
    ("Close Preferences with Cmd+W", test_close_preferences_shortcut),
    ("Reopen Preferences", test_reopen_preferences),
]

if __name__ == "__main__":
    print("\n" + "="*60)
    print("INTERACTIVE PREFERENCES TESTS")
    print("Tests Preferences panel functionality")
    print("="*60 + "\n")
    
    result = run_tests(*tests)
    
    # Cleanup
    close_preferences()
    
    exit(result)
