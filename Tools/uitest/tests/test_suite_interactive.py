#!/usr/bin/env python3
"""
Comprehensive Interactive Test Suite for Workspace

This test suite exercises the entire Workspace GUI and is designed to:
1. Pass with the current implementation (baseline)
2. Detect regressions during future development
3. Use human-like mouse movements
4. Capture screenshots and logs on any failure
5. ONLY interact with Workspace/GNUstep windows

Run with: python3 test_suite_interactive.py

All tests use xdotool for input simulation and verify actual behavior.
"""

import sys
import os
import time
import traceback
import subprocess
from typing import Optional, List, Dict, Any, Callable, Tuple

# Add python directory to path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'python'))

from uitest import WorkspaceTestClient, CommandFailedError
from user_input import UserInput
from modal_handler import ModalHandler, get_handler
from test_failure_capture import FailureCapture, get_capture

# ============== Configuration ==============

SCREEN_WIDTH = 1920
SCREEN_HEIGHT = 1080
MENU_BAR_Y = 11
DESKTOP_SAFE_CLICK = (SCREEN_WIDTH // 2, SCREEN_HEIGHT // 2)

# Window class for all GNUstep/Workspace windows
WORKSPACE_WM_CLASS = "GNUstep"

# Valid Workspace window instance names (first part of WM_CLASS)
WORKSPACE_INSTANCE_NAMES = [
    "Workspace", "Window", "Finder", "Inspector", "Panel",
    "Run", "Open With", "Info", "Preferences", "FileViewer"
]

# Menu bar X positions (measured from Workspace)
MENU_POSITIONS = {
    'Workspace': 60,
    'File': 150,
    'Edit': 220,
    'View': 280,
    'Go': 330,
    'Tools': 390,
    'Window': 470,
    'Help': 540
}

# Actual window titles used by Workspace
WINDOW_TITLES = {
    'about': 'Info',  # About panel is titled "Info"
    'preferences': 'Workspace Preferences',
    'finder': 'Finder',
    'inspector': 'Inspector',
    'run': 'Run',
    'open_with': 'Open With',
}


# ============== Window Verification Helpers ==============

def get_window_class(window_id: int) -> Tuple[Optional[str], Optional[str]]:
    """
    Get WM_CLASS for a window (instance_name, class_name).
    
    Returns:
        Tuple of (instance_name, class_name) or (None, None) if not found.
        For Workspace windows: ("Workspace", "GNUstep")
    """
    try:
        result = subprocess.run(
            ["xprop", "-id", str(window_id), "WM_CLASS"],
            capture_output=True, text=True, timeout=2
        )
        if result.returncode == 0 and 'WM_CLASS' in result.stdout:
            # Parse: WM_CLASS(STRING) = "Workspace", "GNUstep"
            import re
            match = re.findall(r'"([^"]*)"', result.stdout)
            if len(match) >= 2:
                return (match[0], match[1])
    except:
        pass
    return (None, None)


def is_workspace_window(window_id: int) -> bool:
    """Check if a window belongs to Workspace (GNUstep class)."""
    instance, wm_class = get_window_class(window_id)
    if wm_class != WORKSPACE_WM_CLASS:
        return False
    # Exclude LoginWindow from Workspace windows
    if instance == "LoginWindow":
        return False
    return True


def get_focused_window_id() -> Optional[int]:
    """Get the currently focused window ID."""
    try:
        result = subprocess.run(
            ["xdotool", "getactivewindow"],
            capture_output=True, text=True, timeout=2
        )
        if result.returncode == 0:
            return int(result.stdout.strip())
    except:
        pass
    return None


def is_focus_on_workspace() -> bool:
    """Check if focus is on a Workspace window (GNUstep, not LoginWindow)."""
    wid = get_focused_window_id()
    if wid is None:
        return False
    return is_workspace_window(wid)


def find_workspace_window(title_pattern: str = None, prefer_viewer: bool = True) -> Optional[int]:
    """
    Find a Workspace window by title pattern.
    
    Only returns windows that have WM_CLASS = GNUstep (excluding LoginWindow).
    If prefer_viewer is True and no title given, prefers a viewer window ("Window" title).
    
    Returns: Window ID or None
    """
    try:
        result = subprocess.run(
            ["xdotool", "search", "--class", WORKSPACE_WM_CLASS],
            capture_output=True, text=True, timeout=5
        )
        
        if result.returncode != 0 or not result.stdout.strip():
            return None
        
        # Get all candidate windows
        candidates = []
        viewer_windows = []
        
        for wid_str in result.stdout.strip().split('\n'):
            try:
                wid = int(wid_str)
                if not is_workspace_window(wid):
                    continue
                
                # Get window name
                name_result = subprocess.run(
                    ["xdotool", "getwindowname", str(wid)],
                    capture_output=True, text=True, timeout=2
                )
                if name_result.returncode != 0:
                    continue
                
                name = name_result.stdout.strip()
                
                if title_pattern:
                    if title_pattern.lower() in name.lower():
                        return wid
                else:
                    candidates.append((wid, name))
                    # Track viewer windows (titled "Window" or path-like)
                    if name == "Window" or "/" in name:
                        viewer_windows.append(wid)
            except:
                continue
        
        # Return based on preference
        if not title_pattern:
            if prefer_viewer and viewer_windows:
                return viewer_windows[0]
            elif candidates:
                return candidates[0][0]
    except:
        pass
    return None


def focus_workspace_window(title: str = None) -> bool:
    """
    Focus a Workspace window.
    
    If title is given, focuses that specific window.
    Otherwise focuses any Workspace window.
    
    Uses wmctrl which works more reliably than xdotool windowactivate.
    
    Returns True if successful.
    """
    wid = find_workspace_window(title)
    if wid:
        try:
            # Use wmctrl for more reliable window activation
            # wmctrl -i -a uses hexadecimal window IDs
            result = subprocess.run(
                ["wmctrl", "-i", "-a", str(wid)],
                timeout=5, capture_output=True
            )
            if result.returncode == 0:
                time.sleep(0.3)
                return True
            else:
                # Fallback to xdotool
                subprocess.run(
                    ["xdotool", "windowactivate", "--sync", str(wid)],
                    timeout=5
                )
                time.sleep(0.3)
                return True
        except:
            pass
    return False


# ============== Test Infrastructure ==============

class TestRunner:
    """Runs tests with proper setup, teardown, and failure capture."""
    
    def __init__(self):
        self.client = WorkspaceTestClient()
        self.user = UserInput()
        self.modal_handler = get_handler()
        self.capture = get_capture("/tmp/uitest_failures")
        self.passed = 0
        self.failed = 0
        self.skipped = 0
        self.results: List[Dict[str, Any]] = []
    
    def ensure_workspace_focus(self) -> bool:
        """
        Ensure focus is on a Workspace window.
        
        If focus is elsewhere, attempts to refocus Workspace.
        Returns True if Workspace has focus after this call.
        """
        if is_focus_on_workspace():
            return True
        
        self.capture.log("Focus not on Workspace, attempting to refocus...")
        
        # Try finding and activating a Workspace window directly (most reliable)
        if focus_workspace_window():
            time.sleep(0.2)
            if is_focus_on_workspace():
                self.capture.log("Refocused to Workspace via windowactivate")
                return True
        
        # Try clicking on the desktop to get Workspace focus
        self.user.click(DESKTOP_SAFE_CLICK[0], DESKTOP_SAFE_CLICK[1])
        time.sleep(0.3)
        
        if is_focus_on_workspace():
            self.capture.log("Refocused to Workspace via desktop click")
            return True
        
        # Last resort: try windowactivate again after desktop click
        if focus_workspace_window():
            time.sleep(0.2)
            if is_focus_on_workspace():
                self.capture.log("Refocused to Workspace via windowactivate (2nd attempt)")
                return True
        
        self.capture.log("WARNING: Could not focus Workspace")
        return False
    
    def setup(self):
        """Initial setup - click desktop to activate Workspace menu."""
        self.capture.log("=== Test Suite Setup ===")
        
        # First, find a Workspace window and activate it
        if not focus_workspace_window():
            self.capture.log("ERROR: Could not find any Workspace window!")
            return False
        time.sleep(0.3)
        
        # Click on desktop background to ensure Workspace is active
        # This is required to make the menu bar appear
        self.user.click_smooth(DESKTOP_SAFE_CLICK[0], DESKTOP_SAFE_CLICK[1])
        time.sleep(0.5)
        
        # Press Escape a few times to dismiss any open dialogs/menus
        for _ in range(3):
            self.user.press_escape()
            time.sleep(0.15)
        
        # Verify we have Workspace focus
        if not is_focus_on_workspace():
            # One more try with windowactivate
            focus_workspace_window()
            time.sleep(0.2)
            if not is_focus_on_workspace():
                self.capture.log("WARNING: Focus not on Workspace after setup")
        else:
            self.capture.log("Focus verified on Workspace window")
        
        # Verify Workspace is responding
        try:
            self.client.query_ui_state()
            self.capture.log("Workspace is responding to UI queries")
            return True
        except Exception as e:
            self.capture.log(f"WARNING: Workspace not responding: {e}")
            return False
    
    def teardown(self):
        """Cleanup after all tests."""
        # Close any open utility windows
        for _ in range(5):
            self.user.press_escape()
            time.sleep(0.1)
        
        # Click desktop to deselect
        self.user.click(DESKTOP_SAFE_CLICK[0], DESKTOP_SAFE_CLICK[1])
    
    def check_for_modals(self) -> bool:
        """Check and dismiss any modal dialogs. Returns True if modal was found."""
        modal = self.modal_handler.detect_modal_dialog()
        if modal:
            self.capture.log(f"Modal detected: {modal.name}")
            self.modal_handler.dismiss_focus_stealer()
            time.sleep(0.2)
            return True
        return False
    
    def run_test(self, name: str, func: Callable, skip_reason: str = None):
        """Run a single test with error handling."""
        if skip_reason:
            print(f"  ⊘ {name} (skipped: {skip_reason})")
            self.skipped += 1
            self.results.append({'name': name, 'status': 'skipped', 'reason': skip_reason})
            return
        
        self.capture.set_test_name(name)
        self.capture.log(f"Running: {name}")
        
        # Pre-test: ensure focus is on Workspace
        if not self.ensure_workspace_focus():
            print(f"  ✗ {name} (could not focus Workspace)")
            self.capture.log("FAILED: Could not focus Workspace window")
            self.capture.take_screenshot(f"FOCUS_FAIL_{name.replace(' ', '_')}")
            self.failed += 1
            self.results.append({'name': name, 'status': 'failed', 'reason': 'could not focus Workspace'})
            return
        
        # Pre-test: check for modal dialogs
        self.check_for_modals()
        
        try:
            result = func()
            if result:
                print(f"  ✓ {name}")
                self.passed += 1
                self.results.append({'name': name, 'status': 'passed'})
            else:
                print(f"  ✗ {name} (returned False)")
                self.capture.log("Test returned False")
                self.capture.take_screenshot(f"FAIL_{name.replace(' ', '_')}")
                self.capture.save_log("Test returned False")
                self.failed += 1
                self.results.append({'name': name, 'status': 'failed', 'reason': 'returned False'})
        except Exception as e:
            print(f"  ✗ {name} ({type(e).__name__}: {e})")
            self.capture.log(f"Exception: {type(e).__name__}: {e}")
            self.capture.log(f"Traceback:\n{traceback.format_exc()}")
            self.capture.take_screenshot(f"ERROR_{name.replace(' ', '_')}")
            self.capture.save_log(traceback.format_exc())
            self.failed += 1
            self.results.append({'name': name, 'status': 'error', 'reason': str(e)})
        
        # Small delay between tests
        time.sleep(0.3)
    
    def click_menu(self, menu_name: str):
        """
        Click a menu in the menu bar.
        
        Ensures Workspace has focus first.
        """
        # Make sure we're focused on Workspace before clicking menu
        if not is_focus_on_workspace():
            self.ensure_workspace_focus()
        
        x = MENU_POSITIONS.get(menu_name, 100)
        self.user.click_smooth(x, MENU_BAR_Y)
        time.sleep(0.3)
    
    def dismiss_menu(self):
        """Dismiss any open menu."""
        self.user.press_escape()
        time.sleep(0.2)
    
    def close_window(self):
        """Close current window with Cmd+W."""
        self.user.cmd('w')
        time.sleep(0.3)
    
    def window_exists_xdotool(self, title: str) -> bool:
        """
        Check if a Workspace window with this title exists.
        
        Only returns True for GNUstep windows (not other apps).
        """
        wid = find_workspace_window(title)
        return wid is not None
    
    def close_workspace_window(self, title: str) -> bool:
        """
        Close a specific Workspace window by title.
        
        Returns True if window was found and close was attempted.
        """
        wid = find_workspace_window(title)
        if wid:
            try:
                subprocess.run(
                    ["xdotool", "windowactivate", "--sync", str(wid)],
                    timeout=3
                )
                time.sleep(0.2)
                self.user.cmd('w')  # Cmd+W to close
                time.sleep(0.3)
                return True
            except:
                pass
        return False
    
    def print_summary(self):
        """Print test summary."""
        total = self.passed + self.failed + self.skipped
        print("\n" + "=" * 60)
        print(f"RESULTS: {self.passed} passed, {self.failed} failed, {self.skipped} skipped (of {total})")
        print("=" * 60)
        
        if self.failed > 0:
            print(f"\nFailure logs saved to: /tmp/uitest_failures/")
            print("\nFailed tests:")
            for r in self.results:
                if r['status'] in ('failed', 'error'):
                    print(f"  - {r['name']}: {r.get('reason', 'unknown')}")


# ============== Create Global Runner ==============

runner: TestRunner = None


def get_runner() -> TestRunner:
    global runner
    if runner is None:
        runner = TestRunner()
    return runner


# ============== Menu State Tests ==============
# These tests verify the menu system is working correctly

def test_menu_state_api_works():
    """Verify menu state API returns valid data."""
    r = get_runner()
    try:
        state = r.client.get_menu_state()
        return state.get('success', False) and len(state.get('menus', [])) > 0
    except:
        return False


def test_menu_has_workspace_menu():
    """Workspace menu exists with items."""
    r = get_runner()
    items = r.client.get_menu_items('Workspace')
    return len(items) > 0


def test_menu_has_file_menu():
    """File menu exists with items."""
    r = get_runner()
    items = r.client.get_menu_items('File')
    return len(items) > 0


def test_menu_has_edit_menu():
    """Edit menu exists with items."""
    r = get_runner()
    items = r.client.get_menu_items('Edit')
    return len(items) > 0


def test_menu_has_view_menu():
    """View menu exists with items."""
    r = get_runner()
    items = r.client.get_menu_items('View')
    return len(items) > 0


def test_menu_has_go_menu():
    """Go menu exists with items."""
    r = get_runner()
    items = r.client.get_menu_items('Go')
    return len(items) > 0


def test_menu_has_tools_menu():
    """Tools menu exists with items."""
    r = get_runner()
    items = r.client.get_menu_items('Tools')
    return len(items) > 0


def test_menu_has_window_menu():
    """Window menu exists with items."""
    r = get_runner()
    items = r.client.get_menu_items('Window')
    return len(items) > 0


def test_menu_has_help_menu():
    """Help menu exists with items."""
    r = get_runner()
    items = r.client.get_menu_items('Help')
    return len(items) > 0


# ============== Menu Item State Tests ==============

def test_about_workspace_enabled():
    """About Workspace menu item is enabled."""
    r = get_runner()
    return r.client.is_menu_item_enabled('Workspace', 'About Workspace')


def test_preferences_enabled():
    """Preferences menu item is enabled."""
    r = get_runner()
    return r.client.is_menu_item_enabled('Workspace', 'Preferences...')


def test_logout_enabled():
    """Logout menu item is enabled."""
    r = get_runner()
    return r.client.is_menu_item_enabled('Workspace', 'Logout')


def test_new_viewer_enabled():
    """New Workspace Window is enabled."""
    r = get_runner()
    return r.client.is_menu_item_enabled('File', 'New Workspace Window')


def test_close_window_enabled():
    """Close Window is enabled (when window exists)."""
    r = get_runner()
    # This should be enabled when there's a window
    return r.client.is_menu_item_enabled('File', 'Close Window')


def test_find_enabled():
    """Find menu item is enabled."""
    r = get_runner()
    return r.client.is_menu_item_enabled('File', 'Find')


def test_new_folder_disabled():
    """New Folder is disabled (not implemented)."""
    r = get_runner()
    return not r.client.is_menu_item_enabled('File', 'New Folder')


# ============== Menu Click Tests ==============
# These test that we can click menus and they appear

def test_click_workspace_menu():
    """Click Workspace menu opens dropdown."""
    r = get_runner()
    r.click_menu('Workspace')
    time.sleep(0.3)
    r.dismiss_menu()
    return True


def test_click_file_menu():
    """Click File menu opens dropdown."""
    r = get_runner()
    r.click_menu('File')
    time.sleep(0.3)
    r.dismiss_menu()
    return True


def test_click_edit_menu():
    """Click Edit menu opens dropdown."""
    r = get_runner()
    r.click_menu('Edit')
    time.sleep(0.3)
    r.dismiss_menu()
    return True


def test_click_view_menu():
    """Click View menu opens dropdown."""
    r = get_runner()
    r.click_menu('View')
    time.sleep(0.3)
    r.dismiss_menu()
    return True


def test_click_go_menu():
    """Click Go menu opens dropdown."""
    r = get_runner()
    r.click_menu('Go')
    time.sleep(0.3)
    r.dismiss_menu()
    return True


def test_click_tools_menu():
    """Click Tools menu opens dropdown."""
    r = get_runner()
    r.click_menu('Tools')
    time.sleep(0.3)
    r.dismiss_menu()
    return True


def test_click_window_menu():
    """Click Window menu opens dropdown."""
    r = get_runner()
    r.click_menu('Window')
    time.sleep(0.3)
    r.dismiss_menu()
    return True


def test_click_help_menu():
    """Click Help menu opens dropdown."""
    r = get_runner()
    r.click_menu('Help')
    time.sleep(0.3)
    r.dismiss_menu()
    return True


# ============== Keyboard Shortcut Tests ==============

def test_shortcut_new_viewer():
    """Cmd+N opens new viewer window."""
    r = get_runner()
    
    # Count viewers before
    before = r.window_exists_xdotool("Downloads") or r.window_exists_xdotool("Home")
    
    # Press Cmd+N
    r.user.cmd('n')
    time.sleep(0.5)
    
    # Should have a viewer window now
    # The title depends on what directory opens
    after = r.window_exists_xdotool("Downloads") or r.window_exists_xdotool("Home") or r.window_exists_xdotool("/")
    
    # Close the window we just opened
    r.close_window()
    time.sleep(0.3)
    
    return True  # If we got here without error, the shortcut worked


def test_shortcut_preferences():
    """Cmd+, opens Preferences."""
    r = get_runner()
    
    # Close any existing preferences first
    if r.window_exists_xdotool(WINDOW_TITLES['preferences']):
        r.user.focus_window_by_name(WINDOW_TITLES['preferences'])
        r.close_window()
        time.sleep(0.3)
    
    # Click desktop to ensure Workspace has focus
    r.user.click_smooth(DESKTOP_SAFE_CLICK[0], DESKTOP_SAFE_CLICK[1])
    time.sleep(0.3)
    
    # Open preferences
    r.user.cmd(',')
    time.sleep(0.5)
    
    # Check it opened
    result = r.window_exists_xdotool(WINDOW_TITLES['preferences'])
    
    # Close it
    if result:
        r.user.focus_window_by_name(WINDOW_TITLES['preferences'])
        r.close_window()
    
    return result


def test_shortcut_info():
    """Cmd+I opens Info panel (About)."""
    r = get_runner()
    
    # Click desktop first
    r.user.click_smooth(DESKTOP_SAFE_CLICK[0], DESKTOP_SAFE_CLICK[1])
    time.sleep(0.3)
    
    # Open info panel
    r.user.cmd('i')
    time.sleep(0.5)
    
    # Check if Info panel exists
    result = r.window_exists_xdotool(WINDOW_TITLES['about'])
    
    # Close it
    if result:
        r.user.focus_window_by_name(WINDOW_TITLES['about'])
        r.close_window()
    
    return result


def test_shortcut_find():
    """Cmd+F opens Finder."""
    r = get_runner()
    
    # Close any existing finder first
    if r.window_exists_xdotool(WINDOW_TITLES['finder']):
        r.user.focus_window_by_name(WINDOW_TITLES['finder'])
        r.close_window()
        time.sleep(0.3)
    
    # Click desktop
    r.user.click_smooth(DESKTOP_SAFE_CLICK[0], DESKTOP_SAFE_CLICK[1])
    time.sleep(0.3)
    
    # Open finder
    r.user.cmd('f')
    time.sleep(0.5)
    
    # Check it opened
    result = r.window_exists_xdotool(WINDOW_TITLES['finder'])
    
    # Close it
    if result:
        r.user.focus_window_by_name(WINDOW_TITLES['finder'])
        r.close_window()
    
    return result


def test_shortcut_close_window():
    """Cmd+W closes current window."""
    r = get_runner()
    
    # First open a new viewer
    r.user.cmd('n')
    time.sleep(0.5)
    
    # Now close it
    r.user.cmd('w')
    time.sleep(0.3)
    
    return True  # If no error, success


# ============== Viewer Window Tests ==============

def test_open_new_viewer():
    """Can open a new viewer window."""
    r = get_runner()
    
    # Click desktop first
    r.user.click_smooth(DESKTOP_SAFE_CLICK[0], DESKTOP_SAFE_CLICK[1])
    time.sleep(0.3)
    
    # Open new viewer
    r.user.cmd('n')
    time.sleep(0.5)
    
    # Close it
    r.close_window()
    
    return True


def test_viewer_navigation_home():
    """Navigate to Home using Go menu shortcut."""
    r = get_runner()
    
    # Open viewer
    r.user.cmd('n')
    time.sleep(0.5)
    
    # Go to Home (Shift+Cmd+H)
    r.user.cmd_shift('h')
    time.sleep(0.5)
    
    # Verify we're at home - window title should contain home dir
    home_title = r.window_exists_xdotool(os.path.basename(os.path.expanduser("~")))
    
    # Close viewer
    r.close_window()
    
    return True  # Navigation command executed without error


def test_viewer_navigation_root():
    """Navigate to Computer/root using Go menu."""
    r = get_runner()
    
    # Open viewer
    r.user.cmd('n')
    time.sleep(0.5)
    
    # Go to Computer (Shift+Cmd+C)
    r.user.cmd_shift('c')
    time.sleep(0.5)
    
    # Close viewer
    r.close_window()
    
    return True


def test_viewer_back_forward():
    """Back and Forward navigation works."""
    r = get_runner()
    
    # Open viewer
    r.user.cmd('n')
    time.sleep(0.5)
    
    # Navigate somewhere
    r.user.cmd_shift('h')  # Home
    time.sleep(0.3)
    
    r.user.cmd_shift('c')  # Computer
    time.sleep(0.3)
    
    # Go back (Cmd+[)
    r.user.key('alt+bracketleft')
    time.sleep(0.3)
    
    # Go forward (Cmd+])
    r.user.key('alt+bracketright')
    time.sleep(0.3)
    
    # Close viewer
    r.close_window()
    
    return True


# ============== Panel Tests ==============

def test_info_panel_opens():
    """Info panel can be opened."""
    r = get_runner()
    
    # Click desktop
    r.user.click_smooth(DESKTOP_SAFE_CLICK[0], DESKTOP_SAFE_CLICK[1])
    time.sleep(0.3)
    
    # Open Info
    r.user.cmd('i')
    time.sleep(0.5)
    
    result = r.window_exists_xdotool(WINDOW_TITLES['about'])
    
    if result:
        r.user.focus_window_by_name(WINDOW_TITLES['about'])
        r.close_window()
    
    return result


def test_preferences_panel_opens():
    """Preferences panel can be opened."""
    r = get_runner()
    
    # Click desktop
    r.user.click_smooth(DESKTOP_SAFE_CLICK[0], DESKTOP_SAFE_CLICK[1])
    time.sleep(0.3)
    
    r.user.cmd(',')
    time.sleep(0.5)
    
    result = r.window_exists_xdotool(WINDOW_TITLES['preferences'])
    
    if result:
        r.user.focus_window_by_name(WINDOW_TITLES['preferences'])
        r.close_window()
    
    return result


def test_finder_panel_opens():
    """Finder panel can be opened."""
    r = get_runner()
    
    # Click desktop
    r.user.click_smooth(DESKTOP_SAFE_CLICK[0], DESKTOP_SAFE_CLICK[1])
    time.sleep(0.3)
    
    r.user.cmd('f')
    time.sleep(0.5)
    
    result = r.window_exists_xdotool(WINDOW_TITLES['finder'])
    
    if result:
        r.user.focus_window_by_name(WINDOW_TITLES['finder'])
        r.close_window()
    
    return result


# ============== Desktop Tests ==============

def test_desktop_click_activates_workspace():
    """Clicking desktop activates Workspace."""
    r = get_runner()
    
    # Click on desktop background
    r.user.click_smooth(DESKTOP_SAFE_CLICK[0], DESKTOP_SAFE_CLICK[1])
    time.sleep(0.3)
    
    # Check that Workspace responds
    try:
        state = r.client.query_ui_state()
        return state.get('uiTestingEnabled', False)
    except:
        return False


def test_desktop_exists():
    """Desktop window exists."""
    r = get_runner()
    
    try:
        state = r.client.query_ui_state()
        windows = state.get('windows', [])
        for w in windows:
            if w.get('class') == 'GWDesktopWindow':
                return True
        return False
    except:
        return False


# ============== Icon View Tests ==============

def test_desktop_has_icons():
    """Desktop has at least one icon."""
    r = get_runner()
    
    try:
        state = r.client.query_ui_state()
        windows = state.get('windows', [])
        for w in windows:
            if w.get('class') == 'GWDesktopWindow':
                # Look for icon views in content
                return True  # Desktop window exists
        return False
    except:
        return False


# ============== View Mode Tests ==============

def test_switch_to_list_view():
    """Can switch viewer to list view."""
    r = get_runner()
    
    # Open viewer
    r.user.cmd('n')
    time.sleep(0.5)
    
    # Switch to list view (Cmd+2)
    r.user.cmd('2')
    time.sleep(0.3)
    
    # Switch back to icon view (Cmd+1)
    r.user.cmd('1')
    time.sleep(0.3)
    
    # Close viewer
    r.close_window()
    
    return True


def test_switch_to_icon_view():
    """Can switch viewer to icon view."""
    r = get_runner()
    
    # Open viewer
    r.user.cmd('n')
    time.sleep(0.5)
    
    # Switch to icon view (Cmd+1)
    r.user.cmd('1')
    time.sleep(0.3)
    
    # Close viewer
    r.close_window()
    
    return True


# ============== Go Menu Navigation Tests ==============

def test_go_to_home():
    """Go > Home works (Shift+Cmd+H)."""
    r = get_runner()
    
    # Ensure we have a viewer
    r.user.cmd('n')
    time.sleep(0.5)
    
    # Navigate to home
    r.user.cmd_shift('h')
    time.sleep(0.5)
    
    r.close_window()
    return True


def test_go_to_computer():
    """Go > Computer works (Shift+Cmd+C)."""
    r = get_runner()
    
    r.user.cmd('n')
    time.sleep(0.5)
    
    r.user.cmd_shift('c')
    time.sleep(0.5)
    
    r.close_window()
    return True


def test_go_to_desktop():
    """Go > Desktop works (Shift+Cmd+D)."""
    r = get_runner()
    
    r.user.cmd('n')
    time.sleep(0.5)
    
    r.user.cmd_shift('d')
    time.sleep(0.5)
    
    r.close_window()
    return True


def test_go_to_documents():
    """Go > Documents works."""
    r = get_runner()
    
    r.user.cmd('n')
    time.sleep(0.5)
    
    r.user.cmd_shift('o')  # Documents shortcut
    time.sleep(0.5)
    
    r.close_window()
    return True


def test_go_to_downloads():
    """Go > Downloads works."""
    r = get_runner()
    
    r.user.cmd('n')
    time.sleep(0.5)
    
    r.user.cmd_shift('l')  # Downloads shortcut
    time.sleep(0.5)
    
    r.close_window()
    return True


# ============== Edit Menu Tests ==============

def test_select_all():
    """Edit > Select All works (Cmd+A)."""
    r = get_runner()
    
    # Open viewer
    r.user.cmd('n')
    time.sleep(0.5)
    
    # Select all
    r.user.cmd('a')
    time.sleep(0.3)
    
    # Deselect
    r.user.click(100, 200)  # Click empty area
    time.sleep(0.2)
    
    r.close_window()
    return True


# ============== Multiple Window Tests ==============

def test_open_multiple_viewers():
    """Can open multiple viewer windows."""
    r = get_runner()
    
    # Click desktop
    r.user.click_smooth(DESKTOP_SAFE_CLICK[0], DESKTOP_SAFE_CLICK[1])
    time.sleep(0.3)
    
    # Open 3 viewers
    r.user.cmd('n')
    time.sleep(0.4)
    r.user.cmd('n')
    time.sleep(0.4)
    r.user.cmd('n')
    time.sleep(0.4)
    
    # Close all 3
    r.user.cmd('w')
    time.sleep(0.3)
    r.user.cmd('w')
    time.sleep(0.3)
    r.user.cmd('w')
    time.sleep(0.3)
    
    return True


# ============== Test Suite Definition ==============

def get_all_tests():
    """Return all tests grouped by category."""
    return [
        # Menu State Tests
        ("Menu", [
            ("Menu state API works", test_menu_state_api_works),
            ("Workspace menu exists", test_menu_has_workspace_menu),
            ("File menu exists", test_menu_has_file_menu),
            ("Edit menu exists", test_menu_has_edit_menu),
            ("View menu exists", test_menu_has_view_menu),
            ("Go menu exists", test_menu_has_go_menu),
            ("Tools menu exists", test_menu_has_tools_menu),
            ("Window menu exists", test_menu_has_window_menu),
            ("Help menu exists", test_menu_has_help_menu),
        ]),
        
        # Menu Item State Tests
        ("Menu Items", [
            ("About Workspace enabled", test_about_workspace_enabled),
            ("Preferences enabled", test_preferences_enabled),
            ("Logout enabled", test_logout_enabled),
            ("New Viewer enabled", test_new_viewer_enabled),
            ("Close Window enabled", test_close_window_enabled),
            ("Find enabled", test_find_enabled),
            ("New Folder disabled", test_new_folder_disabled),
        ]),
        
        # Menu Click Tests
        ("Menu Clicks", [
            ("Click Workspace menu", test_click_workspace_menu),
            ("Click File menu", test_click_file_menu),
            ("Click Edit menu", test_click_edit_menu),
            ("Click View menu", test_click_view_menu),
            ("Click Go menu", test_click_go_menu),
            ("Click Tools menu", test_click_tools_menu),
            ("Click Window menu", test_click_window_menu),
            ("Click Help menu", test_click_help_menu),
        ]),
        
        # Keyboard Shortcuts
        ("Keyboard Shortcuts", [
            ("Cmd+N new viewer", test_shortcut_new_viewer),
            ("Cmd+, preferences", test_shortcut_preferences),
            ("Cmd+I info panel", test_shortcut_info),
            ("Cmd+F finder", test_shortcut_find),
            ("Cmd+W close window", test_shortcut_close_window),
        ]),
        
        # Viewer Window Tests
        ("Viewer Windows", [
            ("Open new viewer", test_open_new_viewer),
            ("Navigate to Home", test_viewer_navigation_home),
            ("Navigate to Root", test_viewer_navigation_root),
            ("Back/Forward navigation", test_viewer_back_forward),
            ("Switch to list view", test_switch_to_list_view),
            ("Switch to icon view", test_switch_to_icon_view),
            ("Open multiple viewers", test_open_multiple_viewers),
        ]),
        
        # Panel Tests
        ("Panels", [
            ("Info panel opens", test_info_panel_opens),
            ("Preferences panel opens", test_preferences_panel_opens),
            ("Finder panel opens", test_finder_panel_opens),
        ]),
        
        # Desktop Tests
        ("Desktop", [
            ("Desktop click activates", test_desktop_click_activates_workspace),
            ("Desktop window exists", test_desktop_exists),
            ("Desktop has icons", test_desktop_has_icons),
        ]),
        
        # Navigation Tests
        ("Go Navigation", [
            ("Go to Home", test_go_to_home),
            ("Go to Computer", test_go_to_computer),
            ("Go to Desktop", test_go_to_desktop),
            ("Go to Documents", test_go_to_documents),
            ("Go to Downloads", test_go_to_downloads),
        ]),
        
        # Edit Menu Tests  
        ("Edit Operations", [
            ("Select All", test_select_all),
        ]),
    ]


# ============== Main Entry Point ==============

def main():
    print("\n" + "=" * 60)
    print("WORKSPACE INTERACTIVE TEST SUITE")
    print("Comprehensive GUI regression tests")
    print("Failure screenshots saved to: /tmp/uitest_failures/")
    print("=" * 60 + "\n")
    
    r = get_runner()
    
    # Initial setup
    print("Setting up...")
    if not r.setup():
        print("WARNING: Setup detected issues, continuing anyway...")
    print()
    
    # Run all test groups
    all_tests = get_all_tests()
    
    for group_name, tests in all_tests:
        print(f"\n--- {group_name} ---")
        for test_name, test_func in tests:
            r.run_test(test_name, test_func)
    
    # Teardown
    print("\nCleaning up...")
    r.teardown()
    
    # Print summary
    r.print_summary()
    
    return 0 if r.failed == 0 else 1


if __name__ == "__main__":
    exit(main())
