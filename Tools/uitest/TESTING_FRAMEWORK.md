# Workspace GUI Testing Framework - Complete Feature Set

## Overview

The Workspace GUI testing framework provides comprehensive tools for automated testing of the Workspace file manager's user interface. It supports three primary testing approaches:

1. **Command-line tool** (`uitest`) for quick queries and scripts
2. **Python testing library** for writing structured test suites
3. **Coordinate-based inspection** for interactive UI exploration

## Features Implemented

### 1. Command-Line Tool (`uitest`)

The `uitest` tool provides direct command-line access to GUI testing capabilities.

#### Commands

```
about                    Open the Workspace About box and extract UI state
at-coordinate X Y        Show all UI elements at screen coordinates X, Y
query [options]          Query UI state (--json, --tree, or --text)
run-script PATH          Run Python test script against Workspace
help                     Show help message
```

#### Examples

```bash
# Extract About dialog UI state
./uitest about

# Find what UI elements are at screen coordinate (500, 500)
./uitest at-coordinate 500 500

# Run a Python test script
./uitest run-script examples/test_about_dialog.py
```

### 2. Python Testing Library

A complete Python library (`uitest/python/uitest.py`) for writing automated tests.

#### Installation

```python
import sys
sys.path.insert(0, 'Tools/uitest/python')
from uitest import WorkspaceTestClient
```

#### Basic Usage

```python
from uitest import WorkspaceTestClient, AssertionFailedError

# Create a test client
client = WorkspaceTestClient()

# Open the About dialog and get UI state
client.open_about_dialog()

# Query the current UI state
state = client.query_ui_state()
print(f"Found {len(state['windows'])} windows")

# Assert that a window exists
client.assert_window_exists("Workspace Preferences")

# Check if specific text is visible
if client.text_visible("Save"):
    print("Save button is visible")

# Get elements in a specific window
elements = client.get_window_elements("Finder")
for element in elements:
    print(f"  {element.get('class')}: {element.get('text', '')}")
```

#### Core API Methods

**Initialization**
- `WorkspaceTestClient(uitest_path=None)` - Create test client, auto-finds uitest executable

**UI Control**
- `open_about_dialog()` - Open About dialog
- `query_ui_state()` -> Dict - Get complete UI state as JSON
- `get_ui_at_coordinate(x, y)` -> str - Get UI elements at coordinate as text tree

**Queries**
- `window_exists(title)` -> bool - Check if window exists
- `text_visible(text, case_sensitive=False)` -> bool - Check if text is visible
- `get_window_elements(title)` -> List - Get all elements in a window
- `assert_element_exists(class_name, msg="")` - Assert element with class exists

**Script Execution**
- `run_script(script_path)` -> int - Run Python test script

**Assertions**
- `assert_window_exists(title, msg="")` - Raise if window doesn't exist
- `assert_text_visible(text, msg="", case_sensitive=False)` - Raise if text not found
- `assert_element_exists(class_name, msg="")` - Raise if element not found

#### Exception Handling

```python
from uitest import (
    WorkspaceTestClient,
    WorkspaceNotRunningError,
    CommandFailedError,
    AssertionFailedError,
)

try:
    client = WorkspaceTestClient()
except WorkspaceNotRunningError:
    print("Workspace not running - start with: Workspace -d")
except CommandFailedError as e:
    print(f"Command failed: {e}")
except AssertionFailedError as e:
    print(f"Assertion failed: {e}")
```

### 3. Coordinate-Based UI Inspection

The `at-coordinate` command allows you to click on screen coordinates and see all UI elements at that location in a human-readable tree format.

#### How It Works

```bash
./uitest at-coordinate 500 500
```

Output:
```
=== UI Elements at Coordinate (500, 500) ===

Window: Workspace Preferences
─────────────────────────────────
  ├─ NSBox "Box"
    ├─ NSView
      ├─ NSBox "Default Editor"
        ├─ NSView
          ├─ NSImageView
          ├─ NSTextField "TextEdit.app"
      ├─ NSButton "Choose"
  ├─ NSButton "OK"
```

This shows:
- Window name/title
- Class hierarchy of UI elements
- Text labels for each element
- Indented tree structure showing parent-child relationships

#### Use Cases

