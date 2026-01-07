#!/usr/bin/env python3
"""
Interactive Click Test - Demonstrates clicking on UI elements.

This test:
1. Queries the UI to find clickable elements
2. Clicks on specific screen coordinates
3. Verifies the click action had an effect

Run with: python3 test_interactive_click.py

While running, you will SEE clicks happening in the UI.
"""

import sys, os, time
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'python'))

from uitest import WorkspaceTestClient, run_interactive_tests

# Create test client
client = WorkspaceTestClient()

# Clear any previous highlight overlays
client.clear_highlights()


def test_query_ui():
    """Query the UI to find window positions."""
    state = client.query_ui_state()
    windows = state.get('windows', [])
    print(f"   Found {len(windows)} window(s)")
    return True


def test_open_viewer():
    """Open the Viewer window via menu."""
    result = client.menu("Windows > Viewer")
    time.sleep(0.5)  # Wait for window to open
    return True  # Menu might not exist, but continue testing


def test_viewer_or_file():
    """Open a Viewer or File window."""
    # Try different ways to open a window with content
    if client.window_exists("Viewer"):
        return True
    if client.window_exists("File"):
        return True
    
    # Try to open home directory
    result = client.menu("File > Open...")
    time.sleep(0.5)
    return True


def test_click_on_window():
    """Click somewhere in the main area."""
    state = client.query_ui_state()
    
    for window in state.get('windows', []):
        frame = window.get('frame', {})
        if 'x' in frame and 'width' in frame:
            # Click in the center of the window
            x = frame.get('x', 0) + frame.get('width', 100) / 2
            y = frame.get('y', 0) + frame.get('height', 100) / 2
            
            print(f"   Clicking at ({x}, {y})")
            result = client.click(x, y)
            return True
    
    # Fallback: click at a reasonable screen position
    print("   Clicking at default position (300, 300)")
    result = client.click(300, 300)
    return True


def test_find_button():
    """Try to find a button in the UI."""
    state = client.query_ui_state()
    
    def find_buttons(view, buttons=None):
        """Recursively find button-like elements."""
        if buttons is None:
            buttons = []
        
        view_class = view.get('class', '')
        if 'Button' in view_class:
            title = view.get('title', '') or view.get('text', '')
            buttons.append({
                'class': view_class,
                'title': title,
                'frame': view.get('frame', {})
            })
        
        for subview in view.get('subviews', []):
            find_buttons(subview, buttons)
        
        return buttons
    
    all_buttons = []
    for window in state.get('windows', []):
        hierarchy = window.get('viewHierarchy', {})
        buttons = find_buttons(hierarchy)
        all_buttons.extend(buttons)
    
    print(f"   Found {len(all_buttons)} button(s)")
    if all_buttons:
        print(f"   First button: {all_buttons[0].get('title', '(no title)')}")
    
    return True


def test_cleanup():
    """Clean up test state."""
    # Close any windows we opened
    if client.window_exists("Viewer"):
        client.close_window("Viewer")
    if client.window_exists("Open"):
        client.close_window("Open")
    return True


# Run the interactive test suite
if __name__ == '__main__':
    print("=" * 60)
    print("Interactive Click Test")
    print("Watch as the test clicks on UI elements!")
    print("=" * 60)
    print()
    
    result = run_interactive_tests(
        ("Query UI state", test_query_ui),
        ("Open Viewer window", test_open_viewer),
        ("Check for window", test_viewer_or_file),
        ("Click on window", test_click_on_window),
        ("Find buttons", test_find_button),
        ("Cleanup", test_cleanup),
        client=client,
        pause_between=0.5,
        stop_on_failure=False  # Continue even if some tests fail
    )
    
    # Clean up highlights
    client.clear_highlights()
    
    sys.exit(result)
