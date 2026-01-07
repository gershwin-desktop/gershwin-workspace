#!/usr/bin/env python3
"""
uitest.py - Workspace GUI Testing Library for Python

This library provides a client interface to the Workspace GUI testing framework
via the uitest command-line tool. It allows you to write automated tests for
the Workspace file manager's user interface.

Example:
    from uitest import WorkspaceTestClient
    
    client = WorkspaceTestClient()
    client.open_about_dialog()
    assert client.window_exists("About Workspace")
    assert client.text_visible("Version")
"""

import subprocess
import json
import sys
import os
from typing import Dict, List, Optional, Tuple, Any


class UITestException(Exception):
    """Base exception for UI testing errors."""
    pass


class WorkspaceNotRunningError(UITestException):
    """Raised when Workspace is not running or not responding."""
    pass


class CommandFailedError(UITestException):
    """Raised when a uitest command fails."""
    pass


class AssertionFailedError(UITestException):
    """Raised when an assertion fails."""
    pass


class WorkspaceTestClient:
    """
    Client for testing Workspace GUI via the uitest command-line tool.
    
    Requires:
    - Workspace running with debug flag (-d or --debug)
    - uitest command-line tool available in PATH
    
    Usage:
        client = WorkspaceTestClient()
        client.open_about_dialog()
        assert client.window_exists("About Workspace")
    """
    
    def __init__(self, uitest_path: Optional[str] = None):
        """
        Initialize the test client.
        
        Args:
            uitest_path: Path to uitest executable. If None, searches PATH.
        """
        self.uitest_path = uitest_path or self._find_uitest()
        self._verify_uitest()
        self._last_json_response = None
        
    def _find_uitest(self) -> str:
        """Find uitest executable in PATH."""
        import os.path
        
        # First, try to find it relative to this script's location
        script_dir = os.path.dirname(os.path.abspath(__file__))  # .../python
        python_parent = os.path.dirname(script_dir)  # .../uitest
        relative_path = os.path.join(python_parent, 'obj', 'uitest')
        
        if os.path.isfile(relative_path) and os.access(relative_path, os.X_OK):
            return relative_path
        
        # Try other common locations
        candidates = [
            "uitest",
            "/usr/bin/uitest",
            "/usr/local/bin/uitest",
            "Tools/uitest/obj/uitest",
            "./uitest/obj/uitest",
        ]
        
        for candidate in candidates:
            abs_path = os.path.abspath(candidate)
            if os.path.isfile(abs_path) and os.access(abs_path, os.X_OK):
                return abs_path
            # Also try via which for PATH-based executables
            if not candidate.startswith('.') and not candidate.startswith('/'):
                result = subprocess.run(
                    f"which {candidate}",
                    shell=True,
                    capture_output=True,
                    text=True
                )
                if result.returncode == 0:
                    return result.stdout.strip()
                
        raise UITestException(
            "Cannot find uitest executable. "
            "Make sure it's in PATH or provide explicit path."
        )
    
    def _command_exists(self, cmd: str) -> bool:
        """Check if a command exists."""
        result = subprocess.run(
            f"which {cmd} 2>/dev/null || test -f {cmd}",
            shell=True,
            capture_output=True
        )
        return result.returncode == 0
    
    def _verify_uitest(self):
        """Verify uitest is available and functional."""
        try:
            result = subprocess.run(
                [self.uitest_path, "help"],
                capture_output=True,
                timeout=5
            )
            if result.returncode != 0:
                raise CommandFailedError("uitest help command failed")
        except FileNotFoundError:
            raise UITestException(f"uitest not found at {self.uitest_path}")
    
    def _run_command(self, *args: str) -> Tuple[str, str, int]:
        """
        Run a uitest command.
        
        Returns:
            Tuple of (stdout, stderr, returncode)
            
        Raises:
            WorkspaceNotRunningError: If Workspace is not responding
            CommandFailedError: If command execution fails
        """
        cmd = [self.uitest_path] + list(args)
        
        try:
            result = subprocess.run(
                cmd,
                capture_output=True,
                text=True,
                timeout=10
            )
            
            # Check for Workspace not running
            if "Cannot contact Workspace" in result.stderr:
                raise WorkspaceNotRunningError(
                    "Workspace is not running or not responding. "
                    "Start Workspace with: Workspace -d"
                )
            
            return result.stdout, result.stderr, result.returncode
            
        except subprocess.TimeoutExpired:
            raise CommandFailedError("uitest command timed out")
        except Exception as e:
            raise CommandFailedError(f"Failed to run uitest: {e}")
    
    def _extract_json(self, output: str) -> Dict[str, Any]:
        """Extract JSON from command output."""
        lines = output.split('\n')
        json_start = None
        
        # Find where JSON starts
        for i, line in enumerate(lines):
            if line.strip().startswith('{'):
                json_start = i
                break
        
        if json_start is None:
            raise UITestException(f"No JSON found in output: {output[:200]}")
        
        json_text = '\n'.join(lines[json_start:])
        
        try:
            data = json.loads(json_text)
            self._last_json_response = data
            return data
        except json.JSONDecodeError as e:
            raise UITestException(f"Failed to parse JSON response: {e}")
    
    # Public API Methods
    
    def open_about_dialog(self) -> None:
        """Open the Workspace About dialog."""
        stdout, stderr, code = self._run_command("about")
        
        if code != 0:
            raise CommandFailedError(f"Failed to open About dialog: {stderr}")
        
        # Extract and store the JSON response for later queries
        self._extract_json(stdout)
    
    def query_ui_state(self) -> Dict[str, Any]:
        """
        Get the complete UI state as JSON.
        
        Returns:
            Dictionary with UI hierarchy and window information
        """
        stdout, stderr, code = self._run_command("query", "--json")
        
        if code != 0:
            raise CommandFailedError(f"Failed to query UI state: {stderr}")
        
        return self._extract_json(stdout)
    
    def get_ui_at_coordinate(self, x: float, y: float) -> str:
        """
        Get human-readable tree of UI elements at screen coordinate.
        
        Args:
            x: X coordinate (screen pixels)
            y: Y coordinate (screen pixels)
            
        Returns:
            Human-readable text tree of UI elements at that location
        """
        stdout, stderr, code = self._run_command("at-coordinate", str(x), str(y))
        
        if code != 0:
            if "No UI elements found" in stdout:
                return ""
            raise CommandFailedError(f"Failed to query coordinate: {stderr}")
        
        return stdout
    
    def run_script(self, script_path: str) -> int:
        """
        Run a Python test script.
        
        Args:
            script_path: Path to Python test script
            
        Returns:
            Exit code from the script
            
        Raises:
            CommandFailedError: If script execution fails
        """
        # Expand path
        script_path = os.path.expanduser(script_path)
        
        if not os.path.exists(script_path):
            raise UITestException(f"Script not found: {script_path}")
        
        stdout, stderr, code = self._run_command("run-script", script_path)
        
        if stdout:
            print(stdout, end='')
        if stderr:
            print(stderr, file=sys.stderr, end='')
        
        return code
    
    # UI Interaction Methods
    
    def click(self, x: float, y: float) -> Dict[str, Any]:
        """
        Click at screen coordinates.
        
        Args:
            x: X coordinate in screen pixels
            y: Y coordinate in screen pixels
            
        Returns:
            Dictionary with result: {"success": true/false, "element": "NSButton", ...}
        """
        stdout, stderr, code = self._run_command("click", str(x), str(y))
        return self._extract_json(stdout)
    
    def menu(self, menu_path: str) -> Dict[str, Any]:
        """
        Open and click a menu item by path.
        
        Args:
            menu_path: Menu item path like "Info > About" or "File > New Browser"
            
        Returns:
            Dictionary with result: {"success": true/false, "menuItem": "About", ...}
            
        Example:
            client.menu("Info > About")
            client.menu("File > New Browser")
        """
        stdout, stderr, code = self._run_command("menu", menu_path)
        return self._extract_json(stdout)
    
    def shortcut(self, keys: str) -> Dict[str, Any]:
        """
        Send a keyboard shortcut.
        
        Args:
            keys: Shortcut string like "Cmd+i", "Cmd+Shift+n", "Cmd+w"
            
        Returns:
            Dictionary with result: {"success": true/false, "shortcut": "Cmd+i", ...}
            
        Example:
            client.shortcut("Cmd+i")  # Info/About
            client.shortcut("Cmd+Shift+n")  # New something
        """
        stdout, stderr, code = self._run_command("shortcut", keys)
        return self._extract_json(stdout)
    
    def highlight_failure(self, window_title: str, element_text: str, 
                          duration: float = 0) -> Dict[str, Any]:
        """
        Highlight a UI element with a red overlay to indicate failure.
        
        Args:
            window_title: Title of the window containing the element
            element_text: Text content of the element to highlight
            duration: How long to show the highlight (seconds), 0 = permanent
            
        Returns:
            Dictionary with result: {"success": true/false, "highlighted": "element text"}
        """
        stdout, stderr, code = self._run_command(
            "highlight", window_title, element_text, str(duration)
        )
        return self._extract_json(stdout)
    
    def clear_highlights(self) -> Dict[str, Any]:
        """
        Clear all failure highlights from all windows.
        
        Returns:
            Dictionary with result: {"success": true/false, "cleared": count}
        """
        stdout, stderr, code = self._run_command("clear-highlights")
        return self._extract_json(stdout)
    
    def wait_for_window(self, window_title: str, timeout: float = 5.0) -> Dict[str, Any]:
        """
        Wait for a window to appear with timeout.
        
        Args:
            window_title: Window title to wait for
            timeout: Maximum seconds to wait (default 5)
            
        Returns:
            Dictionary with result: {"success": true/false, "window": "title", "waitTime": seconds}
        """
        stdout, stderr, code = self._run_command(
            "wait-window", window_title, str(timeout)
        )
        return self._extract_json(stdout)
    
    def close_window(self, window_title: str) -> Dict[str, Any]:
        """
        Close a window by title.
        
        Args:
            window_title: Title of window to close
            
        Returns:
            Dictionary with result: {"success": true/false, "closed": "window title"}
        """
        stdout, stderr, code = self._run_command("close-window", window_title)
        return self._extract_json(stdout)
    
    def find_element(self, window_title: str, text: str) -> Dict[str, Any]:
        """
        Find a UI element by text content in a specific window.
        
        Args:
            window_title: Window title to search in
            text: Text content to find
            
        Returns:
            Dictionary with element info: {"found": true/false, "class": "NSTextField", "frame": {...}}
        """
        stdout, stderr, code = self._run_command("find", window_title, text)
        return self._extract_json(stdout)
    
    def assert_text_contains(self, window_title: str, expected_text: str, 
                             actual_text: str = None, highlight_on_fail: bool = True) -> bool:
        """
        Assert that element text matches expected value. Highlights element in red if it fails.
        
        Args:
            window_title: Window title to search in
            expected_text: The text we expect to find
            actual_text: If provided, the text found (for comparison). Otherwise searches for expected.
            highlight_on_fail: Whether to highlight the element in red on failure
            
        Returns:
            True if assertion passes
            
        Raises:
            AssertionFailedError: If text doesn't match (element is highlighted red)
        """
        if actual_text is not None:
            # Compare provided text
            if expected_text not in actual_text:
                if highlight_on_fail:
                    self.highlight_failure(window_title, actual_text, 0)
                raise AssertionFailedError(
                    f"Expected text '{expected_text}' not found in '{actual_text}'"
                )
        else:
            # Search for expected text
            result = self.find_element(window_title, expected_text)
            if not result.get('found', False):
                raise AssertionFailedError(
                    f"Text '{expected_text}' not found in window '{window_title}'"
                )
        
        return True
    
    # Assertion Helpers
    
    def window_exists(self, title: str) -> bool:
        """
        Check if a window with the given title exists.
        
        Args:
            title: Window title to search for
            
        Returns:
            True if window exists, False otherwise
        """
        try:
            state = self.query_ui_state()
            windows = state.get('windows', [])
            
            for window in windows:
                # Check both 'title' and 'windowTitle' for compatibility
                if window.get('title') == title or window.get('windowTitle') == title:
                    return True
            return False
        except Exception:
            return False
    
    def text_visible(self, text: str, case_sensitive: bool = False) -> bool:
        """
        Check if text is visible in any UI element.
        
        Args:
            text: Text to search for
            case_sensitive: Whether search is case-sensitive
            
        Returns:
            True if text is found in any element
        """
        try:
            state = self.query_ui_state()
            search_text = text if case_sensitive else text.lower()
            
            def search_in_tree(obj):
                if isinstance(obj, dict):
                    # Check text field
                    if 'text' in obj:
                        element_text = obj['text']
                        if not case_sensitive:
                            element_text = element_text.lower()
                        if search_text in element_text:
                            return True
                    
                    # Recurse into children
                    if 'children' in obj:
                        for child in obj['children']:
                            if search_in_tree(child):
                                return True
                elif isinstance(obj, list):
                    for item in obj:
                        if search_in_tree(item):
                            return True
                
                return False
            
            windows = state.get('windows', [])
            for window in windows:
                if search_in_tree(window):
                    return True
            return False
            
        except Exception:
            return False
    
    def get_window_elements(self, title: str) -> List[Dict[str, Any]]:
        """
        Get all UI elements in a specific window.
        
        Args:
            title: Window title
            
        Returns:
            List of element dictionaries
        """
        state = self.query_ui_state()
        windows = state.get('windows', [])
        
        for window in windows:
            if window.get('title') == title or window.get('windowTitle') == title:
                # Support both 'views' and 'contentView' keys
                if 'views' in window and window['views']:
                    views = window['views']
                    if views and len(views) > 0:
                        return views[0].get('children', [])
                elif 'contentView' in window:
                    content = window['contentView']
                    return content.get('children', [])
        
        raise AssertionFailedError(f"Window not found: {title}")
    
    def assert_window_exists(self, title: str, msg: str = "") -> None:
        """
        Assert that a window exists.
        
        Args:
            title: Expected window title
            msg: Optional assertion message
            
        Raises:
            AssertionFailedError: If window doesn't exist
        """
        if not self.window_exists(title):
            error_msg = msg or f"Window '{title}' not found"
            raise AssertionFailedError(error_msg)
    
    def assert_text_visible(self, text: str, msg: str = "", case_sensitive: bool = False) -> None:
        """
        Assert that text is visible in the UI.
        
        Args:
            text: Text to search for
            msg: Optional assertion message
            case_sensitive: Whether search is case-sensitive
            
        Raises:
            AssertionFailedError: If text is not found
        """
        if not self.text_visible(text, case_sensitive):
            error_msg = msg or f"Text '{text}' not found in UI"
            raise AssertionFailedError(error_msg)
    
    def assert_element_exists(self, class_name: str, msg: str = "") -> None:
        """
        Assert that an element with given class exists.
        
        Args:
            class_name: Objective-C class name (e.g., "NSButton")
            msg: Optional assertion message
            
        Raises:
            AssertionFailedError: If element doesn't exist
        """
        try:
            state = self.query_ui_state()
            
            def find_class(obj):
                if isinstance(obj, dict):
                    if obj.get('class') == class_name:
                        return True
                    if 'children' in obj:
                        for child in obj['children']:
                            if find_class(child):
                                return True
                elif isinstance(obj, list):
                    for item in obj:
                        if find_class(item):
                            return True
                return False
            
            windows = state.get('windows', [])
            for window in windows:
                if find_class(window):
                    return
            
            error_msg = msg or f"Element with class '{class_name}' not found"
            raise AssertionFailedError(error_msg)
            
        except AssertionFailedError:
            raise
        except Exception as e:
            raise AssertionFailedError(f"Error searching for element: {e}")
    
    def get_last_json_response(self) -> Dict[str, Any]:
        """Get the last JSON response from the server."""
        if self._last_json_response is None:
            raise UITestException("No previous query executed")
        return self._last_json_response
    
    # ========== Modal Dialog Detection ==========
    
    def get_modal_windows(self) -> List[Dict[str, Any]]:
        """
        Get all visible modal/panel windows that might block interaction.
        
        Modal windows include:
        - NSPanel, NSAlertPanel
        - Windows with "Alert", "Error", "Warning" in title
        - Small windows that appear on top
        
        Returns:
            List of window dictionaries that appear to be modals
        """
        visible = self.get_visible_windows()
        modals = []
        
        modal_classes = ['NSPanel', 'NSAlertPanel', 'GSAlertPanel', 'NSOpenPanel', 
                         'NSSavePanel', 'NSFontPanel', 'NSColorPanel']
        modal_title_keywords = ['Alert', 'Error', 'Warning', 'Confirm', 'Delete',
                                'Save', 'Open', 'Choose', 'Select']
        
        for w in visible:
            window_class = w.get('class', '')
            title = w.get('title', '')
            
            # Check by class
            if any(mc in window_class for mc in modal_classes):
                modals.append(w)
                continue
            
            # Check by title keywords
            if any(kw.lower() in title.lower() for kw in modal_title_keywords):
                modals.append(w)
                continue
            
            # Check for small windows (likely dialogs)
            frame = w.get('frame', {})
            width = frame.get('width', 1000)
            height = frame.get('height', 1000)
            if width < 400 and height < 300:
                # Small window, might be a dialog
                modals.append(w)
        
        return modals
    
    def has_modal_dialog(self) -> bool:
        """
        Check if there are any modal dialogs on screen.
        
        Returns:
            True if modal dialogs detected
        """
        return len(self.get_modal_windows()) > 0
    
    def get_alert_text(self) -> Optional[str]:
        """
        Get text from any visible alert/modal dialog.
        
        Returns:
            Alert message text, or None if no alert
        """
        modals = self.get_modal_windows()
        if not modals:
            return None
        
        # Get text from first modal
        texts = []
        
        def extract_texts(obj):
            if isinstance(obj, dict):
                if 'text' in obj and obj['text']:
                    texts.append(obj['text'])
                for key in ['children', 'contentView', 'views']:
                    if key in obj:
                        extract_texts(obj[key])
            elif isinstance(obj, list):
                for item in obj:
                    extract_texts(item)
        
        extract_texts(modals[0])
        return ' '.join(texts) if texts else None
    
    def dismiss_modal_dialogs(self, max_attempts: int = 3) -> int:
        """
        Attempt to dismiss any modal dialogs using keyboard.
        
        Args:
            max_attempts: Maximum Escape presses to try
            
        Returns:
            Number of dialogs that were dismissed
        """
        import subprocess
        import time
        
        dismissed = 0
        for _ in range(max_attempts):
            if not self.has_modal_dialog():
                break
            
            # Press Escape to dismiss
            subprocess.run(["xdotool", "key", "Escape"], 
                          capture_output=True, timeout=5)
            time.sleep(0.2)
            dismissed += 1
        
        return dismissed
    
    def ensure_clean_state(self) -> Dict[str, Any]:
        """
        Ensure the UI is in a clean state for testing.
        
        This will:
        - Dismiss any modal dialogs
        - Close Info/Finder/Preferences panels
        - Report what was cleaned up
        
        Returns:
            Dictionary with cleanup actions taken
        """
        import subprocess
        import time
        
        actions = {
            'modals_dismissed': 0,
            'windows_closed': [],
            'errors': []
        }
        
        # Dismiss modals
        try:
            actions['modals_dismissed'] = self.dismiss_modal_dialogs()
        except Exception as e:
            actions['errors'].append(f"Modal dismiss error: {e}")
        
        # Close common utility windows
        windows_to_close = ['Info', 'Finder', 'Workspace Preferences', 'Run']
        
        for title in windows_to_close:
            if self.window_exists(title):
                try:
                    # Focus and close
                    subprocess.run(
                        ["xdotool", "search", "--name", title, "windowactivate"],
                        capture_output=True, timeout=5
                    )
                    time.sleep(0.2)
                    subprocess.run(
                        ["xdotool", "key", "alt+w"],  # Cmd+W
                        capture_output=True, timeout=5
                    )
                    time.sleep(0.3)
                    actions['windows_closed'].append(title)
                except Exception as e:
                    actions['errors'].append(f"Close {title} error: {e}")
        
        return actions

    # Additional Helper Methods
    
    def get_visible_windows(self) -> List[Dict[str, Any]]:
        """
        Get only visible windows (filter out hidden cache windows).
        
        Returns:
            List of visible window dictionaries
        """
        state = self.query_ui_state()
        windows = state.get('windows', [])
        return [w for w in windows if w.get('visibility') == 'visible']
    
    def get_window_titles(self) -> List[str]:
        """
        Get list of all window titles.
        
        Returns:
            List of window title strings
        """
        state = self.query_ui_state()
        windows = state.get('windows', [])
        return [w.get('title', '') for w in windows]
    
    def get_visible_text_in_window(self, title: str) -> List[str]:
        """
        Get all text content visible in a window.
        
        Args:
            title: Window title
            
        Returns:
            List of text strings found in the window
        """
        texts = []
        
        def extract_texts(obj):
            if isinstance(obj, dict):
                if 'text' in obj and obj['text']:
                    texts.append(obj['text'])
                for key in ['children', 'contentView', 'views']:
                    if key in obj:
                        extract_texts(obj[key])
            elif isinstance(obj, list):
                for item in obj:
                    extract_texts(item)
        
        try:
            state = self.query_ui_state()
            for window in state.get('windows', []):
                if window.get('title') == title:
                    extract_texts(window)
                    break
        except Exception:
            pass
        
        return texts
    
    def count_elements_by_class(self, class_name: str) -> int:
        """
        Count UI elements with a specific class.
        
        Args:
            class_name: Objective-C class name (e.g., "NSButton")
            
        Returns:
            Number of elements found
        """
        count = 0
        
        def count_class(obj):
            nonlocal count
            if isinstance(obj, dict):
                if obj.get('class') == class_name:
                    count += 1
                for key in ['children', 'contentView', 'views']:
                    if key in obj:
                        count_class(obj[key])
            elif isinstance(obj, list):
                for item in obj:
                    count_class(item)
        
        try:
            state = self.query_ui_state()
            for window in state.get('windows', []):
                count_class(window)
        except Exception:
            pass
        
        return count
    
    def is_workspace_running(self) -> bool:
        """Check if Workspace is running and responding to commands."""
        try:
            self.query_ui_state()
            return True
        except WorkspaceNotRunningError:
            return False
        except Exception:
            return False
    
    def get_element_by_text(self, text: str) -> Optional[Dict[str, Any]]:
        """
        Find an element by its text content across all windows.
        
        Args:
            text: Text content to search for
            
        Returns:
            Element dictionary if found, None otherwise
        """
        def find_element(obj):
            if isinstance(obj, dict):
                if obj.get('text') == text:
                    return obj
                for key in ['children', 'contentView', 'views']:
                    if key in obj:
                        result = find_element(obj[key])
                        if result:
                            return result
            elif isinstance(obj, list):
                for item in obj:
                    result = find_element(item)
                    if result:
                        return result
            return None
        
        try:
            state = self.query_ui_state()
            for window in state.get('windows', []):
                result = find_element(window)
                if result:
                    return result
        except Exception:
            pass
        
        return None
    
    def wait_for_text(self, text: str, timeout: float = 5.0) -> bool:
        """
        Wait for specific text to appear in the UI.
        
        Args:
            text: Text to wait for
            timeout: Maximum seconds to wait
            
        Returns:
            True if text appeared, False if timeout
        """
        import time
        start = time.time()
        while time.time() - start < timeout:
            if self.text_visible(text):
                return True
            time.sleep(0.2)
        return False
    
    def wait_for_window_closed(self, title: str, timeout: float = 5.0) -> bool:
        """
        Wait for a window to close.
        
        Args:
            title: Window title to wait for closure
            timeout: Maximum seconds to wait
            
        Returns:
            True if window closed, False if timeout
        """
        import time
        start = time.time()
        while time.time() - start < timeout:
            if not self.window_exists(title):
                return True
            time.sleep(0.2)
        return False

    # File System Helper Methods
    
    def file_exists(self, path: str) -> bool:
        """Check if a file or directory exists on the filesystem."""
        import os
        return os.path.exists(path)
    
    def create_test_directory(self, base_path: str, name: str = "TestFolder") -> str:
        """
        Create a test directory via filesystem (for test setup).
        
        Args:
            base_path: Parent directory
            name: Name of directory to create
            
        Returns:
            Full path of created directory
        """
        import os
        full_path = os.path.join(base_path, name)
        if not os.path.exists(full_path):
            os.makedirs(full_path)
        return full_path
    
    def create_test_file(self, base_path: str, name: str = "TestFile.txt", 
                        content: str = "Test content") -> str:
        """
        Create a test file via filesystem (for test setup).
        
        Args:
            base_path: Parent directory
            name: Name of file to create
            content: Content to write
            
        Returns:
            Full path of created file
        """
        import os
        full_path = os.path.join(base_path, name)
        with open(full_path, 'w') as f:
            f.write(content)
        return full_path
    
    def delete_path(self, path: str) -> bool:
        """
        Delete a file or directory from filesystem (for test cleanup).
        
        Args:
            path: Path to delete
            
        Returns:
            True if deleted, False if didn't exist
        """
        import os
        import shutil
        if os.path.isdir(path):
            shutil.rmtree(path)
            return True
        elif os.path.isfile(path):
            os.remove(path)
            return True
        return False
    
    def get_trash_path(self) -> str:
        """Get the path to the Trash/Recycler directory."""
        import os
        return os.path.expanduser("~/.Trash")
    
    def list_directory(self, path: str) -> List[str]:
        """List contents of a directory."""
        import os
        if os.path.isdir(path):
            return os.listdir(path)
        return []
    
    def wait_for_file(self, path: str, timeout: float = 5.0, exists: bool = True) -> bool:
        """
        Wait for a file to exist or be deleted.
        
        Args:
            path: File path to check
            timeout: Maximum seconds to wait
            exists: If True, wait for file to exist. If False, wait for deletion.
            
        Returns:
            True if condition met, False if timeout
        """
        import time
        import os
        start = time.time()
        while time.time() - start < timeout:
            file_exists = os.path.exists(path)
            if exists and file_exists:
                return True
            if not exists and not file_exists:
                return True
            time.sleep(0.2)
        return False
    
    def refresh_viewer(self) -> Dict[str, Any]:
        """
        Refresh the file viewer display.
        Uses Cmd+Shift+R or menu.
        """
        # Query state first to trigger refresh
        return self.query_ui_state()
    
    def get_desktop_path(self) -> str:
        """Get the path to the Desktop directory."""
        import os
        return os.path.expanduser("~/Desktop")
    
    def unique_name(self, prefix: str = "Test") -> str:
        """Generate a unique name using timestamp."""
        import time
        return f"{prefix}_{int(time.time() * 1000)}"

    # ========== Menu State Methods ==========
    
    def get_menu_state(self) -> Dict[str, Any]:
        """
        Get all menus and menu items with their enabled/disabled state.
        
        Returns:
            Dictionary with:
            - success: True/False
            - menus: List of menu dictionaries, each with:
              - title: Menu title (e.g., "File")
              - enabled: Whether menu is enabled
              - items: List of menu item dictionaries with:
                - title: Item title
                - enabled: Whether item is enabled
                - action: Selector name (e.g., "newFolder:")
                - shortcut: Keyboard shortcut (e.g., "Shift+Cmd+N")
                - hasSubmenu: Whether item has a submenu
                - separator: True if this is a separator item
        """
        stdout, stderr, code = self._run_command("list-menus")
        
        if code != 0:
            raise CommandFailedError(f"Failed to get menu state: {stderr}")
        
        return self._extract_json(stdout)
    
    def get_menu_items(self, menu_title: str) -> List[Dict[str, Any]]:
        """
        Get items from a specific menu.
        
        Args:
            menu_title: Title of menu (e.g., "File", "Edit", "View")
            
        Returns:
            List of menu item dictionaries
        """
        state = self.get_menu_state()
        menus = state.get('menus', [])
        
        for menu in menus:
            if menu.get('title') == menu_title:
                return menu.get('items', [])
        
        raise UITestException(f"Menu not found: {menu_title}")
    
    def is_menu_item_enabled(self, menu_title: str, item_title: str) -> bool:
        """
        Check if a specific menu item is enabled.
        
        Args:
            menu_title: Menu name (e.g., "File")
            item_title: Menu item name (e.g., "New Folder")
            
        Returns:
            True if enabled, False if disabled
        """
        items = self.get_menu_items(menu_title)
        
        for item in items:
            if item.get('title') == item_title:
                return item.get('enabled', False)
        
        raise UITestException(f"Menu item not found: {menu_title} > {item_title}")
    
    def get_menu_item(self, menu_title: str, item_title: str) -> Dict[str, Any]:
        """
        Get detailed info about a specific menu item.
        
        Args:
            menu_title: Menu name (e.g., "File")
            item_title: Menu item name (e.g., "New Folder")
            
        Returns:
            Dictionary with item details
        """
        items = self.get_menu_items(menu_title)
        
        for item in items:
            if item.get('title') == item_title:
                return item
        
        raise UITestException(f"Menu item not found: {menu_title} > {item_title}")
    
    def get_enabled_menu_items(self, menu_title: str = None) -> List[Dict[str, Any]]:
        """
        Get all enabled (non-separator) menu items.
        
        Args:
            menu_title: Optional - limit to specific menu
            
        Returns:
            List of enabled menu item dictionaries with menu context
        """
        state = self.get_menu_state()
        menus = state.get('menus', [])
        enabled = []
        
        for menu in menus:
            if menu_title and menu.get('title') != menu_title:
                continue
            
            for item in menu.get('items', []):
                if item.get('separator'):
                    continue
                if item.get('enabled'):
                    item_copy = dict(item)
                    item_copy['menu'] = menu.get('title')
                    enabled.append(item_copy)
        
        return enabled
    
    def get_disabled_menu_items(self, menu_title: str = None) -> List[Dict[str, Any]]:
        """
        Get all disabled menu items.
        
        Args:
            menu_title: Optional - limit to specific menu
            
        Returns:
            List of disabled menu item dictionaries with menu context
        """
        state = self.get_menu_state()
        menus = state.get('menus', [])
        disabled = []
        
        for menu in menus:
            if menu_title and menu.get('title') != menu_title:
                continue
            
            for item in menu.get('items', []):
                if item.get('separator'):
                    continue
                if not item.get('enabled'):
                    item_copy = dict(item)
                    item_copy['menu'] = menu.get('title')
                    disabled.append(item_copy)
        
        return disabled
    
    def assert_menu_item_enabled(self, menu_title: str, item_title: str, 
                                  msg: str = "") -> None:
        """
        Assert that a menu item is enabled.
        
        Raises:
            AssertionFailedError: If item is disabled
        """
        if not self.is_menu_item_enabled(menu_title, item_title):
            error_msg = msg or f"Menu item '{menu_title} > {item_title}' is disabled"
            raise AssertionFailedError(error_msg)
    
    def assert_menu_item_disabled(self, menu_title: str, item_title: str,
                                   msg: str = "") -> None:
        """
        Assert that a menu item is disabled.
        
        Raises:
            AssertionFailedError: If item is enabled
        """
        if self.is_menu_item_enabled(menu_title, item_title):
            error_msg = msg or f"Menu item '{menu_title} > {item_title}' is enabled (expected disabled)"
            raise AssertionFailedError(error_msg)


