#!/usr/bin/env python3
"""
test_failure_capture.py - Capture screenshots, logs, and state on test failure

When a test fails, this module captures:
- Screenshot of the current screen
- List of all windows from xdotool
- Focus window information
- Test log/traceback

This helps debug what went wrong without querying the (possibly blocked) UI.
"""

import subprocess
import os
import sys
import time
import traceback
from datetime import datetime
from typing import Optional, Dict, Any, List, Callable
from functools import wraps


class FailureCapture:
    """
    Captures screenshots and logs when tests fail.
    
    Usage:
        capture = FailureCapture(output_dir="/tmp/test_failures")
        
        # Manual capture
        capture.take_screenshot("test_menu_open")
        capture.capture_state("after_menu_click")
        
        # Decorator for tests
        @capture.on_failure
        def test_something():
            ...
    """
    
    def __init__(self, output_dir: str = "/tmp/uitest_failures"):
        """
        Initialize the failure capture system.
        
        Args:
            output_dir: Directory to store screenshots and logs
        """
        self.output_dir = output_dir
        self._ensure_output_dir()
        self._test_name = "unknown"
        self._log_lines: List[str] = []
    
    def _ensure_output_dir(self):
        """Create output directory if it doesn't exist."""
        os.makedirs(self.output_dir, exist_ok=True)
    
    def _timestamp(self) -> str:
        """Get current timestamp for filenames."""
        return datetime.now().strftime("%Y%m%d_%H%M%S")
    
    def set_test_name(self, name: str):
        """Set the current test name for logging."""
        self._test_name = name
        self._log_lines = []
    
    def log(self, message: str):
        """Add a log message."""
        timestamp = datetime.now().strftime("%H:%M:%S.%f")[:-3]
        line = f"[{timestamp}] {message}"
        self._log_lines.append(line)
        # Also print to stdout
        print(line)
    
    def take_screenshot(self, name: Optional[str] = None) -> Optional[str]:
        """
        Take a screenshot of the current screen.
        
        Args:
            name: Optional name for the screenshot
            
        Returns:
            Path to saved screenshot, or None if failed
        """
        timestamp = self._timestamp()
        safe_name = (name or self._test_name).replace(' ', '_').replace('/', '_')
        filename = f"{timestamp}_{safe_name}.png"
        filepath = os.path.join(self.output_dir, filename)
        
        try:
            # Try scrot first (common on Linux)
            result = subprocess.run(
                ["scrot", filepath],
                capture_output=True,
                timeout=5
            )
            if result.returncode == 0:
                self.log(f"Screenshot saved: {filepath}")
                return filepath
        except FileNotFoundError:
            pass
        except Exception as e:
            self.log(f"scrot failed: {e}")
        
        try:
            # Fallback to import (ImageMagick)
            result = subprocess.run(
                ["import", "-window", "root", filepath],
                capture_output=True,
                timeout=10
            )
            if result.returncode == 0:
                self.log(f"Screenshot saved: {filepath}")
                return filepath
        except FileNotFoundError:
            pass
        except Exception as e:
            self.log(f"import failed: {e}")
        
        try:
            # Last resort: xwd + convert
            xwd_file = filepath.replace('.png', '.xwd')
            subprocess.run(
                ["xwd", "-root", "-out", xwd_file],
                capture_output=True,
                timeout=10
            )
            subprocess.run(
                ["convert", xwd_file, filepath],
                capture_output=True,
                timeout=10
            )
            if os.path.exists(filepath):
                os.remove(xwd_file)
                self.log(f"Screenshot saved: {filepath}")
                return filepath
        except Exception as e:
            self.log(f"xwd+convert failed: {e}")
        
        self.log("WARNING: Could not capture screenshot (no tool available)")
        return None
    
    def get_focused_window_info(self) -> Dict[str, Any]:
        """
        Get information about the currently focused window using xdotool.
        This is non-blocking and doesn't require uitest.
        
        Returns:
            Dictionary with window info
        """
        info = {
            'window_id': None,
            'window_name': None,
            'window_class': None,
            'window_geometry': None,
            'error': None
        }
        
        try:
            # Get active window ID
            result = subprocess.run(
                ["xdotool", "getactivewindow"],
                capture_output=True,
                text=True,
                timeout=5
            )
            if result.returncode == 0:
                wid = result.stdout.strip()
                info['window_id'] = wid
                
                # Get window name
                result = subprocess.run(
                    ["xdotool", "getwindowname", wid],
                    capture_output=True,
                    text=True,
                    timeout=5
                )
                if result.returncode == 0:
                    info['window_name'] = result.stdout.strip()
                
                # Get window geometry
                result = subprocess.run(
                    ["xdotool", "getwindowgeometry", "--shell", wid],
                    capture_output=True,
                    text=True,
                    timeout=5
                )
                if result.returncode == 0:
                    geom = {}
                    for line in result.stdout.split('\n'):
                        if '=' in line:
                            k, v = line.split('=', 1)
                            geom[k] = v
                    info['window_geometry'] = geom
                
                # Try to get window class via xprop
                result = subprocess.run(
                    ["xprop", "-id", wid, "WM_CLASS"],
                    capture_output=True,
                    text=True,
                    timeout=5
                )
                if result.returncode == 0 and 'WM_CLASS' in result.stdout:
                    info['window_class'] = result.stdout.strip()
                    
        except Exception as e:
            info['error'] = str(e)
        
        return info
    
    def get_all_windows(self) -> List[Dict[str, Any]]:
        """
        Get list of all visible windows using xdotool.
        This is non-blocking and doesn't require uitest.
        
        Returns:
            List of window info dictionaries
        """
        windows = []
        
        try:
            # Search for all windows
            result = subprocess.run(
                ["xdotool", "search", "--onlyvisible", "--name", ""],
                capture_output=True,
                text=True,
                timeout=5
            )
            if result.returncode == 0:
                for wid in result.stdout.strip().split('\n'):
                    if not wid:
                        continue
                    try:
                        # Get window name
                        name_result = subprocess.run(
                            ["xdotool", "getwindowname", wid],
                            capture_output=True,
                            text=True,
                            timeout=2
                        )
                        name = name_result.stdout.strip() if name_result.returncode == 0 else ""
                        
                        windows.append({
                            'id': wid,
                            'name': name
                        })
                    except:
                        pass
        except Exception as e:
            self.log(f"Error getting window list: {e}")
        
        return windows
    
    def capture_state(self, label: str = "current") -> Dict[str, Any]:
        """
        Capture complete current state for debugging.
        
        Args:
            label: Label for this state capture
            
        Returns:
            Dictionary with all captured state
        """
        state = {
            'timestamp': self._timestamp(),
            'label': label,
            'test_name': self._test_name,
            'focused_window': self.get_focused_window_info(),
            'visible_windows': self.get_all_windows(),
            'mouse_position': self._get_mouse_position()
        }
        
        self.log(f"State captured: {label}")
        self.log(f"  Focused: {state['focused_window'].get('window_name', 'unknown')}")
        self.log(f"  Windows: {len(state['visible_windows'])} visible")
        
        return state
    
    def _get_mouse_position(self) -> Dict[str, int]:
        """Get current mouse position."""
        try:
            result = subprocess.run(
                ["xdotool", "getmouselocation", "--shell"],
                capture_output=True,
                text=True,
                timeout=5
            )
            if result.returncode == 0:
                pos = {}
                for line in result.stdout.split('\n'):
                    if '=' in line:
                        k, v = line.split('=', 1)
                        try:
                            pos[k] = int(v)
                        except:
                            pos[k] = v
                return pos
        except:
            pass
        return {'X': 0, 'Y': 0}
    
    def save_log(self, additional_info: str = "") -> Optional[str]:
        """
        Save the current log to a file.
        
        Args:
            additional_info: Additional information to append
            
        Returns:
            Path to log file
        """
        timestamp = self._timestamp()
        safe_name = self._test_name.replace(' ', '_').replace('/', '_')
        filename = f"{timestamp}_{safe_name}_log.txt"
        filepath = os.path.join(self.output_dir, filename)
        
        try:
            with open(filepath, 'w') as f:
                f.write(f"Test: {self._test_name}\n")
                f.write(f"Timestamp: {timestamp}\n")
                f.write("=" * 60 + "\n\n")
                
                f.write("LOG:\n")
                for line in self._log_lines:
                    f.write(line + "\n")
                f.write("\n")
                
                if additional_info:
                    f.write("ADDITIONAL INFO:\n")
                    f.write(additional_info + "\n\n")
                
                # Capture current state
                state = self.capture_state("at_log_save")
                f.write("CURRENT STATE:\n")
                f.write(f"  Focused window: {state['focused_window']}\n")
                f.write(f"  Mouse: {state['mouse_position']}\n")
                f.write(f"  Visible windows ({len(state['visible_windows'])}):\n")
                for w in state['visible_windows']:
                    f.write(f"    - {w.get('name', 'unnamed')} ({w.get('id', '?')})\n")
            
            self.log(f"Log saved: {filepath}")
            return filepath
        except Exception as e:
            self.log(f"Failed to save log: {e}")
            return None
    
    def on_failure(self, func: Callable) -> Callable:
        """
        Decorator that captures screenshot and log on test failure.
        
        Usage:
            @capture.on_failure
            def test_something():
                assert False, "This will trigger capture"
        """
        @wraps(func)
        def wrapper(*args, **kwargs):
            self.set_test_name(func.__name__)
            self.log(f"Starting test: {func.__name__}")
            
            try:
                result = func(*args, **kwargs)
                self.log(f"Test passed: {func.__name__}")
                return result
            except Exception as e:
                self.log(f"Test FAILED: {func.__name__}")
                self.log(f"Error: {type(e).__name__}: {e}")
                self.log(f"Traceback:\n{traceback.format_exc()}")
                
                # Capture everything
                screenshot = self.take_screenshot(f"FAIL_{func.__name__}")
                log_file = self.save_log(traceback.format_exc())
                
                self.log(f"Failure artifacts saved to: {self.output_dir}")
                
                # Re-raise the exception
                raise
        
        return wrapper


# Global instance for convenience
_capture = None

def get_capture(output_dir: str = "/tmp/uitest_failures") -> FailureCapture:
    """Get or create the global FailureCapture instance."""
    global _capture
    if _capture is None:
        _capture = FailureCapture(output_dir)
    return _capture


def on_test_failure(func: Callable) -> Callable:
    """
    Convenience decorator using global capture instance.
    
    Usage:
        @on_test_failure
        def test_something():
            ...
    """
    return get_capture().on_failure(func)


def capture_and_raise(exception: Exception, test_name: str = "unknown"):
    """
    Capture failure state and re-raise exception.
    
    Usage:
        try:
            do_something()
        except Exception as e:
            capture_and_raise(e, "my_test")
    """
    cap = get_capture()
    cap.set_test_name(test_name)
    cap.log(f"Exception caught: {type(exception).__name__}: {exception}")
    cap.take_screenshot(f"FAIL_{test_name}")
    cap.save_log(traceback.format_exc())
    raise exception
