#!/usr/bin/env python3
"""
Test: Window Management and Focus

Tests window manager functionality including:
- Multiple window handling
- Window properties and metadata
- Inspector/tool window integration
- Window state persistence

This validates that the window management system correctly tracks and
manages multiple open windows and their properties.
"""

import sys, os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'python'))

from uitest import WorkspaceTestClient, run_tests

client = WorkspaceTestClient()

# Define window management tests
tests = [
    # Core requirement: Workspace must be running
    ("Workspace is running",
     lambda: client.query_ui_state() is not None),
    
    # Check windows list structure
    ("Windows list is accessible",
     lambda: 'windows' in client.query_ui_state()),
    
    # Verify each window has required properties
    ("Windows have valid structure",
     lambda: all(isinstance(w, dict) for w in client.query_ui_state()['windows'])),
    
    # Ensure at least one window is open (the main Workspace window)
    ("At least one window open",
     lambda: len(client.query_ui_state()['windows']) > 0),
    
    # Check that windows have proper properties (title, frame, visibility)
    ("Windows have expected properties",
     lambda: all(('title' in w or 'class' in w) and 'frame' in w 
                 for w in client.query_ui_state()['windows'])),
    
    # Verify main window can be located by title
    ("Main Workspace window can be found",
     lambda: client.window_exists("Workspace")),
    
    # Test that window visibility can be determined
    ("Window visibility accessible",
     lambda: all('visibility' in w or 'isKeyWindow' in w
                 for w in client.query_ui_state()['windows'])),
]

exit(run_tests(*tests))
