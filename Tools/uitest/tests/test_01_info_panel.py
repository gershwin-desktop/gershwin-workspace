#!/usr/bin/env python3
"""
Test 01: Info Panel (About Dialog)

Verifies the Workspace Info panel:
- Opens correctly via menu/shortcut
- Shows correct version information
- Shows author credits
- Shows license information
- Shows current theme
"""

import sys, os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'python'))

from uitest import WorkspaceTestClient, run_tests

client = WorkspaceTestClient()

# First, open the About dialog
client.open_about_dialog()

tests = [
    # Panel opens
    ("Info panel opens",
     lambda: client.window_exists("Info")),
    
    # Application name shown
    ("Shows 'Workspace' title",
     lambda: client.text_visible("Workspace")),
    
    # Tagline
    ("Shows desktop experience text",
     lambda: client.text_visible("Desktop Experience")),
    
    # Version information
    ("Shows release version",
     lambda: client.text_visible("Release")),
    
    # Author credits
    ("Shows Authors section",
     lambda: client.text_visible("Authors")),
    
    # Copyright notice
    ("Shows copyright notice",
     lambda: client.text_visible("Copyright")),
    
    # License information
    ("Shows GPL license",
     lambda: client.text_visible("GPL") or client.text_visible("General Public License")),
    
    # Theme information
    ("Shows current theme",
     lambda: client.text_visible("Current theme")),
]

if __name__ == "__main__":
    exit(run_tests(*tests))
