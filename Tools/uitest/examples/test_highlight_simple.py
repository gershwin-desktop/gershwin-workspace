#!/usr/bin/env python3
"""
Test red highlighting without using the broken menu command.
This uses the working 'about' command to open the dialog.
"""
import sys, os, time
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'python'))

from uitest import WorkspaceTestClient

client = WorkspaceTestClient()

print("=" * 60)
print("RED HIGHLIGHTING TEST")
print("=" * 60)
print()

# Step 1: Open About dialog (this works)
print("1. Opening About dialog...")
try:
    client.open_about_dialog()
    print("   ✓ About dialog opened")
    time.sleep(1)
except Exception as e:
    print(f"   ✗ Failed: {e}")
    sys.exit(1)

# Step 2: Find something to highlight
print("\n2. Looking for text to highlight...")
try:
    state = client.query_ui_state()
    
    # Look for the About window
    about_window = None
    for window in state.get('windows', []):
        title = window.get('title', '')
        if 'About' in title or 'Info' in title:
            about_window = window
            print(f"   Found window: {title}")
            break
    
    if not about_window:
        print("   ⚠ No About window found")
        sys.exit(1)
        
except Exception as e:
    print(f"   ✗ Failed: {e}")
    sys.exit(1)

# Step 3: Try to highlight "Workspace" text
print("\n3. Attempting to highlight 'Workspace' text in RED...")
try:
    # Use the uitest command directly
    import subprocess
    result = subprocess.run(
        ['./obj/uitest', 'highlight', 'About', 'Workspace', '0'],
        cwd='/home/devuan/gershwin-build/repos/gershwin-workspace/Tools/uitest',
        capture_output=True,
        text=True,
        timeout=5
    )
    
    if result.returncode == 0:
        print("   ✓ Highlight command executed!")
        print("\n" + "=" * 60)
        print("CHECK YOUR SCREEN NOW!")
        print("You should see RED highlighting on the 'Workspace' text")
        print("=" * 60)
        print("\nKeeping highlight visible for 10 seconds...")
        time.sleep(10)
        print("Done!")
    else:
        print(f"   ✗ Command failed:")
        print(f"   stdout: {result.stdout}")
        print(f"   stderr: {result.stderr}")
        
except subprocess.TimeoutExpired:
    print("   ✗ Command timed out")
except Exception as e:
    print(f"   ✗ Failed: {e}")

sys.exit(0)
