#!/usr/bin/env python3
"""
Interactive Test Suite - Menu System

Tests all menu operations with human-like mouse movement.
Uses xdotool for input simulation and verifies menu state.

This test drives the UI exactly like a human would:
- Smooth mouse movements
- Click on menu bar
- Navigate dropdown menus
- Verify menu items open correct windows/dialogs

FEATURES:
- Non-blocking modal detection (uses xdotool, not uitest)
- Screenshot + log capture on any failure
- Pre-click focus checking
"""

import sys
import os
import time
import traceback

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'python'))

from uitest import WorkspaceTestClient
from user_input import UserInput
from modal_handler import ModalHandler, get_handler
from test_failure_capture import FailureCapture, get_capture

# Import test utilities
from test_utils import (
    ensure_clean_state, dismiss_all_modals, activate_workspace,
    close_window_by_title, MENU_POSITIONS, MENU_BAR_Y, SCREEN_WIDTH, SCREEN_HEIGHT,
    safe_click, run_test_safely, get_failure_capture as get_test_capture
)

# Initialize
client = WorkspaceTestClient()
user = UserInput()
modal_handler = get_handler()
capture = get_capture()


def get_desktop_window_id():
    """Find the desktop window ID."""
    result = user._run("search", "--name", "")
    if result:
        for wid in result.split('\n'):
            try:
                geom = user.get_window_geometry(wid)
                if geom[2] == SCREEN_WIDTH and geom[3] == SCREEN_HEIGHT:
                    return wid
            except:
                pass
    return None


def click_menu(menu_name, smooth=True):
    """Click on a menu in the menu bar with pre-click focus check."""
    # Check for focus stealers first
    modal = modal_handler.detect_modal_dialog()
    if modal:
        capture.log(f"Pre-click: dismissing modal '{modal.name}'")
        modal_handler.dismiss_focus_stealer()
    
    x = MENU_POSITIONS.get(menu_name, 100)
    if smooth:
        user.click_smooth(x, MENU_BAR_Y)
    else:
        user.click(x, MENU_BAR_Y)
    time.sleep(0.3)


def dismiss_menu():
    """Dismiss any open menu by pressing Escape."""
    user.press_escape()
    time.sleep(0.2)

def click_menu_item_by_offset(menu_name, item_index, smooth=True):
    """
    Click a menu item by its position in the dropdown.
    
    item_index: 0-based index of menu item (separators count)
    """
    # First click the menu
    click_menu(menu_name, smooth)
    time.sleep(0.2)
    
    # Menu items are approximately 22 pixels high
    # First item starts around y=35 (menu bar height + some padding)
    x = MENU_POSITIONS.get(menu_name, 100)
    y = 35 + (item_index * 22)
    
    if smooth:
        user.click_smooth(x, y)
    else:
        user.click(x, y)
    time.sleep(0.3)

def dismiss_menu():
    """Dismiss any open menu by clicking elsewhere."""
    user.press_escape()
    time.sleep(0.2)

def close_current_window():
    """Close the current window with Cmd+W."""
    user.cmd('w')
    time.sleep(0.3)


# ============== Test Functions ==============

def test_menu_state_available():
    """Verify we can query menu state."""
    state = client.get_menu_state()
    return state.get('success', False) and len(state.get('menus', [])) > 0

def test_file_menu_has_items():
    """File menu has expected items."""
    items = client.get_menu_items('File')
    titles = [i.get('title', '') for i in items if not i.get('separator')]
    return 'New Workspace Window' in titles and 'Close Window' in titles

def test_new_folder_is_disabled():
    """New Folder is disabled (not implemented)."""
    return not client.is_menu_item_enabled('File', 'New Folder')

def test_new_workspace_window_enabled():
    """New Workspace Window is enabled."""
    return client.is_menu_item_enabled('File', 'New Workspace Window')

def test_about_menu_enabled():
    """About Workspace is enabled."""
    return client.is_menu_item_enabled('Workspace', 'About Workspace')

def test_preferences_enabled():
    """Preferences is enabled."""
    return client.is_menu_item_enabled('Workspace', 'Preferences...')

def test_find_enabled():
    """Find is enabled."""
    return client.is_menu_item_enabled('File', 'Find')

def test_get_info_enabled():
    """Get Info is enabled."""
    return client.is_menu_item_enabled('File', 'Get Info')


# ============== Interactive Menu Tests ==============

def test_click_workspace_menu():
    """Click Workspace menu and dismiss."""
    activate_workspace()
    click_menu('Workspace', smooth=True)
    time.sleep(0.5)
    # Menu should be visible
    dismiss_menu()
    return True

def test_click_file_menu():
    """Click File menu and dismiss."""
    activate_workspace()
    click_menu('File', smooth=True)
    time.sleep(0.5)
    dismiss_menu()
    return True

