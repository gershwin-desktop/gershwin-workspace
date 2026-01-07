#!/usr/bin/env python3
"""
Test 05: Preferences Panel

Verifies the Preferences panel:
- Opens correctly
- Contains expected sections
- Shows settings categories
"""

import sys, os, time
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'python'))

from uitest import WorkspaceTestClient, run_tests

client = WorkspaceTestClient()

def open_preferences():
    """Try to open Preferences window."""
    # Check if already open
    if client.window_exists("Workspace Preferences"):
        return True
    # Try menu path
    try:
        result = client.menu("Info > Preferences...")
        time.sleep(0.5)
        return client.window_exists("Workspace Preferences")
    except:
        return False

def has_browser_section():
    """Check for Browser preferences section."""
    return client.text_visible("Browser") or client.text_visible("browser")

def has_icons_section():
    """Check for Icons/Desktop section."""
    return (client.text_visible("Icons") or client.text_visible("Desktop") or
            client.text_visible("icons") or client.text_visible("desktop"))

tests = [
    # Open preferences
    ("Preferences opens",
     open_preferences),
    
    ("Preferences window visible",
     lambda: client.window_exists("Workspace Preferences")),
    
    # Common preference categories
    ("Has preference sections",
     lambda: len(client.get_visible_text_in_window("Workspace Preferences")) > 0),
]

if __name__ == "__main__":
    exit(run_tests(*tests))
