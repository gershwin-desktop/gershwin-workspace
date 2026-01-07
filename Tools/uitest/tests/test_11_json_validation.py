#!/usr/bin/env python3
"""
Test 11: JSON Response Validation

Verifies that all JSON responses are properly structured:
- Valid JSON format
- Required fields present
- Correct data types
"""

import sys, os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'python'))

from uitest import WorkspaceTestClient, run_tests

client = WorkspaceTestClient()

def validate_ui_state_structure():
    """Verify UI state has expected top-level structure."""
    state = client.query_ui_state()
    
    # Must have windows array
    if 'windows' not in state:
        return False
    if not isinstance(state['windows'], list):
        return False
    
    # Must have uiTestingEnabled flag
    if 'uiTestingEnabled' not in state:
        return False
    
    return True

def validate_window_structure():
    """Verify each window has expected fields."""
    state = client.query_ui_state()
    windows = state.get('windows', [])
    
    for w in windows:
        # Must have class
        if 'class' not in w:
            return False
        # Must have title
        if 'title' not in w:
            return False
        # Must have frame
        if 'frame' not in w:
            return False
    
    return True

def validate_frame_structure():
    """Verify frame objects have required fields."""
    state = client.query_ui_state()
    windows = state.get('windows', [])
    
    for w in windows:
        frame = w.get('frame', {})
        required = ['x', 'y', 'width', 'height']
        for field in required:
            if field not in frame:
                return False
            if not isinstance(frame[field], (int, float)):
                return False
    
    return True

def validate_highlight_response():
    """Verify highlight command returns proper response."""
    client.open_about_dialog()
    result = client.highlight_failure("Info", "Workspace", 2)
    
    # Must have success field
    if 'success' not in result:
        return False
    if not isinstance(result['success'], bool):
        return False
    
    return True

tests = [
    # Top-level structure
    ("UI state has correct structure",
     validate_ui_state_structure),
    
    # Window structure
    ("Windows have required fields",
     validate_window_structure),
    
    # Frame structure
    ("Frames have x/y/width/height",
     validate_frame_structure),
    
    # Command responses
    ("Highlight response is valid",
     validate_highlight_response),
]

if __name__ == "__main__":
    exit(run_tests(*tests))
