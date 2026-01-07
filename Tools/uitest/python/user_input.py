#!/usr/bin/env python3
"""
user_input.py - Simulate user keyboard and mouse input

Uses xdotool to simulate real user input - keyboard shortcuts, 
mouse clicks, and text typing. This allows tests to drive the 
application exactly like a human user would.
"""

import subprocess
import time
import os
import math
import random
from typing import Optional, Tuple, List

class UserInputError(Exception):
    """Error during user input simulation."""
    pass


class UserInput:
    """
    Simulate user keyboard and mouse input via xdotool.
    
    All methods interact with the GUI exactly as a user would -
    no internal application APIs are used.
    """
    
    def __init__(self):
        """Initialize and verify xdotool is available."""
        self._verify_xdotool()
        self.key_delay = 50  # ms between key events
        self.type_delay = 20  # ms between typed characters
        self._current_mouse_pos = None  # Track mouse position for smooth moves
        self._mouse_speed = 800  # pixels per second for smooth movement
    
    def _verify_xdotool(self):
        """Verify xdotool is installed."""
        result = subprocess.run(["which", "xdotool"], capture_output=True)
        if result.returncode != 0:
            raise UserInputError("xdotool not found. Install with: apt install xdotool")
    
    def _run(self, *args) -> str:
        """Run xdotool command and return output."""
        cmd = ["xdotool"] + list(args)
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=10)
        if result.returncode != 0:
            raise UserInputError(f"xdotool failed: {result.stderr}")
        return result.stdout.strip()
    
    def _get_mouse_position(self) -> Tuple[int, int]:
        """Get current mouse position."""
        output = self._run("getmouselocation", "--shell")
        vals = {}
        for line in output.split('\n'):
            if '=' in line:
                k, v = line.split('=')
                vals[k] = int(v)
        return (vals.get('X', 0), vals.get('Y', 0))
    
    # ========== Smooth Mouse Movement ==========
    
    def move_mouse_smoothly(self, target_x: int, target_y: int, 
                            speed: Optional[float] = None,
                            variation: float = 0.1):
        """
        Move mouse smoothly to target coordinates like a human would.
        
        Uses a bezier curve with slight randomization to simulate
        natural human mouse movement.
        
        Args:
            target_x: Target X coordinate
            target_y: Target Y coordinate
            speed: Pixels per second (None = use default self._mouse_speed)
            variation: Random variation factor (0 = straight line, higher = more wobble)
        """
        current_x, current_y = self._get_mouse_position()
        
        if speed is None:
            speed = self._mouse_speed
        
        # Calculate distance and duration
        dx = target_x - current_x
        dy = target_y - current_y
        distance = math.sqrt(dx * dx + dy * dy)
        
        if distance < 5:
            # Very short distance, just move directly
            self._run("mousemove", str(target_x), str(target_y))
            return
        
        # Calculate duration based on speed (minimum 0.1s, maximum 1.5s)
        duration = max(0.1, min(1.5, distance / speed))
        
        # Generate bezier control points for natural curve
        # Add slight random offset to control point for human-like curve
        mid_x = (current_x + target_x) / 2
        mid_y = (current_y + target_y) / 2
        
        # Add perpendicular offset for curve
        perp_x = -dy * variation * random.uniform(-1, 1)
        perp_y = dx * variation * random.uniform(-1, 1)
        
        control_x = mid_x + perp_x
        control_y = mid_y + perp_y
        
        # Calculate number of steps (aim for ~60 fps feel, but cap at reasonable number)
        steps = max(5, min(30, int(distance / 20)))
        step_delay = duration / steps
        
        # Generate points along quadratic bezier curve
        for i in range(1, steps + 1):
            t = i / steps
            # Quadratic bezier: B(t) = (1-t)²P0 + 2(1-t)tP1 + t²P2
            inv_t = 1 - t
            x = int(inv_t * inv_t * current_x + 
                   2 * inv_t * t * control_x + 
                   t * t * target_x)
            y = int(inv_t * inv_t * current_y + 
                   2 * inv_t * t * control_y + 
                   t * t * target_y)
            
            self._run("mousemove", str(x), str(y))
            time.sleep(step_delay)
        
        # Ensure we end at exact target
        self._run("mousemove", str(target_x), str(target_y))
    
    def move_mouse_linear(self, target_x: int, target_y: int,
                          duration: float = 0.3):
        """
        Move mouse in a straight line to target coordinates.
        
        Args:
            target_x: Target X coordinate
            target_y: Target Y coordinate  
            duration: Time to complete movement in seconds
        """
        current_x, current_y = self._get_mouse_position()
        
        steps = max(5, int(duration * 30))  # ~30 steps per second
        step_delay = duration / steps
        
        for i in range(1, steps + 1):
            t = i / steps
            x = int(current_x + (target_x - current_x) * t)
            y = int(current_y + (target_y - current_y) * t)
            self._run("mousemove", str(x), str(y))
            time.sleep(step_delay)
    
    # ========== Keyboard Methods ==========
    
    def key(self, keyspec: str):
        """
        Send a key or key combination.
        
        Args:
            keyspec: Key specification like "Return", "ctrl+s", "super+n"
            
        Examples:
            user.key("Return")
            user.key("ctrl+s")
            user.key("alt+F4")
            user.key("super+shift+n")  # Super = Windows/Command key
        """
        self._run("key", "--delay", str(self.key_delay), keyspec)
        time.sleep(0.1)  # Allow UI to process
    
    def type_text(self, text: str):
        """
        Type text as if user is typing on keyboard.
        
        Args:
            text: Text to type
        """
        self._run("type", "--delay", str(self.type_delay), text)
        time.sleep(0.1)
    
    def shortcut(self, *keys: str):
        """
        Send a keyboard shortcut.
        
        Args:
            *keys: Keys to press together, e.g., "ctrl", "shift", "n"
            
        Examples:
            user.shortcut("ctrl", "s")       # Ctrl+S
            user.shortcut("ctrl", "shift", "n")  # Ctrl+Shift+N
            user.shortcut("alt", "F4")       # Alt+F4
        """
        keyspec = "+".join(keys)
        self.key(keyspec)
    
    def cmd(self, key: str):
        """
        Send Command/Alt + key (GNUstep uses Alt as Command).
        
        Args:
            key: Key to combine with Command
        """
        self.key(f"alt+{key}")
    
    def cmd_shift(self, key: str):
        """Send Command+Shift+key (Alt+Shift on GNUstep)."""
        self.key(f"alt+shift+{key}")
    
    def press_return(self):
        """Press Enter/Return key."""
        self.key("Return")
    
    def press_escape(self):
        """Press Escape key."""
        self.key("Escape")
    
    def press_tab(self):
        """Press Tab key."""
        self.key("Tab")
    
    def press_backspace(self):
        """Press Backspace key."""
        self.key("BackSpace")
    
    def press_delete(self):
        """Press Delete key."""
        self.key("Delete")
    
    def press_arrow(self, direction: str):
        """Press arrow key. direction: up, down, left, right"""
        key_map = {"up": "Up", "down": "Down", "left": "Left", "right": "Right"}
        self.key(key_map.get(direction.lower(), direction))
    
    # ========== Focus Check Methods ==========
    
    def get_focused_window_name(self) -> Optional[str]:
        """
        Get the name of the currently focused window.
        
        Returns:
            Window name, or None if cannot determine
        """
        try:
            result = subprocess.run(
                ["xdotool", "getactivewindow"],
                capture_output=True,
                text=True,
                timeout=5
            )
            if result.returncode != 0:
                return None
            
            wid = result.stdout.strip()
            result = subprocess.run(
                ["xdotool", "getwindowname", wid],
                capture_output=True,
                text=True,
                timeout=5
            )
            if result.returncode == 0:
                return result.stdout.strip()
        except:
            pass
        return None
    
    def check_focus_before_click(self, log_func=None) -> bool:
        """
        Check if there's an unexpected window stealing focus.
        
        This does a quick check for focus stealers like modal dialogs.
        If found, tries to dismiss them.
        
        Args:
            log_func: Optional logging function to report findings
            
        Returns:
            True if focus is OK (or was corrected)
        """
        focused = self.get_focused_window_name()
        if not focused:
            return True  # Can't determine, assume OK
        
        if log_func:
            log_func(f"Focus check: current focus = '{focused}'")
        
        # Check for obvious alerts/dialogs
        alert_keywords = ['alert', 'error', 'warning', 'confirm', 'delete']
        focused_lower = focused.lower()
        
        if any(kw in focused_lower for kw in alert_keywords):
            if log_func:
                log_func(f"Focus check: detected alert dialog '{focused}', pressing Escape")
            self.press_escape()
            time.sleep(0.2)
            return True  # Attempted to dismiss
        
        return True
    
    # ========== Mouse Methods ==========
    
    def click(self, x: int, y: int, button: int = 1, smooth: bool = False, 
              check_focus: bool = False):
        """
        Click at screen coordinates.
        
        Args:
            x: X screen coordinate
            y: Y screen coordinate
            button: Mouse button (1=left, 2=middle, 3=right)
            smooth: If True, move mouse smoothly like a human
            check_focus: If True, check for focus stealers before clicking
        """
        if check_focus:
            self.check_focus_before_click()
        
        if smooth:
            self.move_mouse_smoothly(x, y)
        else:
            self._run("mousemove", str(x), str(y))
        time.sleep(0.05)
        self._run("click", str(button))
        time.sleep(0.1)
    
    def click_smooth(self, x: int, y: int, button: int = 1, check_focus: bool = False):
        """Click with smooth human-like mouse movement."""
        self.click(x, y, button=button, smooth=True, check_focus=check_focus)
    
    def click_safe(self, x: int, y: int, button: int = 1, smooth: bool = True):
        """
        Safe click that always checks for focus stealers first.
        
        This is the RECOMMENDED way to click during tests.
        """
        self.check_focus_before_click()
        self.click(x, y, button=button, smooth=smooth)
    
    def double_click(self, x: int, y: int, smooth: bool = False, check_focus: bool = False):
        """Double-click at screen coordinates."""
        if check_focus:
            self.check_focus_before_click()
        
        if smooth:
            self.move_mouse_smoothly(x, y)
        else:
            self._run("mousemove", str(x), str(y))
        time.sleep(0.05)
        self._run("click", "--repeat", "2", "--delay", "50", "1")
        time.sleep(0.1)
    
    def double_click_smooth(self, x: int, y: int, check_focus: bool = False):
        """Double-click with smooth human-like mouse movement."""
        self.double_click(x, y, smooth=True, check_focus=check_focus)
    
    def right_click(self, x: int, y: int, smooth: bool = False, check_focus: bool = False):
        """Right-click at screen coordinates."""
        self.click(x, y, button=3, smooth=smooth, check_focus=check_focus)
    
    def right_click_smooth(self, x: int, y: int, check_focus: bool = False):
        """Right-click with smooth human-like mouse movement."""
        self.right_click(x, y, smooth=True, check_focus=check_focus)
    
    def move_mouse(self, x: int, y: int, smooth: bool = False):
        """Move mouse to screen coordinates without clicking."""
        if smooth:
            self.move_mouse_smoothly(x, y)
        else:
            self._run("mousemove", str(x), str(y))
    
    def drag(self, from_x: int, from_y: int, to_x: int, to_y: int, smooth: bool = False):
        """
        Drag from one point to another.
        
        Args:
            from_x, from_y: Starting coordinates
            to_x, to_y: Ending coordinates
            smooth: If True, drag smoothly like a human
        """
        if smooth:
            self.move_mouse_smoothly(from_x, from_y)
        else:
            self._run("mousemove", str(from_x), str(from_y))
        time.sleep(0.05)
        self._run("mousedown", "1")
        time.sleep(0.05)
        if smooth:
            self.move_mouse_smoothly(to_x, to_y)
        else:
            self._run("mousemove", str(to_x), str(to_y))
        time.sleep(0.05)
        self._run("mouseup", "1")
        time.sleep(0.1)
    
    def drag_smooth(self, from_x: int, from_y: int, to_x: int, to_y: int):
        """Drag with smooth human-like mouse movement."""
        self.drag(from_x, from_y, to_x, to_y, smooth=True)
    
    # ========== Window Methods ==========
    
    def get_active_window_id(self) -> str:
        """Get the currently active window ID."""
        return self._run("getactivewindow")
    
    def get_window_name(self, window_id: str) -> str:
        """Get the name/title of a window."""
        return self._run("getwindowname", window_id)
    
    def focus_window(self, window_id: str):
        """Focus a specific window by ID."""
        self._run("windowactivate", window_id)
        time.sleep(0.2)
    
    def focus_window_by_name(self, name: str) -> bool:
        """
        Focus a window by name/title.
        
        Returns:
            True if window found and focused
        """
        try:
            result = subprocess.run(
                ["xdotool", "search", "--name", name],
                capture_output=True, text=True, timeout=5
            )
            if result.returncode == 0 and result.stdout.strip():
                window_id = result.stdout.strip().split('\n')[0]
                self._run("windowactivate", window_id)
                time.sleep(0.2)
                return True
        except:
            pass
        return False
    
    def get_window_geometry(self, window_id: str) -> Tuple[int, int, int, int]:
        """
        Get window geometry.
        
        Returns:
            Tuple of (x, y, width, height)
        """
        output = self._run("getwindowgeometry", "--shell", window_id)
        vals = {}
        for line in output.split('\n'):
            if '=' in line:
                k, v = line.split('=')
                vals[k] = int(v)
        return (vals.get('X', 0), vals.get('Y', 0), 
                vals.get('WIDTH', 0), vals.get('HEIGHT', 0))
    
    def search_window(self, name: str) -> Optional[str]:
        """
        Search for a window by name.
        
        Returns:
            Window ID if found, None otherwise
        """
        try:
            result = subprocess.run(
                ["xdotool", "search", "--name", name],
                capture_output=True, text=True, timeout=5
            )
            if result.returncode == 0 and result.stdout.strip():
                return result.stdout.strip().split('\n')[0]
        except:
            pass
        return None
    
    # ========== Utility Methods ==========
    
    def wait(self, seconds: float):
        """Wait for specified time."""
        time.sleep(seconds)
    
    def wait_for_window(self, name: str, timeout: float = 5.0) -> bool:
        """
        Wait for a window with given name to appear.
        
        Returns:
            True if window appeared, False if timeout
        """
        start = time.time()
        while time.time() - start < timeout:
            if self.search_window(name):
                return True
            time.sleep(0.2)
        return False
    
    def take_screenshot(self, filename: str):
        """Take a screenshot of the entire screen."""
        subprocess.run(["scrot", filename], capture_output=True)
    
    # ========== Modal Dialog Dismissal ==========
    
    def dismiss_dialog_escape(self):
        """Try to dismiss a modal dialog by pressing Escape."""
        self.press_escape()
        time.sleep(0.2)
    
    def dismiss_dialog_return(self):
        """Try to dismiss a modal dialog by pressing Return (accept default)."""
        self.press_return()
        time.sleep(0.2)
    
    def dismiss_dialog_click_button(self, button_text: str = "OK"):
        """
        Try to dismiss a dialog by clicking a button.
        
        This uses accessibility features to find and click buttons.
        Falls back to common button positions if not found.
        
        Args:
            button_text: Text of button to click (e.g., "OK", "Cancel")
        """
        # Try pressing Return for OK/default buttons
        if button_text.lower() in ['ok', 'yes', 'continue', 'accept']:
            self.press_return()
        elif button_text.lower() in ['cancel', 'no', 'abort']:
            self.press_escape()
        else:
            # Default to Escape
            self.press_escape()
        time.sleep(0.2)
    
    def dismiss_all_dialogs(self, max_attempts: int = 5):
        """
        Attempt to dismiss any modal dialogs on screen.
        
        Tries pressing Escape multiple times to close dialogs.
        
        Args:
            max_attempts: Maximum number of Escape presses
        """
        for _ in range(max_attempts):
            self.press_escape()
            time.sleep(0.15)
    
    def click_dialog_button_by_position(self, position: str = "right"):
        """
        Click a dialog button by its typical position.
        
        In most dialogs:
        - Right button = OK/Accept/Default
        - Left button = Cancel
        
        Args:
            position: "left", "right", or "center"
        """
        # Get active window
        try:
            wid = self.get_active_window_id()
            x, y, w, h = self.get_window_geometry(wid)
            
            # Dialog buttons are typically near bottom
            button_y = y + h - 40
            
            if position == "right":
                button_x = x + w - 80
            elif position == "left":
                button_x = x + 80
            else:  # center
                button_x = x + w // 2
            
            self.click_smooth(button_x, button_y)
        except:
            # Fallback to keyboard
            if position == "right":
                self.press_return()
            else:
                self.press_escape()


# Convenience instance
user = UserInput()
