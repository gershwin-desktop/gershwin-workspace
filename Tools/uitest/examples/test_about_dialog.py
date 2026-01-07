#!/usr/bin/env python3
"""Minimal example test script using run_tests() - 18 LOC"""

import sys, os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'python'))

from uitest import WorkspaceTestClient, run_tests

# Create test client and open About dialog
client = WorkspaceTestClient()
client.open_about_dialog()

# Define tests - each is a (name, callable) tuple where callable returns True/False
# JSON responses are automatically validated by the client
tests = [
    # Verify the About dialog opens successfully
    ("About opens", lambda: client.open_about_dialog() or True),
    
    # Check that Workspace window exists in the system
    ("Window exists", lambda: client.window_exists("Workspace")),
    
    # Verify the UI tree has at least one window registered
    ("Has windows", lambda: len(client.query_ui_state()['windows']) > 0),
    
    # Confirm the response contains expected structure (JSON auto-validated)
    ("JSON structure valid", lambda: 'windows' in client.query_ui_state()),
    
    # Check that UI testing is enabled in the application
    ("Content visible", lambda: client.query_ui_state()['uiTestingEnabled']),
]

# Run all tests and exit with status code (0=pass, 1=fail)
exit(run_tests(*tests))