def test_click_edit_menu():
    """Click Edit menu and dismiss."""
    activate_workspace()
    click_menu('Edit', smooth=True)
    time.sleep(0.5)
    dismiss_menu()
    return True

def test_click_view_menu():
    """Click View menu and dismiss."""
    activate_workspace()
    click_menu('View', smooth=True)
    time.sleep(0.5)
    dismiss_menu()
    return True

def test_click_go_menu():
    """Click Go menu and dismiss."""
    activate_workspace()
    click_menu('Go', smooth=True)
    time.sleep(0.5)
    dismiss_menu()
    return True

def test_click_tools_menu():
    """Click Tools menu and dismiss."""
    activate_workspace()
    click_menu('Tools', smooth=True)
    time.sleep(0.5)
    dismiss_menu()
    return True

def test_click_window_menu():
    """Click Window menu and dismiss."""
    activate_workspace()
    click_menu('Window', smooth=True)
    time.sleep(0.5)
    dismiss_menu()
    return True

def test_click_help_menu():
    """Click Help menu and dismiss."""
    activate_workspace()
    click_menu('Help', smooth=True)
    time.sleep(0.5)
    dismiss_menu()
    return True


# ============== Menu Action Tests ==============

def test_open_about_via_menu():
    """Open About Workspace via menu click (second item now)."""
    activate_workspace()
    
    # Click Workspace menu, then About Workspace (now second item)
    click_menu('Workspace', smooth=True)
    time.sleep(0.3)
    
    # About Workspace is second item
    x = MENU_POSITIONS['Workspace']
    user.click_smooth(x, 60)  # Second menu item
    time.sleep(0.5)
    
    # Verify Info panel opened
    result = client.window_exists('Info')
    if result:
        close_current_window()
    return result


def test_open_about_computer_via_menu():
    """Open About This Computer via menu click (first item)."""
    activate_workspace()

    # Click Workspace menu, then About This Computer (first item)
    click_menu('Workspace', smooth=True)
    time.sleep(0.3)

    x = MENU_POSITIONS['Workspace']
    user.click_smooth(x, 38)  # First menu item (About This Computer)
    time.sleep(0.5)

    # Verify About window opened
    result = client.window_exists('About This Computer')
    if result:
        close_current_window()
    return result

def test_open_preferences_via_menu():
    """Open Preferences via Workspace menu."""
    activate_workspace()
    
    click_menu('Workspace', smooth=True)
    time.sleep(0.3)
    
    # Preferences is after About and separator (index ~2)
    x = MENU_POSITIONS['Workspace']
    user.click_smooth(x, 70)  # Preferences position
    time.sleep(0.5)
    
    result = client.window_exists('Workspace Preferences')
    if result:
        close_current_window()
    return result

def test_open_new_viewer_via_menu():
    """Open new Workspace Window via File menu."""
    activate_workspace()
    
    # Count viewers before
    visible = client.get_visible_windows()
    viewer_count_before = sum(1 for w in visible if w.get('class') == 'GWViewerWindow')
    
    click_menu('File', smooth=True)
    time.sleep(0.3)
    
    # New Workspace Window is first item
    x = MENU_POSITIONS['File']
    user.click_smooth(x, 38)
    time.sleep(0.5)
    
    # Count viewers after
    visible = client.get_visible_windows()
    viewer_count_after = sum(1 for w in visible if w.get('class') == 'GWViewerWindow')
    
    if viewer_count_after > viewer_count_before:
        close_current_window()
        return True
    return False

def test_open_find_via_menu():
    """Open Finder via File menu."""
    activate_workspace()
    
    click_menu('File', smooth=True)
    time.sleep(0.3)
    
    # Find is further down in File menu
    x = MENU_POSITIONS['File']
    # Scroll down through File menu items to Find
    user.move_mouse_smoothly(x, 300)  # Move to lower part of menu
    time.sleep(0.2)
    
    # Look for Find item and click it
    # Find has shortcut Cmd+F
    user.click_smooth(x, 320)  # Approximate position for Find
    time.sleep(0.5)
    
    result = client.window_exists('Finder')
    if result:
        close_current_window()
    return result


# ============== Keyboard Shortcut Tests ==============

def test_shortcut_new_viewer():
    """Open new viewer with Cmd+N."""
    activate_workspace()
    
    visible = client.get_visible_windows()
    viewer_count_before = sum(1 for w in visible if w.get('class') == 'GWViewerWindow')
    
    user.cmd('n')
    time.sleep(0.5)
    
    visible = client.get_visible_windows()
    viewer_count_after = sum(1 for w in visible if w.get('class') == 'GWViewerWindow')
    
    if viewer_count_after > viewer_count_before:
        close_current_window()
        return True
    return False