# Convenience functions

def assert_about_opens() -> None:
    """Quick test: verify About dialog can be opened."""
    client = WorkspaceTestClient()
    client.open_about_dialog()
    client.assert_window_exists("About")


def test_workspace_responding() -> bool:
    """Check if Workspace is running and responding."""
    try:
        client = WorkspaceTestClient()
        client.query_ui_state()
        return True
    except WorkspaceNotRunningError:
        return False


def run_tests(*tests: tuple, verbose: bool = True, stop_on_failure: bool = False,
               highlight_failures: bool = True, client: 'WorkspaceTestClient' = None) -> int:
    """
    Run a list of tests with minimal boilerplate.
    
    This function automates test execution, error handling, and result reporting.
    Each test is a (name, callable) tuple where callable returns True/False or
    raises an exception on failure. JSON validation is automatic when querying
    UI state.
    
    Features:
    - Stop-on-failure: Stop execution at first failure
    - Failure highlighting: Mark failed elements with red overlay in the UI
    - Visual feedback: See what's happening on screen during test execution
    
    Usage:
        from uitest import WorkspaceTestClient, run_tests
        
        client = WorkspaceTestClient()
        
        exit(run_tests(
            ("About opens", lambda: client.menu("Info > About") or True),
            ("Window exists", lambda: client.window_exists("About")),
            ("Check theme", lambda: client.text_visible("Current Theme")),
            stop_on_failure=True,
            highlight_failures=True,
            client=client
        ))
    
    Args:
        *tests: Tuples of (test_name: str, test_function: callable)
        verbose: Whether to print results (default True)
        stop_on_failure: Stop at first failing test (default False)
        highlight_failures: Highlight failed elements in red (default True)
        client: WorkspaceTestClient instance for highlighting (optional)
    
    Returns:
        0 if all tests pass, 1 if any fail
    """
    if not tests:
        return 0
    
    results = []
    failed_test_name = None
    failed_error = None
    
    for test_name, test_func in tests:
        try:
            if verbose:
                print(f"▶ Running: {test_name}", end='', flush=True)
            
            result = test_func()
            
            # Allow test to return True/False or just raise on failure
            if result is False:
                if verbose:
                    print(f"\r✗ {test_name}")
                results.append(False)
                failed_test_name = test_name
                
                if stop_on_failure:
                    print(f"\n⛔ STOPPED: Test failed - {test_name}")
                    break
            else:
                if verbose:
                    print(f"\r✓ {test_name}")
                results.append(True)
                
        except AssertionFailedError as e:
            if verbose:
                print(f"\r✗ {test_name}: {e}")
            results.append(False)
            failed_test_name = test_name
            failed_error = str(e)
            
            # Try to highlight the failed element if client is provided
            if highlight_failures and client:
                try:
                    # Extract element text from error if possible
                    if "'" in str(e):
                        parts = str(e).split("'")
                        if len(parts) >= 2:
                            element_text = parts[1]
                            # Try to find and highlight in any visible window
                            state = client.query_ui_state()
                            for window in state.get('windows', []):
                                title = window.get('title', '')
                                if title:
                                    client.highlight_failure(title, element_text, 0)
                                    break
                except:
                    pass  # Silently ignore highlighting errors
            
            if stop_on_failure:
                print(f"\n⛔ STOPPED: Test failed - {test_name}")
                if failed_error:
                    print(f"   Error: {failed_error}")
                break
                
        except Exception as e:
            if verbose:
                print(f"\r✗ {test_name}: {type(e).__name__}: {e}")
            results.append(False)
            failed_test_name = test_name
            failed_error = str(e)
            
            if stop_on_failure:
                print(f"\n⛔ STOPPED: Test failed - {test_name}")
                print(f"   Error: {type(e).__name__}: {e}")
                break
    
    if verbose:
        passed = sum(results)
        total = len(tests)
        executed = len(results)
        print()
        if executed < total:
            print(f"Results: {passed}/{executed} tests passed ({total - executed} not executed)")
        else:
            print(f"Results: {passed}/{total} tests passed")
        
        if not all(results):
            print(f"Status: FAILED ❌")
        else:
            print(f"Status: PASSED ✓")
    
    return 0 if all(results) else 1


