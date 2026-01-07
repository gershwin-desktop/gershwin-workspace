#!/usr/bin/env python3
"""
Test 12: Error Handling

Verifies that errors are handled gracefully:
- Invalid window names
- Invalid element text
- Timeout handling
- Graceful failures
"""

import sys, os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'python'))

from uitest import WorkspaceTestClient, run_tests, AssertionFailedError

client = WorkspaceTestClient()

def nonexistent_window_handled():
    """Test that operations on missing windows are handled."""
    result = client.find_element("NONEXISTENT_WINDOW_12345", "test")
    # Should return found=False, not crash
    return result.get('found', True) == False or 'error' in result

def nonexistent_element_handled():
    """Test that operations on missing elements are handled."""
    client.open_about_dialog()
    result = client.find_element("Info", "NONEXISTENT_ELEMENT_12345")
    # Should return found=False, not crash
    return result.get('found', True) == False or 'error' in result

def highlight_missing_window_handled():
    """Test highlighting in missing window doesn't crash."""
    result = client.highlight_failure("MISSING_WINDOW", "text", 1)
    # Should return success=False, not crash
    return 'success' in result

def highlight_missing_element_handled():
    """Test highlighting missing element doesn't crash."""
    client.open_about_dialog()
    result = client.highlight_failure("Info", "MISSING_ELEMENT_TEXT", 1)
    # Should return success=False, not crash
    return 'success' in result

def wait_timeout_handled():
    """Test that timeouts don't cause exceptions."""
    try:
        result = client.wait_for_window("NONEXISTENT_WINDOW", timeout=0.5)
        # Should return without exception
        return True
    except:
        return False

tests = [
    # Missing window handling
    ("Handles nonexistent window gracefully",
     nonexistent_window_handled),
    
    # Missing element handling
    ("Handles nonexistent element gracefully",
     nonexistent_element_handled),
    
    # Highlight errors
    ("Highlight handles missing window",
     highlight_missing_window_handled),
    
    ("Highlight handles missing element",
     highlight_missing_element_handled),
    
    # Timeout handling
    ("Wait timeout doesn't crash",
     wait_timeout_handled),
]

if __name__ == "__main__":
    exit(run_tests(*tests))
