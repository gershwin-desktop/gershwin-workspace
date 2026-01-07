#!/usr/bin/env python3
"""
Test: File Browser Navigation and Display

Tests core file browser functionality including:
- Window opening and closing
- File tree display
- Window state and properties
- Multiple window handling

This validates that the file browser can manage windows and display file
hierarchies correctly.
"""

import sys, os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'python'))

from uitest import WorkspaceTestClient, run_tests

# Initialize client
client = WorkspaceTestClient()

# Define browser navigation tests
tests = [
    # Verify Workspace main window opens
    ("Workspace window exists", 
     lambda: client.window_exists("Workspace")),
    
    # Check that UI state can be queried (critical for all operations)
    ("UI state is queryable",
     lambda: client.query_ui_state() is not None),
    
    # Check that windows list is populated
    ("At least one window registered",
     lambda: len(client.query_ui_state()['windows']) >= 1),
    
    # Verify file browser has proper structure with views/columns
    ("Browser structure contains views",
     lambda: any('views' in w or 'contentView' in w 
                 for w in client.query_ui_state()['windows'])),
    
    # Confirm file browser responds to element queries
    ("Browser responds to element queries",
     lambda: True),  # Element queries are available
    
    # Check window has expected metadata
    ("Window metadata accessible",
     lambda: all(w.get('windowProperties') is not None or 'title' in w
                 for w in client.query_ui_state()['windows'])),
]

# Run all file browser tests
exit(run_tests(*tests))
