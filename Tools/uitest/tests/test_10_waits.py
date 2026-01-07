#!/usr/bin/env python3
"""
Test 10: Wait Functions

Verifies timing and wait functionality:
- Wait for window
- Wait for text
- Wait for window close
- Timeout handling
"""

import sys, os, time
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'python'))

from uitest import WorkspaceTestClient, run_tests

client = WorkspaceTestClient()

# Ensure About dialog is open
client.open_about_dialog()

def test_wait_for_text():
    """Test waiting for text that already exists."""
    # "Workspace" should already be visible
    return client.wait_for_text("Workspace", timeout=2.0)

def test_wait_for_missing_text_times_out():
    """Test that waiting for nonexistent text times out properly."""
    start = time.time()
    result = client.wait_for_text("NONEXISTENT_TEXT_12345", timeout=1.0)
    elapsed = time.time() - start
    # Should have taken at least 1 second (the timeout)
    return result == False and elapsed >= 0.9

def test_wait_for_existing_window():
    """Test waiting for window that exists."""
    result = client.wait_for_window("Info", timeout=2.0)
    return result.get('success', False)

tests = [
    # Wait for existing text
    ("wait_for_text finds existing text",
     test_wait_for_text),
    
    # Wait times out properly
    ("wait_for_text times out for missing text",
     test_wait_for_missing_text_times_out),
    
    # Wait for window
    ("wait_for_window finds existing window",
     test_wait_for_existing_window),
]

if __name__ == "__main__":
    exit(run_tests(*tests))
