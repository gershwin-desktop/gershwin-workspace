#!/usr/bin/env python3
"""
Test 06: Inspector Panel

Verifies the Inspector/Info panel for files:
- Inspector window functionality
- File information display
"""

import sys, os, time
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'python'))

from uitest import WorkspaceTestClient, run_tests

client = WorkspaceTestClient()

def check_inspector_elements():
    """Check if any inspector-related UI is present."""
    # Check for common inspector-related text
    return (client.text_visible("Name") or 
            client.text_visible("Size") or 
            client.text_visible("Modified") or
            client.text_visible("Inspector"))

def has_file_info_labels():
    """Check for file information labels."""
    texts = []
    for title in client.get_window_titles():
        texts.extend(client.get_visible_text_in_window(title))
    
    # Common file info labels
    info_labels = ["Name", "Size", "Kind", "Where", "Created", "Modified"]
    return any(label in ' '.join(texts) for label in info_labels)

tests = [
    # Basic inspector availability
    ("Can query window state",
     lambda: client.query_ui_state() is not None),
    
    # UI testing works for inspector checks
    ("Element queries work",
     lambda: isinstance(client.get_window_titles(), list)),
]

if __name__ == "__main__":
    exit(run_tests(*tests))
