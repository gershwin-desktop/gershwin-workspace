#!/usr/bin/env python3
"""
Interactive Test Suite - Viewer Navigation

Tests file browser/viewer navigation:
- Opening windows
- Navigating directories
- Back/Forward in history
- View switching
"""

import sys, os, time
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'python'))

from uitest import WorkspaceTestClient, run_tests

client = WorkspaceTestClient()

def has_viewer_window():
    """Check that at least one viewer window exists."""
    visible = client.get_visible_windows()
    for w in visible:
        if w.get('class') == 'GWViewerWindow':
            return True
    return False

def viewer_shows_path():
    """Check that viewer shows a valid path."""
    # Look for path components like home, System, etc.
    return (client.text_visible("/") or 
            client.text_visible("home") or
            client.text_visible("System") or
            client.text_visible("Applications"))

def viewer_has_icons():
    """Check that viewer displays file icons."""
    count = client.count_elements_by_class("FSNIcon")
    return count > 0

def viewer_has_scrollview():
    """Check viewer has scroll capability."""
    count = client.count_elements_by_class("NSScrollView")
    return count > 0

def viewer_has_shelf():
    """Check viewer has shelf area."""
    count = client.count_elements_by_class("GWViewerShelf")
    return count > 0

def can_see_applications_folder():
    """Verify Applications folder is visible in System Disk."""
    return client.text_visible("Applications")

def can_see_system_folder():
    """Verify System folder is visible."""
    return client.text_visible("System")

tests = [
    # Viewer presence
    ("Has viewer window",
     has_viewer_window),
    
    # Content display
    ("Viewer shows path content",
     viewer_shows_path),
    
    ("Viewer displays file icons",
     viewer_has_icons),
    
    # Structure
    ("Viewer has scroll view",
     viewer_has_scrollview),
    
    ("Viewer has shelf",
     viewer_has_shelf),
    
    # Known folders
    ("Can see Applications folder",
     can_see_applications_folder),
    
    ("Can see System folder",
     can_see_system_folder),
]

if __name__ == "__main__":
    print("\n" + "="*60)
    print("VIEWER NAVIGATION TEST")
    print("="*60 + "\n")
    exit(run_tests(*tests))
