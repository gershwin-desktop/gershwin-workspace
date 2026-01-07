#!/usr/bin/env python3
"""
INTENTIONAL FAILURE TEST - Demonstrates red highlighting on test failure.

This test INTENTIONALLY FAILS to demonstrate the failure highlighting feature.

The test will:
1. Open the About dialog
2. Look for "Current Theme: GNUstep" in the About window
3. If the theme text shows something DIFFERENT, the test FAILS
4. The offending text label gets highlighted in RED on the actual UI
5. Test execution STOPS at the first failure

You will visually SEE the red highlight appear on the screen where the
text mismatch occurred.

Run with: python3 test_intentional_failure.py

Expected behavior:
- The About dialog opens
- Tests look for "Current Theme: GNUstep"
- If text is different (e.g., "Current Theme: Eau"), the element turns RED
- Test stops with failure message
"""

import sys, os, time
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'python'))

from uitest import WorkspaceTestClient, run_interactive_tests

# Create test client
client = WorkspaceTestClient()

# Clear any previous highlight overlays (skip for now - command has issues)
# client.clear_highlights()


def test_open_about_dialog():
    """Open the About dialog to check theme info."""
    result = client.menu("Info > About")
    return result.get('success', False)


def test_about_window_visible():
    """Wait for About window to appear."""
    result = client.wait_for_window("About", timeout=3.0)
    return result.get('success', False)


def test_check_theme_gnustep():
    """
    INTENTIONAL FAILURE TEST
    
    Check if the About box contains 'Current Theme: GNUstep'.
    If the theme is something else (e.g., 'Current Theme: Eau'),
    the test will FAIL and highlight that text in RED.
    """
    expected_theme = "Current Theme: GNUstep"
    
    # First, try to find any theme text in the About window
    state = client.query_ui_state()
    
    # Look through all windows for About
    for window in state.get('windows', []):
        if 'About' in window.get('title', ''):
            # Search through the view hierarchy for theme text
            def find_theme_text(view, depth=0):
                """Recursively search for theme text in view hierarchy."""
                text = view.get('text', '') or view.get('stringValue', '') or ''
                
                if 'Current Theme' in text or 'Theme:' in text:
                    return text
                
                for subview in view.get('subviews', []):
                    result = find_theme_text(subview, depth + 1)
                    if result:
                        return result
                return None
            
            theme_text = find_theme_text(window.get('viewHierarchy', {}))
            
            if theme_text:
                print(f"   Found theme text: '{theme_text}'")
                
                if expected_theme in theme_text:
                    return True  # Test passes
                else:
                    # INTENTIONAL FAILURE: Theme text doesn't match expected
                    # Highlight the failing element in RED
                    print(f"   ❌ Expected '{expected_theme}'")
                    print(f"   ❌ Found: '{theme_text}'")
                    
                    # Highlight the theme text in RED on the actual UI
                    client.highlight_failure("About", theme_text.strip(), duration=0)
                    
                    # Keep the highlight visible and return failure
                    return False
    
    # If we get here, no theme text was found at all
    # This is also a failure - simulate by looking for any text
    print("   ⚠ No 'Current Theme' text found in About dialog")
    print("   ⚠ Searching for any theme-related text to highlight...")
    
    # Try to find and highlight any text that might be theme-related
    for theme_name in ["Eau", "GNUstep", "Rik", "Default", "Theme"]:
        if client.text_visible(theme_name):
            print(f"   Found '{theme_name}' - highlighting it as potential theme indicator")
            client.highlight_failure("About", theme_name, duration=0)
            break
    
    # Fail the test since we couldn't find the expected theme text
    return False


def test_never_reached():
    """This test should never run because the previous test fails."""
    print("   This test should not have executed!")
    return True


# Run the interactive test suite with stop_on_failure
if __name__ == '__main__':
    print("=" * 60)
    print("INTENTIONAL FAILURE TEST")
    print("This test is DESIGNED TO FAIL to demonstrate red highlighting")
    print("=" * 60)
    print()
    print("Expected behavior:")
    print("  1. About dialog opens")
    print("  2. Test looks for 'Current Theme: GNUstep'")
    print("  3. If theme is different, that label turns RED")
    print("  4. Test execution STOPS at the failure")
    print()
    time.sleep(1)  # Give user time to read
    
    result = run_interactive_tests(
        ("Open About dialog", test_open_about_dialog),
        ("About window visible", test_about_window_visible),
        ("Theme is 'GNUstep'", test_check_theme_gnustep),  # <-- WILL FAIL
        ("Never reached", test_never_reached),  # <-- Should not run
        client=client,
        pause_between=0.5,
        stop_on_failure=True  # Stop at first failure
    )
    
    if result != 0:
        print()
        print("=" * 60)
        print("TEST FAILED AS EXPECTED!")
        print("The red highlight should be visible on the offending UI element.")
        print("The highlight will remain until you close the About window")
        print("or run: client.clear_highlights()")
        print("=" * 60)
        
        # Keep running for 5 seconds so user can see the highlight
        print("\nKeeping highlight visible for 10 seconds...")
        time.sleep(10)
        
        # Clean up
        print("Clearing highlights...")
        # client.clear_highlights()  # Skip for now - command has issues
    
    sys.exit(result)
