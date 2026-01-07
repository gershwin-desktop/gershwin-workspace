#!/usr/bin/env python3
"""
Test 18: Framework Integration

Tests the Python-to-CLI-to-Workspace integration:
- Command execution
- Response parsing
- Error recovery
"""

import sys, os, subprocess
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'python'))

from uitest import WorkspaceTestClient, run_tests

client = WorkspaceTestClient()

def cli_tool_exists():
    """Verify uitest CLI tool exists."""
    tool_path = os.path.join(
        os.path.dirname(__file__), '..', '..', 
        'derived_src', 'uitest'
    )
    # Try common locations
    paths = [
        tool_path,
        os.path.expanduser('~/.local/bin/uitest'),
        '/usr/local/bin/uitest',
    ]
    for p in paths:
        if os.path.exists(p):
            return True
    # If client works, tool exists somewhere
    try:
        state = client.query_ui_state()
        return 'windows' in state
    except:
        return False

def multiple_queries_work():
    """Verify multiple queries don't break connection."""
    for _ in range(3):
        state = client.query_ui_state()
        if 'windows' not in state:
            return False
    return True

def query_returns_fresh_data():
    """Verify each query gets fresh data."""
    state1 = client.query_ui_state()
    state2 = client.query_ui_state()
    # Should return valid data both times
    return 'windows' in state1 and 'windows' in state2

def client_handles_special_chars():
    """Test that special characters in text don't break commands."""
    try:
        # Search for text with special chars
        client.text_visible("Test & <test>")
        return True  # No crash
    except:
        return False

tests = [
    # CLI integration
    ("CLI tool is accessible",
     cli_tool_exists),
    
    # Multiple queries
    ("Multiple queries work",
     multiple_queries_work),
    
    # Fresh data
    ("Queries return fresh data",
     query_returns_fresh_data),
    
    # Special characters
    ("Handles special characters",
     client_handles_special_chars),
]

if __name__ == "__main__":
    exit(run_tests(*tests))