def test_shortcut_preferences():
    """Open Preferences with Cmd+,."""
    activate_workspace()
    user.cmd('comma')
    time.sleep(0.5)
    
    result = client.window_exists('Workspace Preferences')
    if result:
        close_current_window()
    return result

def test_shortcut_about():
    """Open About/Info with Cmd+I on desktop."""
    activate_workspace()
    user.cmd('i')
    time.sleep(0.5)
    
    result = client.window_exists('Info')
    if result:
        close_current_window()
    return result

def test_shortcut_find():
    """Open Finder with Cmd+F."""
    activate_workspace()
    user.cmd('f')
    time.sleep(0.5)
    
    result = client.window_exists('Finder')
    if result:
        close_current_window()
    return result


# ============== Test Suite ==============

tests = [
    # Menu state tests
    ("Menu state API available", test_menu_state_available),
    ("File menu has items", test_file_menu_has_items),
    ("New Folder is disabled", test_new_folder_is_disabled),
    ("New Workspace Window enabled", test_new_workspace_window_enabled),
    ("About Workspace enabled", test_about_menu_enabled),
    ("Preferences enabled", test_preferences_enabled),
    ("Find enabled", test_find_enabled),
    ("Get Info enabled", test_get_info_enabled),
    
    # Menu click tests
    ("Click Workspace menu", test_click_workspace_menu),
    ("Click File menu", test_click_file_menu),
    ("Click Edit menu", test_click_edit_menu),
    ("Click View menu", test_click_view_menu),
    ("Click Go menu", test_click_go_menu),
    ("Click Tools menu", test_click_tools_menu),
    ("Click Window menu", test_click_window_menu),
    ("Click Help menu", test_click_help_menu),
    
    # Menu action tests
    ("Open About via menu", test_open_about_via_menu),
    ("Open Preferences via menu", test_open_preferences_via_menu),
    ("Open new viewer via menu", test_open_new_viewer_via_menu),
    ("Open Find via menu", test_open_find_via_menu),
    
    # Keyboard shortcut tests  
    ("Shortcut: New viewer (Cmd+N)", test_shortcut_new_viewer),
    ("Shortcut: Preferences (Cmd+,)", test_shortcut_preferences),
    ("Shortcut: About/Info (Cmd+I)", test_shortcut_about),
    ("Shortcut: Find (Cmd+F)", test_shortcut_find),
]


def run_tests_with_capture(test_list):
    """Run tests with full failure capture."""
    passed = 0
    failed = 0
    
    for name, func in test_list:
        capture.set_test_name(name)
        capture.log(f"Running: {name}")
        
        # Pre-test: check for modals
        modal = modal_handler.detect_modal_dialog()
        if modal:
            capture.log(f"Pre-test modal detected: {modal.name}")
            modal_handler.dismiss_focus_stealer()
            time.sleep(0.2)
        
        try:
            result = func()
            if result:
                print(f"  ✓ {name}")
                passed += 1
            else:
                print(f"  ✗ {name} (returned False)")
                capture.log(f"Test returned False")
                capture.take_screenshot(f"FAIL_{name.replace(' ', '_')}")
                capture.save_log("Test returned False")
                failed += 1
        except Exception as e:
            print(f"  ✗ {name} ({type(e).__name__}: {e})")
            capture.log(f"Exception: {type(e).__name__}: {e}")
            capture.log(f"Traceback:\n{traceback.format_exc()}")
            capture.take_screenshot(f"ERROR_{name.replace(' ', '_')}")
            capture.save_log(traceback.format_exc())
            failed += 1
        
        # Small delay between tests
        time.sleep(0.2)
    
    return passed, failed


if __name__ == "__main__":
    print("\n" + "="*60)
    print("INTERACTIVE MENU TESTS")
    print("Uses smooth mouse movement and keyboard shortcuts")
    print("Failure screenshots saved to: /tmp/uitest_failures/")
    print("="*60 + "\n")
    
    capture.set_test_name("test_40_startup")
    capture.log("Starting interactive menu tests")
    
    # Initial state check using non-blocking method
    modal = modal_handler.detect_modal_dialog()
    if modal:
        capture.log(f"Initial modal detected: {modal.name}")
        modal_handler.dismiss_focus_stealer()
    
    # Activate Workspace
    activate_workspace()
    time.sleep(0.5)
    
    # Run tests
    passed, failed = run_tests_with_capture(tests)
    
    # Summary
    print("\n" + "="*60)
    print(f"RESULTS: {passed} passed, {failed} failed")
    print("="*60)
    
    if failed > 0:
        print(f"Failure logs saved to: /tmp/uitest_failures/")
    
    # Final cleanup - dismiss any open menus/dialogs
    user.press_escape()
    time.sleep(0.1)
    user.press_escape()
    
    exit(0 if failed == 0 else 1)
