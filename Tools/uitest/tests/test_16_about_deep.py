#!/usr/bin/env python3
"""
Test 16: About Dialog Comprehensive

Deep dive into About dialog structure and content:
- Multiple tabs: Credits, Authors, License
- Theme information
- Version display
"""

import sys, os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'python'))

from uitest import WorkspaceTestClient, run_tests

client = WorkspaceTestClient()

# Open About dialog for all tests
client.open_about_dialog()

def has_workspace_title():
    """Verify 'Workspace' title is displayed."""
    return client.text_visible("Workspace")

def has_version():
    """Verify version is displayed."""
    return client.text_visible("Version")

def has_theme_info():
    """Check for theme-related text."""
    # Look for theme button or label
    return (client.text_visible("Theme:") or 
            client.text_visible("Eau") or
            client.text_visible("theme"))

def has_credits_button():
    """Verify Credits button exists."""
    result = client.find_element("Info", "Credits")
    return result.get('found', False)

def has_authors_button():
    """Verify Authors button exists."""
    result = client.find_element("Info", "Authors")
    return result.get('found', False)

def has_license_button():
    """Verify License button exists."""
    result = client.find_element("Info", "License")
    return result.get('found', False)

def has_app_icon():
    """Verify app icon image view exists."""
    count = client.count_elements_by_class("NSImageView")
    return count >= 1  # At least one image (app icon)

def info_window_correct_class():
    """Verify Info panel uses correct class."""
    state = client.query_ui_state()
    for w in state.get('windows', []):
        if w.get('title') == 'Info':
            cls = w.get('class', '')
            return cls in ['NSPanel', 'NSWindow', 'GWAboutPanel']
    return False

tests = [
    # Title and version
    ("Shows 'Workspace' title",
     has_workspace_title),
    
    ("Shows version",
     has_version),
    
    # Buttons
    ("Has Credits button",
     has_credits_button),
    
    ("Has Authors button",
     has_authors_button),
    
    ("Has License button",
     has_license_button),
    
    # Visual elements
    ("Has app icon",
     has_app_icon),
    
    # Theme info
    ("Has theme information",
     has_theme_info),
    
    # Window class
    ("Info panel uses correct window class",
     info_window_correct_class),
]

if __name__ == "__main__":
    exit(run_tests(*tests))