1. **Interactive Testing** - Click on a UI element to identify it
2. **Debugging** - Understand the UI element hierarchy
3. **Element Inspection** - Find class names and hierarchy of controls
4. **Accessibility Testing** - Verify all interactive elements are accessible

## Example Test Script

See `Tools/uitest/examples/test_about_dialog.py` for a complete example.

```python
#!/usr/bin/env python3

import sys
import os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'python'))

from uitest import WorkspaceTestClient

def main():
    client = WorkspaceTestClient()
    
    # Test 1: Open About dialog
    print("Opening About dialog...", end=' ')
    client.open_about_dialog()
    print("✓")
    
    # Test 2: Verify dialog opened
    print("Verifying dialog...", end=' ')
    state = client.query_ui_state()
    assert len(state['windows']) > 0, "No windows found"
    print("✓")
    
    # Test 3: Check for content
    print("Checking content...", end=' ')
    client.assert_window_exists("Workspace Preferences")
    print("✓")
    
    print("\nAll tests passed!")
    return 0

if __name__ == '__main__':
    sys.exit(main())
```

### Running Test Scripts

```bash
# Run directly with Python
python3 test_about_dialog.py

# Run via uitest tool
./uitest run-script test_about_dialog.py

# Run via uitest tool with full path
./uitest run-script examples/test_about_dialog.py
```

## JSON Output Format

The `query_ui_state()` method and `about` command return JSON with this structure:

```json
{
  "uiTestingEnabled": true,
  "windows": [
    {
      "title": "Window Title",
      "class": "NSWindow",
      "visibility": "visible",
      "isKeyWindow": "yes",
      "frame": {
        "x": 100,
        "y": 200,
        "width": 800,
        "height": 600
      },
      "contentView": {
        "class": "NSView",
        "children": [
          {
            "class": "NSButton",
            "text": "OK",
            "state": "enabled",
            "visibility": "visible",
            "frame": { "x": 10, "y": 20, "width": 80, "height": 30 },
            "children": []
          }
        ]
      }
    }
  ]
}
```

## System Requirements

- Workspace running with `-d` or `--debug` flag
- Python 3.6+ for Python testing library
- GNUstep/Objective-C environment for building uitest

## Starting Workspace with Debug Mode

The UI testing framework requires Workspace to be started with debug flag enabled:

```bash
# Start Workspace with debug mode
/path/to/Workspace.app/Workspace -d

# Verify it's running
ps aux | grep Workspace
```

When debug mode is enabled, Workspace logs:
```
Workspace: Debug mode enabled
Workspace: UI Testing mode enabled (WorkspaceUITesting protocol)
```

## Architecture

### Distributed Objects Communication

The uitest tool communicates with Workspace via macOS distributed objects (NSConnection):

```
uitest tool (client)
    ↓
NSConnection to "Workspace"
    ↓
Workspace (server)
    ↓
WorkspaceUITesting protocol
    ↓
JSON serialized UI state
    ↓
uitest tool (client receives JSON)
```

### Protocol Definition

```objc
@protocol WorkspaceUITesting
- (NSString *)currentWindowHierarchyAsJSON;
- (NSArray *)allWindowTitles;
@end
```

The protocol is implemented in `Workspace+UITesting.m` which:
- Builds a complete representation of all windows and their UI elements
- Serializes to JSON for transmission to the tool
- Only enabled when Workspace started with `-d` flag

## Files Included

### Implementation Files
- `Tools/uitest/uitest.m` - Main C command-line tool (600+ lines)
- `Tools/uitest/GNUmakefile` - Build configuration
- `Tools/uitest/WorkspaceUITesting.h` - Protocol header
- `Workspace/Workspace+UITesting.m` - Protocol implementation in Workspace
- `Workspace/main.m` - Debug flag parsing

### Python Library
- `Tools/uitest/python/uitest.py` - Main testing library (430 lines)
- `Tools/uitest/python/__init__.py` - Package initialization

### Examples & Documentation
- `Tools/uitest/examples/test_about_dialog.py` - Example test suite
- `Tools/uitest/examples/README.md` - Example documentation
- `Tools/uitest/UI_STATE_GUIDE.md` - Integration guide
- `Tools/uitest/README.md` - Tool documentation

## Testing the Framework

### Quick Verification

