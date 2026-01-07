#!/usr/bin/env python3
"""
Test 00: Connection and Basic Functionality

Verifies that:
- Workspace is running with debug mode
- UI testing protocol is enabled
- Basic queries work correctly
"""

import sys, os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'python'))

from uitest import WorkspaceTestClient, run_tests

client = WorkspaceTestClient()

tests = [
    # Core connectivity
    ("Workspace is running",
     lambda: client.is_workspace_running()),
    
    ("UI state can be queried",
     lambda: client.query_ui_state() is not None),
    
    ("UI testing is enabled",
     lambda: client.query_ui_state().get('uiTestingEnabled', False)),
    
    # Basic window management
    ("Windows list exists",
     lambda: 'windows' in client.query_ui_state()),
    
    ("At least one window exists",
     lambda: len(client.query_ui_state().get('windows', [])) > 0),
    
    ("Can get visible windows",
     lambda: isinstance(client.get_visible_windows(), list)),
    
    ("Can get window titles",
     lambda: isinstance(client.get_window_titles(), list)),
]

if __name__ == "__main__":
    exit(run_tests(*tests))
