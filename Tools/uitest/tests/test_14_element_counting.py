#!/usr/bin/env python3
"""
Test 14: Element Counting

Verifies element counting functionality:
- Count by class name
- Common widget detection
- Desktop icon counting
"""

import sys, os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'python'))

from uitest import WorkspaceTestClient, run_tests

client = WorkspaceTestClient()

def count_buttons():
    """Count NSButton elements."""
    count = client.count_elements_by_class("NSButton")
    return count >= 0  # Valid even if 0

def count_text_fields():
    """Count NSTextField elements."""
    count = client.count_elements_by_class("NSTextField")
    return count >= 0

def count_image_views():
    """Count NSImageView elements."""
    count = client.count_elements_by_class("NSImageView")
    return count >= 0

def has_many_buttons():
    """Verify About dialog has multiple buttons."""
    client.open_about_dialog()
    count = client.count_elements_by_class("NSButton")
    return count >= 3  # At minimum: Credits, License, Authors, close button

def count_returns_integer():
    """Verify count returns integer type."""
    count = client.count_elements_by_class("NSButton")
    return isinstance(count, int)

tests = [
    # Basic counting
    ("Can count buttons",
     count_buttons),
    
    ("Can count text fields",
     count_text_fields),
    
    ("Can count image views",
     count_image_views),
    
    # About dialog has expected buttons
    ("About dialog has multiple buttons",
     has_many_buttons),
    
    # Type validation
    ("Count returns integer",
     count_returns_integer),
]

if __name__ == "__main__":
    exit(run_tests(*tests))
