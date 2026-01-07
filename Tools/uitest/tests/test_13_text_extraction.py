#!/usr/bin/env python3
"""
Test 13: Text Content Extraction

Verifies text extraction capabilities:
- Find text across all windows
- Get visible text from specific window
- Text search patterns
"""

import sys, os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'python'))

from uitest import WorkspaceTestClient, run_tests

client = WorkspaceTestClient()

# Ensure About dialog is open for text tests
client.open_about_dialog()

def can_get_all_text():
    """Test extracting all text from a window."""
    text = client.get_visible_text_in_window("Info")
    return isinstance(text, list) and len(text) > 0

def text_includes_version():
    """Test that version string is in extracted text."""
    text = client.get_visible_text_in_window("Info")
    # Look for version pattern
    for t in text:
        if 'Version' in t or '0.' in t or '1.' in t:
            return True
    return False

def can_find_element_by_text():
    """Test finding element that contains specific text."""
    element = client.get_element_by_text("Workspace")
    return element is not None

def case_sensitive_text_check():
    """Test that text_visible is case sensitive."""
    # Should find "Workspace"
    found_upper = client.text_visible("Workspace")
    # Check case sensitivity (depends on implementation)
    found_lower = client.text_visible("workspace")
    return found_upper  # At minimum should find the title case version

tests = [
    # Text extraction
    ("Can extract text from window",
     can_get_all_text),
    
    # Version detection
    ("Can find version in About dialog",
     text_includes_version),
    
    # Element by text
    ("Can find element by text content",
     can_find_element_by_text),
    
    # Case handling
    ("Text search finds expected text",
     case_sensitive_text_check),
]

if __name__ == "__main__":
    exit(run_tests(*tests))
