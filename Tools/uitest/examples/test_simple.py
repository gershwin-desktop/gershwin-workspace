#!/usr/bin/env python3
"""Simple test to check query works"""
import sys, os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'python'))

from uitest import WorkspaceTestClient

client = WorkspaceTestClient()

# Test 1: Query works
print("Testing query...")
try:
    state = client.query_ui_state()
    print(f"✓ Query works - found {len(state.get('windows', []))} windows")
except Exception as e:
    print(f"✗ Query failed: {e}")
    sys.exit(1)

# Test 2: About dialog
print("Testing about dialog...")
try:
    client.open_about_dialog()
    print("✓ About dialog opened")
except Exception as e:
    print(f"✗ About dialog failed: {e}")
    sys.exit(1)

print("\n✓ All basic tests passed!")
sys.exit(0)
