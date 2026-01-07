#!/usr/bin/env python3
"""
Interactive Test Suite - Menu Operations

Tests menu accessibility and operations:
- Main menu items
- File menu
- Edit menu
- View menu
- Go menu
"""

import sys, os, time
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'python'))

from uitest import WorkspaceTestClient, run_tests

client = WorkspaceTestClient()

def test_about_menu():
    """Open About dialog via menu simulation."""
    client.open_about_dialog()
    return client.window_exists("Info")

def test_about_shows_workspace():
    """About dialog shows Workspace title."""
    return client.text_visible("Workspace")

def test_about_shows_version():
    """About dialog shows version info."""
    texts = client.get_visible_text_in_window("Info")
    for t in texts:
        if "Release:" in t or "Version" in t or "20" in t:  # Year in version
            return True
    return False

def test_about_shows_authors():
    """About dialog shows authors."""
    return client.text_visible("Authors:")

def test_about_shows_license():
    """About dialog shows license info."""
    texts = client.get_visible_text_in_window("Info")
    for t in texts:
        if "GPL" in t or "GNU" in t or "License" in t:
            return True
    return False

def test_about_shows_theme():
    """About dialog shows current theme."""
    return client.text_visible("Current theme:")

def test_about_has_buttons():
    """About dialog has action buttons."""
    # Look for Credits/Authors/License buttons
    buttons = client.count_elements_by_class("NSButton")
    return buttons >= 1

def test_preferences_visible():
    """Check if Preferences window can be detected."""
    # Preferences may already be cached
    titles = client.get_window_titles()
    return "Workspace Preferences" in titles

def test_finder_available():
    """Check if Finder window is available."""
    titles = client.get_window_titles()
    return "Finder" in titles

def test_run_panel_available():
    """Check if Run panel is available."""
    titles = client.get_window_titles()
    return "Run" in titles

def test_open_with_available():
    """Check if Open With panel is available."""
    titles = client.get_window_titles()
    return "Open With" in titles

tests = [
    # About dialog tests
    ("About dialog opens",
     test_about_menu),
    
    ("About shows Workspace title",
     test_about_shows_workspace),
    
    ("About shows version info",
     test_about_shows_version),
    
    ("About shows authors",
     test_about_shows_authors),
    
    ("About shows license",
     test_about_shows_license),
    
    ("About shows theme",
     test_about_shows_theme),
    
    ("About has buttons",
     test_about_has_buttons),
    
    # Panel availability
    ("Preferences panel available",
     test_preferences_visible),
    
    ("Finder panel available",
     test_finder_available),
    
    ("Run panel available",
     test_run_panel_available),
    
    ("Open With panel available",
     test_open_with_available),
]

if __name__ == "__main__":
    print("\n" + "="*60)
    print("MENU OPERATIONS TEST")
    print("="*60 + "\n")
    exit(run_tests(*tests))
