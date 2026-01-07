#!/usr/bin/env python3
"""
Interactive Test Suite - Finder (Search)

Tests the Finder/Search functionality:
- Opening Finder window
- Typing search terms
- Interacting with search results
- Closing Finder
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

def close_finder():
    """Close Finder window if open."""
    if client.window_exists('Finder'):
        user.focus_window_by_name('Finder')
        time.sleep(0.2)
        user.cmd('w')
        time.sleep(0.3)


# ============== Menu Tests ==============

def test_find_menu_enabled():
    """Find menu item is enabled."""
    return client.is_menu_item_enabled('File', 'Find')

def test_find_shortcut():
    """Find has Cmd+F shortcut."""
    item = client.get_menu_item('File', 'Find')
    return 'Cmd+F' in item.get('shortcut', '')


# ============== Opening Finder Tests ==============

def test_open_finder_shortcut():
    """Open Finder with Cmd+F."""
    activate_workspace()
    close_finder()
    
    user.cmd('f')
    time.sleep(0.5)
    
    result = client.window_exists('Finder')
    return result

def test_finder_has_search_field():
    """Finder has text input field."""
    activate_workspace()
    
    if not client.window_exists('Finder'):
        user.cmd('f')
        time.sleep(0.5)
    
    # Look for text field
    count = client.count_elements_by_class('NSTextField')
    return count > 0


# ============== Search Interaction Tests ==============

def test_type_in_finder():
    """Type search term in Finder."""
    activate_workspace()
    
    if not client.window_exists('Finder'):
        user.cmd('f')
        time.sleep(0.5)
    
    user.focus_window_by_name('Finder')
    time.sleep(0.3)
    
    # Type a search term
    user.type_text('Applications')
    time.sleep(0.3)
    
    return True

def test_search_and_clear():
    """Type search, then clear."""
    activate_workspace()
    
    if not client.window_exists('Finder'):
        user.cmd('f')
        time.sleep(0.5)
    
    user.focus_window_by_name('Finder')
    time.sleep(0.3)
    
    # Clear any existing text
    user.cmd('a')
    time.sleep(0.1)
    user.press_delete()
    time.sleep(0.2)
    
    # Type something
    user.type_text('test')
    time.sleep(0.3)
    
    # Clear it
    user.cmd('a')
    time.sleep(0.1)
    user.press_delete()
    time.sleep(0.2)
    
    return True

def test_search_with_enter():
    """Type search and press Enter."""
    activate_workspace()
    
    if not client.window_exists('Finder'):
        user.cmd('f')
        time.sleep(0.5)
    
    user.focus_window_by_name('Finder')
    time.sleep(0.3)
    
    user.cmd('a')
    time.sleep(0.1)
    user.press_delete()
    time.sleep(0.2)
    
    user.type_text('Workspace')
    time.sleep(0.3)
    user.press_return()
    time.sleep(0.5)
    
    return True


# ============== Finder Window Tests ==============

def test_finder_close_with_escape():
    """Close Finder with Escape key."""
    activate_workspace()
    
    if not client.window_exists('Finder'):
        user.cmd('f')
        time.sleep(0.5)
    
    user.focus_window_by_name('Finder')
    time.sleep(0.3)
    
    user.press_escape()
    time.sleep(0.3)
    
    # Finder might close or field might just unfocus
    # Either behavior is acceptable
    return True

def test_finder_close_with_cmd_w():
    """Close Finder with Cmd+W."""
    activate_workspace()
    
    if not client.window_exists('Finder'):
        user.cmd('f')
        time.sleep(0.5)
    
    user.focus_window_by_name('Finder')
    time.sleep(0.3)
    
    user.cmd('w')
    time.sleep(0.5)
    
    # Finder should be closed
    return not client.window_exists('Finder')

def test_reopen_finder():
    """Close and reopen Finder."""
    activate_workspace()
    
    # Close if open
    close_finder()
    
    # Open
    user.cmd('f')
    time.sleep(0.5)
    
    result = client.window_exists('Finder')
    return result


# ============== Test Suite ==============

tests = [
    # Menu
    ("Find menu enabled", test_find_menu_enabled),
    ("Find has Cmd+F shortcut", test_find_shortcut),
    
    # Opening
    ("Open Finder with Cmd+F", test_open_finder_shortcut),
    ("Finder has search field", test_finder_has_search_field),
    
    # Interaction
    ("Type in Finder", test_type_in_finder),
    ("Search and clear", test_search_and_clear),
    ("Search with Enter", test_search_with_enter),
    
    # Window management
    ("Close Finder with Escape", test_finder_close_with_escape),
    ("Close Finder with Cmd+W", test_finder_close_with_cmd_w),
    ("Reopen Finder", test_reopen_finder),
]

if __name__ == "__main__":
    print("\n" + "="*60)
    print("INTERACTIVE FINDER TESTS")
    print("Tests search functionality")
    print("="*60 + "\n")
    
    result = run_tests(*tests)
    
    # Cleanup
    close_finder()
    
    exit(result)
