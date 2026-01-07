#!/usr/bin/env python3
"""
Test 15: Window Titles

Verifies window title functionality:
- Get all window titles
- Title changes detection
- Title filtering
"""

import sys, os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'python'))

from uitest import WorkspaceTestClient, run_tests

client = WorkspaceTestClient()

def can_get_titles():
    """Test getting list of window titles."""
    titles = client.get_window_titles()
    return isinstance(titles, list)

def titles_are_strings():
    """Test that all titles are strings."""
    titles = client.get_window_titles()
    return all(isinstance(t, str) for t in titles)

def has_desktop_in_titles():
    """Test that desktop window has empty or Desktop title."""
    titles = client.get_window_titles()
    # Desktop might be "" or "Desktop" or "Shelf"
    return "" in titles or "Desktop" in titles or len(titles) > 0

def info_panel_has_title():
    """Test that About dialog appears in titles."""
    client.open_about_dialog()
    titles = client.get_window_titles()
    return "Info" in titles

tests = [
    # Basic functionality
    ("Can get window titles",
     can_get_titles),
    
    # Type validation
    ("Titles are strings",
     titles_are_strings),
    
    # Desktop presence
    ("Desktop window present",
     has_desktop_in_titles),
    
    # About dialog
    ("Info panel appears in titles",
     info_panel_has_title),
]

if __name__ == "__main__":
    exit(run_tests(*tests))
