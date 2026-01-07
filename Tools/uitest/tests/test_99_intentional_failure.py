#!/usr/bin/env python3
"""
Test 99: Intentional Failure (Demo)

This test intentionally fails to demonstrate:
- Failure highlighting
- Screenshot capture
- Log file generation
- Error reporting

Use this to verify the failure detection system works.
"""

import sys, os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'python'))

from uitest import WorkspaceTestClient, run_tests

client = WorkspaceTestClient()

# Open About dialog for visible failure
client.open_about_dialog()

def always_fails():
    """This test always fails for demonstration."""
    return False

def fails_with_missing_element():
    """Fails because element doesn't exist."""
    return client.text_visible("THIS_TEXT_DOES_NOT_EXIST_12345")

tests = [
    # Intentional failures
    ("DEMO: This test always fails",
     always_fails),
    
    ("DEMO: Missing element fails",
     fails_with_missing_element),
]

if __name__ == "__main__":
    print("\n" + "="*60)
    print("NOTE: These tests are EXPECTED to fail!")
    print("They demonstrate the failure detection and highlighting.")
    print("="*60 + "\n")
    exit(run_tests(*tests))
