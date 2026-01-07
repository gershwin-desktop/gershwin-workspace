#!/usr/bin/env python3
"""
Minimal test template - copy and adapt this for your own tests!

Just define your test cases as (name, lambda) tuples and run_tests() handles
the rest. That's it! JSON responses are automatically validated by the client.
"""

import sys, os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'python'))

from uitest import WorkspaceTestClient, run_tests

client = WorkspaceTestClient()

# Add your setup here if needed
# client.open_about_dialog()

exit(run_tests(
    # Format: ("Test name", lambda: expression_that_returns_truthy_or_raises)
    # ✓ = test passes (returns True or doesn't raise exception)
    # ✗ = test fails (returns False or raises exception)
    
    ("Example test 1", lambda: True),
    ("Example test 2", lambda: 1 + 1 == 2),
    ("Example test 3", lambda: len(client.query_ui_state()['windows']) > 0),
))
