#!/usr/bin/env python3
"""
Workspace UI Test Suite Runner

Runs all test files in order and provides summary.

Usage:
    ./run_all_tests.py           # Run all tests
    ./run_all_tests.py -v        # Verbose mode
    ./run_all_tests.py --quick   # Skip slow tests
    ./run_all_tests.py test_00   # Run only matching tests
"""

import os
import sys
import glob
import subprocess
import time
from datetime import datetime

# Configuration
TEST_DIR = os.path.dirname(os.path.abspath(__file__))
SKIP_INTENTIONAL_FAILURES = True  # Skip test_99 by default

def get_test_files(pattern=None):
    """Get all test files in order."""
    test_files = sorted(glob.glob(os.path.join(TEST_DIR, "test_*.py")))
    
    # Filter out the runner itself
    test_files = [f for f in test_files if 'run_all' not in f]
    
    # Skip intentional failure tests unless specifically requested
    if SKIP_INTENTIONAL_FAILURES:
        test_files = [f for f in test_files if 'test_99' not in f]
    
    # Apply pattern filter if specified
    if pattern:
        test_files = [f for f in test_files if pattern in os.path.basename(f)]
    
    return test_files

def run_test_file(filepath, verbose=False):
    """Run a single test file and return results."""
    filename = os.path.basename(filepath)
    
    start_time = time.time()
    
    try:
        result = subprocess.run(
            [sys.executable, filepath],
            capture_output=True,
            text=True,
            timeout=60  # 60 second timeout per file
        )
        elapsed = time.time() - start_time
        
        return {
            'file': filename,
            'returncode': result.returncode,
            'stdout': result.stdout,
            'stderr': result.stderr,
            'elapsed': elapsed,
            'success': result.returncode == 0,
        }
    except subprocess.TimeoutExpired:
        return {
            'file': filename,
            'returncode': -1,
            'stdout': '',
            'stderr': 'TIMEOUT: Test exceeded 60 seconds',
            'elapsed': 60,
            'success': False,
        }
    except Exception as e:
        return {
            'file': filename,
            'returncode': -1,
            'stdout': '',
            'stderr': str(e),
            'elapsed': 0,
            'success': False,
        }

def print_summary(results):
    """Print test summary."""
    total = len(results)
    passed = sum(1 for r in results if r['success'])
    failed = total - passed
    total_time = sum(r['elapsed'] for r in results)
    
    print("\n" + "="*70)
    print("TEST SUITE SUMMARY")
    print("="*70)
    print(f"  Total:  {total} test files")
    print(f"  Passed: {passed} ✓")
    print(f"  Failed: {failed} ✗")
    print(f"  Time:   {total_time:.2f}s")
    print("="*70)
    
    if failed > 0:
        print("\nFAILED TESTS:")
        for r in results:
            if not r['success']:
                print(f"  ✗ {r['file']}")
                # Show first error line
                for line in r['stdout'].split('\n'):
                    if 'FAILED' in line or 'Error' in line:
                        print(f"    {line.strip()}")
                        break
    
    print()
    return 0 if failed == 0 else 1

def main():
    """Main entry point."""
    verbose = '-v' in sys.argv or '--verbose' in sys.argv
    
    # Check for pattern filter
    pattern = None
    for arg in sys.argv[1:]:
        if not arg.startswith('-'):
            pattern = arg
            break
    
    # Allow intentional failures if explicitly specified
    global SKIP_INTENTIONAL_FAILURES
    if pattern and '99' in pattern:
        SKIP_INTENTIONAL_FAILURES = False
    if '--all' in sys.argv:
        SKIP_INTENTIONAL_FAILURES = False
    
    test_files = get_test_files(pattern)
    
    if not test_files:
        print("No test files found!")
        return 1
    
    print(f"\n{'='*70}")
    print(f"WORKSPACE UI TEST SUITE")
    print(f"Started: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print(f"{'='*70}")
    print(f"Running {len(test_files)} test files...\n")
    
    results = []
    
    for filepath in test_files:
        filename = os.path.basename(filepath)
        
        # Extract description from docstring
        desc = ""
        try:
            with open(filepath) as f:
                content = f.read()
                if '"""' in content:
                    desc = content.split('"""')[1].strip().split('\n')[0]
        except:
            pass
        
        print(f"Running: {filename}", end="")
        if verbose and desc:
            print(f" - {desc}", end="")
        print(" ... ", end="", flush=True)
        
        result = run_test_file(filepath, verbose)
        results.append(result)
        
        if result['success']:
            print(f"✓ ({result['elapsed']:.1f}s)")
        else:
            print(f"✗ FAILED ({result['elapsed']:.1f}s)")
            if verbose:
                # Show output on failure
                for line in result['stdout'].split('\n'):
                    if line.strip():
                        print(f"    {line}")
    
    return print_summary(results)

if __name__ == "__main__":
    sys.exit(main())
