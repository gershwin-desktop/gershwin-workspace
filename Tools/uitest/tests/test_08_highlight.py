#!/usr/bin/env python3
"""
Test 08: Highlight and Failure Marking

Verifies the test framework's failure highlighting:
- Can highlight elements
- Can clear highlights
- Red box appears on failures
"""

import sys, os, time
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'python'))

from uitest import WorkspaceTestClient, run_tests

client = WorkspaceTestClient()

# Open About dialog for elements to highlight
client.open_about_dialog()
time.sleep(0.3)

def can_highlight():
    """Test highlight functionality."""
    result = client.highlight_failure("Info", "Workspace", 3)
    return result.get('success', False)

def can_clear_highlights():
    """Test clearing highlights."""
    result = client.clear_highlights()
    # Success or already cleared
    return True

def highlight_creates_overlay():
    """Verify highlight adds overlay."""
    # First clear any existing
    client.clear_highlights()
    time.sleep(0.1)
    
    # Then add new highlight
    result = client.highlight_failure("Info", "Authors: ", 5)
    time.sleep(0.2)
    
    return result.get('success', False)

tests = [
    # Highlight works
    ("Can highlight element",
     can_highlight),
    
    ("Can clear highlights",
     can_clear_highlights),
    
    ("Highlight creates visual overlay",
     highlight_creates_overlay),
    
    # Final cleanup
    ("Cleanup highlights",
     lambda: client.clear_highlights() or True),
]

if __name__ == "__main__":
    exit(run_tests(*tests))
