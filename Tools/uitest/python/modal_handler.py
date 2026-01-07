#!/usr/bin/env python3
"""
modal_handler.py - Smart modal dialog detection and handling

This module detects and handles modal dialogs WITHOUT querying the Workspace UI
(which can block/timeout). Instead, it uses xdotool and xprop to inspect windows.

Key Features:
- Non-blocking modal detection via xdotool
- Detects focus stealers before clicks
- Handles modals by clicking buttons or closing windows
- Works even when Workspace UI is blocked
"""

import subprocess
import time
import os
from typing import Optional, Dict, Any, List, Tuple
from dataclasses import dataclass


@dataclass
class WindowInfo:
    """Information about a window from xdotool."""
    window_id: str
    name: str
    x: int = 0
    y: int = 0
    width: int = 0
    height: int = 0
    wm_class: str = ""
    
    @property
    def is_small_dialog(self) -> bool:
        """Check if window appears to be a small dialog."""
        return self.width > 0 and self.width < 500 and self.height < 400
    
    @property
    def looks_like_alert(self) -> bool:
        """Check if window looks like an alert/modal."""
        keywords = ['alert', 'error', 'warning', 'confirm', 'delete', 
                    'save', 'open', 'choose', 'panel']
        name_lower = self.name.lower()
        class_lower = self.wm_class.lower()
        return any(kw in name_lower or kw in class_lower for kw in keywords)


