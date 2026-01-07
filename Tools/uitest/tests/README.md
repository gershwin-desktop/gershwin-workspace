# Workspace UI Test Suite

A comprehensive test suite for automated testing of the Workspace file manager GUI.

## Test Files

| File | Description | Tests |
|------|-------------|-------|
| `test_00_connection.py` | Basic connectivity and UI testing | 4 tests |
| `test_01_info_panel.py` | About dialog contents | 5 tests |
| `test_02_window_management.py` | Window detection and properties | 7 tests |
| `test_03_ui_elements.py` | UI widget detection | 5 tests |
| `test_04_desktop.py` | Desktop window testing | 5 tests |
| `test_05_preferences.py` | Preferences panel | 3 tests |
| `test_06_inspector.py` | Inspector panel | 2 tests |
| `test_07_finder.py` | Finder/search functionality | 2 tests |
| `test_08_highlight.py` | Failure highlighting system | 4 tests |
| `test_09_file_browser.py` | File browser windows | 4 tests |
| `test_10_waits.py` | Wait functions and timing | 3 tests |
| `test_11_json_validation.py` | JSON response validation | 4 tests |
| `test_12_error_handling.py` | Error handling and edge cases | 5 tests |
| `test_13_text_extraction.py` | Text content extraction | 4 tests |
| `test_14_element_counting.py` | Element counting | 5 tests |
| `test_15_window_titles.py` | Window title operations | 4 tests |
| `test_16_about_deep.py` | Deep About dialog testing | 8 tests |
| `test_17_desktop_shelf.py` | Desktop and shelf features | 5 tests |
| `test_18_integration.py` | Python-CLI-Workspace integration | 4 tests |
| `test_19_visibility.py` | Visibility filtering | 5 tests |
| `test_20_geometry.py` | Frame and geometry validation | 5 tests |
| `test_99_intentional_failure.py` | Demo: intentional failures | 2 tests |

**Total: ~90 tests across 22 test files**

## Prerequisites

1. **Workspace running in debug mode:**
   ```bash
   Workspace -d
   ```

2. **uitest CLI tool built:**
   ```bash
   cd Tools/uitest
   make
   ```

3. **Python 3.x with no additional dependencies**

## Running Tests

### Run all tests
```bash
./run_all_tests.py
```

### Run with verbose output
```bash
./run_all_tests.py -v
```

### Run specific test file pattern
```bash
./run_all_tests.py test_01        # Run test_01_info_panel.py
./run_all_tests.py connection     # Run tests matching "connection"
```

### Run individual test file
```bash
./test_00_connection.py
```

### Include intentional failure tests (demo)
```bash
./run_all_tests.py --all          # Include test_99
./run_all_tests.py test_99        # Run only test_99
```

## Test Structure

Each test file follows a simple pattern:

```python
#!/usr/bin/env python3
"""Test description"""

import sys, os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'python'))

from uitest import WorkspaceTestClient, run_tests

client = WorkspaceTestClient()

def my_test():
    """Returns True if test passes, False if fails."""
    return client.window_exists("Some Window")

tests = [
    ("Test name shown in output", my_test),
    ("Another test", lambda: client.text_visible("Some text")),
]

if __name__ == "__main__":
    exit(run_tests(*tests))
```

## Writing New Tests

1. Create a new file: `test_XX_feature.py` (XX = number for ordering)
2. Import the test framework
3. Create test functions that return `True`/`False`
4. Add tests to the `tests` list as `(name, function)` tuples
5. Use `run_tests(*tests)` to execute

### Available Assertions

```python
client.window_exists("Window Title")      # Check window exists
client.text_visible("Some text")          # Check text visible anywhere
client.find_element("Window", "text")     # Find element with text
client.get_visible_windows()              # Get visible windows
client.get_window_titles()                # Get all window titles
client.count_elements_by_class("NSButton") # Count widgets by class
client.query_ui_state()                   # Get full UI state JSON
```

### Available Actions

```python
client.open_about_dialog()               # Open About dialog
client.menu("Info > About")              # Click menu item
client.shortcut("Cmd+i")                 # Send keyboard shortcut
client.click(x, y)                       # Click at coordinates
client.close_window("Title")             # Close a window
client.highlight_failure("Win", "text", 3)  # Red highlight (3 sec)
client.clear_highlights()                # Clear all highlights
```

### Wait Functions

```python
client.wait_for_window("Title", timeout=5.0)      # Wait for window
client.wait_for_text("text", timeout=5.0)         # Wait for text
client.wait_for_window_closed("Title", timeout=5.0)  # Wait for close
```

## Failure Detection

When a test fails:
1. The element is highlighted in **red** in the UI
2. A screenshot is saved to `~/Desktop/TestFailure-{window}-{element}-{timestamp}/`
3. Workspace logs are captured alongside the screenshot
4. Test output shows which assertion failed

## Exit Codes

- `0` - All tests passed
- `1` - One or more tests failed

## Continuous Integration

The test suite can be run in CI with:

```bash
# Start Workspace in headless mode (requires virtual display)
Xvfb :99 -screen 0 1920x1080x24 &
export DISPLAY=:99
Workspace -d &
sleep 2

# Run tests
cd Tools/uitest/tests
./run_all_tests.py

# Capture exit code
TEST_RESULT=$?
exit $TEST_RESULT
```