def run_interactive_tests(*tests: tuple, client: 'WorkspaceTestClient' = None,
                          pause_between: float = 0.5, **kwargs) -> int:
    """
    Run interactive tests with visual feedback on the UI.
    
    Same as run_tests but with:
    - Default stop_on_failure=True
    - Default highlight_failures=True
    - Brief pause between tests for visual feedback
    
    Args:
        *tests: Tuples of (test_name: str, test_function: callable)
        client: WorkspaceTestClient instance (required for highlighting)
        pause_between: Seconds to pause between tests (default 0.5)
        **kwargs: Additional arguments passed to run_tests
        
    Returns:
        0 if all tests pass, 1 if any fail
    """
    import time
    
    # Default to stop-on-failure for interactive testing
    kwargs.setdefault('stop_on_failure', True)
    kwargs.setdefault('highlight_failures', True)
    kwargs.setdefault('verbose', True)
    kwargs['client'] = client
    
    if not tests:
        return 0
    
    # Wrap tests to add pause between them
    def make_paused_test(original_func):
        def paused():
            result = original_func()
            time.sleep(pause_between)
            return result
        return paused
    
    paused_tests = tuple((name, make_paused_test(func)) for name, func in tests)
    
    return run_tests(*paused_tests, **kwargs)


# Backward compatibility alias
simple_tests = run_tests