class ModalHandler:
    """
    Handles modal dialog detection and dismissal.
    
    This class uses xdotool/xprop directly instead of querying Workspace,
    which makes it non-blocking and reliable even when the UI is stuck.
    
    Usage:
        handler = ModalHandler()
        
        # Check before clicking
        if handler.has_focus_stealer("Workspace"):
            handler.dismiss_focus_stealer()
        
        # Do the click...
    """
    
    def __init__(self, workspace_name: str = "Workspace"):
        """
        Initialize the modal handler.
        
        Args:
            workspace_name: Name of the main application window
        """
        self.workspace_name = workspace_name
        self._known_workspace_windows: List[str] = []
    
    def _run_xdotool(self, *args) -> Tuple[str, int]:
        """Run xdotool command and return (stdout, returncode)."""
        try:
            result = subprocess.run(
                ["xdotool"] + list(args),
                capture_output=True,
                text=True,
                timeout=5
            )
            return result.stdout.strip(), result.returncode
        except subprocess.TimeoutExpired:
            return "", -1
        except Exception:
            return "", -1
    
    def _run_xprop(self, window_id: str, prop: str) -> str:
        """Run xprop to get a window property."""
        try:
            result = subprocess.run(
                ["xprop", "-id", window_id, prop],
                capture_output=True,
                text=True,
                timeout=3
            )
            if result.returncode == 0:
                return result.stdout.strip()
        except:
            pass
        return ""
    
    def get_focused_window(self) -> Optional[WindowInfo]:
        """
        Get information about the currently focused window.
        
        Returns:
            WindowInfo or None if cannot determine
        """
        output, code = self._run_xdotool("getactivewindow")
        if code != 0 or not output:
            return None
        
        wid = output.strip()
        return self.get_window_info(wid)
    
    def get_window_info(self, window_id: str) -> Optional[WindowInfo]:
        """
        Get detailed information about a window.
        
        Args:
            window_id: X11 window ID
            
        Returns:
            WindowInfo or None
        """
        # Get window name
        name_out, _ = self._run_xdotool("getwindowname", window_id)
        name = name_out.strip() if name_out else ""
        
        # Get geometry
        geom_out, _ = self._run_xdotool("getwindowgeometry", "--shell", window_id)
        x, y, width, height = 0, 0, 0, 0
        if geom_out:
            for line in geom_out.split('\n'):
                if '=' in line:
                    k, v = line.split('=', 1)
                    try:
                        if k == 'X':
                            x = int(v)
                        elif k == 'Y':
                            y = int(v)
                        elif k == 'WIDTH':
                            width = int(v)
                        elif k == 'HEIGHT':
                            height = int(v)
                    except:
                        pass
        
        # Get WM_CLASS
        wm_class = self._run_xprop(window_id, "WM_CLASS")
        
        return WindowInfo(
            window_id=window_id,
            name=name,
            x=x, y=y,
            width=width, height=height,
            wm_class=wm_class
        )
    
    def get_all_visible_windows(self) -> List[WindowInfo]:
        """
        Get list of all visible windows.
        
        Returns:
            List of WindowInfo objects
        """
        output, code = self._run_xdotool("search", "--onlyvisible", "--name", "")
        if code != 0 or not output:
            return []
        
        windows = []
        for wid in output.split('\n'):
            if not wid.strip():
                continue
            info = self.get_window_info(wid.strip())
            if info:
                windows.append(info)
        
        return windows
    
    def is_workspace_window(self, window: WindowInfo) -> bool:
        """
        Check if a window belongs to Workspace.
        
        Args:
            window: WindowInfo to check
            
        Returns:
            True if this is a Workspace window
        """
        # Check WM_CLASS for GNUstep/Workspace
        if 'GNUstep' in window.wm_class or 'Workspace' in window.wm_class:
            return True
        
        # Check for known Workspace window names
        workspace_names = [
            'Workspace', 'Inspector', 'Info', 'Finder', 'Run',
            'Workspace Preferences', 'About', 'Console', 'Recycler',
            'Open With', 'Go to Folder'
        ]
        for name in workspace_names:
            if name in window.name:
                return True
        
        return False
    
    def has_focus_stealer(self, expected_focus: Optional[str] = None) -> bool:
        """
        Check if something unexpected has stolen focus.
        
        Args:
            expected_focus: Window name that should have focus (None = any Workspace window)
            
        Returns:
            True if an unexpected window has focus
        """
        focused = self.get_focused_window()
        if not focused:
            return False  # Can't determine, assume OK
        
        if expected_focus:
            # Check for specific expected window
            if expected_focus.lower() in focused.name.lower():
                return False  # Expected window has focus
            
            # Check if it's a Workspace window (acceptable)
            if self.is_workspace_window(focused):
                # Could be a modal from Workspace
                if focused.looks_like_alert or focused.is_small_dialog:
                    return True  # Modal dialog
                return False  # Normal Workspace window
            
            # Non-Workspace window has focus
            return True
        else:
            # Just check if any Workspace window has focus
            if self.is_workspace_window(focused):
                # Check if it's a modal we need to dismiss
                if focused.looks_like_alert:
                    return True
                return False
            return True  # Non-Workspace window
    
    def detect_modal_dialog(self) -> Optional[WindowInfo]:
        """
        Detect if a modal dialog is currently displayed.
        
        Looks for:
        - Small focused windows
        - Windows with alert/warning keywords
        - Windows that are not the main viewer/desktop
        
        Returns:
            WindowInfo of modal, or None
        """
        focused = self.get_focused_window()
        if not focused:
            return None
        
        # Check if focused window looks like a modal
        if focused.looks_like_alert:
            return focused
        
        if focused.is_small_dialog and self.is_workspace_window(focused):
            # Small Workspace window, might be a dialog
            # Exclude known panels
            known_panels = ['Inspector', 'Finder', 'Preferences', 'Run']
            if not any(p in focused.name for p in known_panels):
                return focused
        
        return None
    
    def dismiss_with_escape(self, max_attempts: int = 3) -> bool:
        """
        Try to dismiss modal by pressing Escape.
        
        Args:
            max_attempts: Maximum Escape presses
            
        Returns:
            True if a modal was likely dismissed
        """
        initial_focus = self.get_focused_window()
        
        for i in range(max_attempts):
            self._run_xdotool("key", "Escape")
            time.sleep(0.2)
            
            # Check if focus changed
            new_focus = self.get_focused_window()
            if new_focus and initial_focus:
                if new_focus.window_id != initial_focus.window_id:
                    return True  # Focus changed, likely dismissed
        
        return False
    
    def dismiss_with_return(self) -> bool:
        """
        Try to dismiss modal by pressing Return (accept default).
        
        Returns:
            True if a modal was likely dismissed
        """
        initial_focus = self.get_focused_window()
        
        self._run_xdotool("key", "Return")
        time.sleep(0.3)
        
        new_focus = self.get_focused_window()
        if new_focus and initial_focus:
            if new_focus.window_id != initial_focus.window_id:
                return True
        
        return False
    
    def click_button_in_dialog(self, position: str = "right") -> bool:
        """
        Click a button in the current dialog window.
        
        Args:
            position: "right" (OK/Accept), "left" (Cancel), "center"
            
        Returns:
            True if click was performed
        """
        focused = self.get_focused_window()
        if not focused or focused.width == 0:
            return False
        
        # Calculate button position
        # Buttons are typically near the bottom of dialogs
        button_y = focused.y + focused.height - 40
        
        if position == "right":
            button_x = focused.x + focused.width - 80
        elif position == "left":
            button_x = focused.x + 80
        else:  # center
            button_x = focused.x + focused.width // 2
        
        self._run_xdotool("mousemove", str(button_x), str(button_y))
        time.sleep(0.1)
        self._run_xdotool("click", "1")
        time.sleep(0.2)
        
        return True
    
    def close_window(self) -> bool:
        """
        Close the currently focused window using Alt+F4 or Cmd+W.
        
        Returns:
            True if close command was sent
        """
        # Try Alt+W first (GNUstep command key)
        self._run_xdotool("key", "alt+w")
        time.sleep(0.3)
        
        # Check if focus changed
        return True
    
    def dismiss_focus_stealer(self, method: str = "auto") -> bool:
        """
        Dismiss whatever is stealing focus.
        
        Args:
            method: "escape", "return", "click", "close", or "auto"
            
        Returns:
            True if something was dismissed
        """
        if method == "auto":
            # Try Escape first
            if self.dismiss_with_escape(max_attempts=2):
                return True
            
            # Try clicking right button (OK/Accept)
            if self.click_button_in_dialog("right"):
                time.sleep(0.2)
                # Verify it worked
                if not self.has_focus_stealer():
                    return True
            
            # Try closing window
            if self.close_window():
                time.sleep(0.2)
                return True
            
            return False
        
        elif method == "escape":
            return self.dismiss_with_escape()
        elif method == "return":
            return self.dismiss_with_return()
        elif method == "click":
            return self.click_button_in_dialog()
        elif method == "close":
            return self.close_window()
        
        return False
    
    def ensure_workspace_focused(self, max_attempts: int = 5) -> bool:
        """
        Ensure a Workspace window has focus, dismissing any modals/stealers.
        
        Args:
            max_attempts: Maximum attempts to get Workspace focused
            
        Returns:
            True if Workspace is now focused
        """
        for i in range(max_attempts):
            focused = self.get_focused_window()
            if focused and self.is_workspace_window(focused):
                if not focused.looks_like_alert and not focused.is_small_dialog:
                    return True  # Good, normal Workspace window focused
                else:
                    # It's a modal/dialog, try to dismiss
                    self.dismiss_focus_stealer()
            else:
                # Not a Workspace window, try to focus one
                output, code = self._run_xdotool("search", "--name", "Workspace")
                if code == 0 and output:
                    wid = output.split('\n')[0]
                    self._run_xdotool("windowactivate", wid)
                    time.sleep(0.3)
        
        return False
    
    def pre_click_check(self) -> Dict[str, Any]:
        """
        Perform pre-click safety check.
        
        This should be called before any click operation to ensure
        the UI is in a good state.
        
        Returns:
            Dictionary with check results:
            - 'ok': True if safe to proceed
            - 'focused_window': Current focus info
            - 'modal_detected': Any modal that was found
            - 'actions_taken': List of actions taken
        """
        result = {
            'ok': True,
            'focused_window': None,
            'modal_detected': None,
            'actions_taken': []
        }
        
        # Get current focus
        focused = self.get_focused_window()
        result['focused_window'] = focused.name if focused else None
        
        # Check for modal
        modal = self.detect_modal_dialog()
        if modal:
            result['modal_detected'] = modal.name
            result['actions_taken'].append(f"Detected modal: {modal.name}")
            
            # Try to dismiss
            if self.dismiss_focus_stealer():
                result['actions_taken'].append("Dismissed modal")
            else:
                result['ok'] = False
                result['actions_taken'].append("Failed to dismiss modal")
        
        # Check focus stealer
        if self.has_focus_stealer():
            result['actions_taken'].append("Focus stealer detected")
            if self.dismiss_focus_stealer():
                result['actions_taken'].append("Dismissed focus stealer")
            else:
                result['ok'] = False
        
        return result


# Global instance
_handler = None

def get_handler() -> ModalHandler:
    """Get or create the global ModalHandler instance."""
    global _handler
    if _handler is None:
        _handler = ModalHandler()
    return _handler


def check_before_click() -> Dict[str, Any]:
    """
    Convenience function to check UI state before clicking.
    
    Usage:
        result = check_before_click()
        if not result['ok']:
            print(f"Warning: {result['actions_taken']}")
    """
    return get_handler().pre_click_check()


def dismiss_any_modals() -> bool:
    """
    Convenience function to dismiss any modal dialogs.
    
    Returns:
        True if modals were dismissed or none existed
    """
    handler = get_handler()
    modal = handler.detect_modal_dialog()
    if modal:
        return handler.dismiss_focus_stealer()
    return True  # No modal to dismiss
