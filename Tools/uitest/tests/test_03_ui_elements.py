#!/usr/bin/env python3
"""
Test 03: UI Elements and Widgets

Verifies UI widget presence and functionality:
- NSButton presence
- NSTextField presence
- NSScrollView presence
- Element counting
- Element text extraction
"""

import sys, os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'python'))

from uitest import WorkspaceTestClient, run_tests

client = WorkspaceTestClient()

# Open About dialog to ensure we have widgets to test
client.open_about_dialog()

tests = [
    # Common widget types exist
    ("Has NSButton widgets",
     lambda: client.count_elements_by_class("NSButton") > 0),
    
    ("Has NSTextField widgets",
     lambda: client.count_elements_by_class("NSTextField") > 0),
    
    ("Has NSView widgets",
     lambda: client.count_elements_by_class("NSView") > 0),
    
    # Text content extraction
    ("Can extract text from Info window",
     lambda: len(client.get_visible_text_in_window("Info")) > 0),
    
    # Element by text search
    ("Can find element by text 'Workspace'",
     lambda: client.get_element_by_text("Workspace") is not None),
    
    ("Can find element by text 'Authors'",
     lambda: client.get_element_by_text("Authors: ") is not None),
    
    # Text visibility check
    ("text_visible works correctly",
     lambda: client.text_visible("Workspace")),
    
    ("Case-insensitive search works",
     lambda: client.text_visible("workspace", case_sensitive=False)),
]

if __name__ == "__main__":
    exit(run_tests(*tests))