```bash
# 1. Start Workspace with debug flag
Workspace -d

# 2. Verify it's running
./uitest/obj/uitest about | head -20

# 3. Run example test suite
python3 ./uitest/examples/test_about_dialog.py

# 4. Try coordinate inspection
./uitest/obj/uitest at-coordinate 500 500
```

### Expected Output

**test_about_dialog.py** should show:
```
============================================================
Workspace About Dialog Test Suite
============================================================

Checking Workspace availability... ✓ Workspace is running

Test 1: Opening About dialog... ✓ SUCCESS
Test 2: Checking About window exists... ✓ SUCCESS
Test 3: Checking About content... ✓ SUCCESS
Test 4: Verifying dialog interaction... ✓ SUCCESS
Test 5: Checking window count... ✓ SUCCESS
Test 6: Checking JSON structure... ✓ SUCCESS
Test 7: Checking UI element tree... ✓ SUCCESS

============================================================
Results: 7/7 tests passed
============================================================
```

## Advanced Usage

### Custom Test Scripts

Create your own test scripts following this pattern:

```python
#!/usr/bin/env python3
import sys, os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'python'))

from uitest import WorkspaceTestClient, AssertionFailedError

def test_finder_operations():
    client = WorkspaceTestClient()
    
    # Test Finder window
    state = client.query_ui_state()
    finder_windows = [w for w in state['windows'] if 'Finder' in w.get('title', '')]
    assert len(finder_windows) > 0, "Finder window not found"
    
    print("✓ Finder window found")

def test_window_properties():
    client = WorkspaceTestClient()
    state = client.query_ui_state()
    
    for window in state['windows']:
        title = window.get('title', 'Unknown')
        visibility = window.get('visibility', 'unknown')
        is_key = window.get('isKeyWindow', 'no')
        print(f"Window: {title} ({visibility}, key={is_key})")

if __name__ == '__main__':
    try:
        test_finder_operations()
        test_window_properties()
        print("\nAll custom tests passed!")
    except AssertionFailedError as e:
        print(f"Test failed: {e}", file=sys.stderr)
        sys.exit(1)
```

### Continuous Integration

The framework can be integrated into CI/CD pipelines:

```bash
#!/bin/bash
# ci-test.sh

# Start Workspace in background
Workspace -d > /dev/null 2>&1 &
WORKSPACE_PID=$!
sleep 2

# Run test suite
python3 tools/uitest/examples/test_about_dialog.py
TEST_RESULT=$?

# Cleanup
kill $WORKSPACE_PID 2>/dev/null

exit $TEST_RESULT
```

## Troubleshooting

### "Cannot contact Workspace application"

**Cause**: Workspace not running or not responding
**Solution**: 
```bash
# Make sure Workspace is running with debug flag
ps aux | grep '[W]orkspace -d'

# If not running, start it:
Workspace -d
```

### Python script fails with "setRequestTimeout" error

**Cause**: Old Workspace instance still running
**Solution**:
```bash
pkill -9 Workspace
sleep 2
Workspace -d
```

### JSON parse errors in Python

**Cause**: Workspace not started with debug flag
**Solution**: Verify debug mode is enabled by checking Workspace logs

### Coordinate inspection returns empty results

**Cause**: Coordinates might be off-screen or outside any window
**Solution**: Use visible window coordinates from `query_ui_state()` frame data

## Performance Notes

- First query takes ~500ms (connection establishment)
- Subsequent queries take ~100-200ms
- JSON parsing adds ~50ms
- Coordinate queries are similar speed to regular queries

## Future Enhancements

Potential additions to the framework:

1. **Mouse/Keyboard Simulation**
   - `client.click(x, y)`
   - `client.type("text")`
   - `client.key_press("Return")`

2. **Window Management**
   - `client.close_window(title)`
   - `client.minimize_window(title)`
   - `client.bring_to_front(title)`

3. **Visual Regression Testing**
   - Screenshot comparison
   - Element position validation
   - Layout verification

4. **Accessibility Testing**
   - Accessibility attribute checking
   - ARIA role validation
   - Screen reader compatibility

5. **Performance Profiling**
   - UI element count monitoring
   - Render time measurement
   - Memory usage tracking

## License

GNU General Public License v2.0 or later

Part of the Workspace/Gershwin project.
