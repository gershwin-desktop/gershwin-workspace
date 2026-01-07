#!/usr/bin/env python3
"""
Run All Interactive Tests

This script runs all interactive test suites in order.
Each suite tests a different aspect of the Workspace UI
using simulated mouse and keyboard input.

Tests are designed to:
- Move the mouse smoothly like a human
- Click on actual UI elements
- Use keyboard shortcuts
- Verify UI state through the testing framework

IMPORTANT: Make sure Workspace is running with -d flag:
    /System/Applications/Workspace.app/Workspace -d
"""

import sys
import os
import subprocess
import time

# Add python directory to path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'python'))

from uitest import WorkspaceTestClient

# Test suites in order
TEST_SUITES = [
    ('test_40_interactive_menus.py', 'Menu System'),
    ('test_41_interactive_navigation.py', 'Navigation'),
    ('test_42_interactive_viewer.py', 'Viewer Windows'),
    ('test_43_interactive_edit.py', 'Edit Operations'),
    ('test_44_interactive_info.py', 'Info Panel'),
    ('test_45_interactive_finder.py', 'Finder'),
    ('test_46_interactive_preferences.py', 'Preferences'),
    ('test_47_interactive_desktop.py', 'Desktop'),
]


def check_workspace_running():
    """Check if Workspace is running and responding."""
    try:
        client = WorkspaceTestClient()
        return client.is_workspace_running()
    except:
        return False


def run_test_suite(script_path, suite_name):
    """Run a single test suite."""
    print(f"\n{'='*60}")
    print(f"  {suite_name.upper()}")
    print(f"{'='*60}")
    
    result = subprocess.run(
        [sys.executable, script_path],
        cwd=os.path.dirname(script_path)
    )
    
    return result.returncode == 0


def main():
    print("\n" + "="*70)
    print("  WORKSPACE INTERACTIVE TEST SUITE")
    print("  Complete UI testing with simulated user input")
    print("="*70)
    
    # Check if Workspace is running
    print("\nChecking Workspace connection...")
    if not check_workspace_running():
        print("\n❌ ERROR: Workspace is not running or not responding.")
        print("\nPlease start Workspace with the debug flag:")
        print("    /System/Applications/Workspace.app/Workspace -d")
        print()
        return 1
    
    print("✓ Workspace is running and responding\n")
    
    # Get script directory
    script_dir = os.path.dirname(os.path.abspath(__file__))
    
    # Run each test suite
    results = []
    for script, name in TEST_SUITES:
        script_path = os.path.join(script_dir, script)
        
        if not os.path.exists(script_path):
            print(f"\n⚠ Skipping {name}: {script} not found")
            continue
        
        passed = run_test_suite(script_path, name)
        results.append((name, passed))
        
        # Brief pause between suites
        time.sleep(0.5)
    
    # Summary
    print("\n" + "="*70)
    print("  SUMMARY")
    print("="*70 + "\n")
    
    passed = 0
    failed = 0
    
    for name, result in results:
        status = "✓ PASSED" if result else "✗ FAILED"
        print(f"  {name:30} {status}")
        if result:
            passed += 1
        else:
            failed += 1
    
    print()
    print(f"  Total: {passed + failed} suites")
    print(f"  Passed: {passed}")
    print(f"  Failed: {failed}")
    print()
    
    if failed == 0:
        print("  ✓ ALL TESTS PASSED")
    else:
        print(f"  ✗ {failed} SUITE(S) FAILED")
    
    print()
    
    return 0 if failed == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
