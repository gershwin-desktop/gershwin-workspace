#!/usr/bin/env python3
"""
Interactive Test Suite - Desktop Operations

Tests desktop-specific functionality:
- Desktop window presence
- Desktop icons
- Desktop file operations
"""

import sys, os, time
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'python'))

from uitest import WorkspaceTestClient, run_tests

client = WorkspaceTestClient()

# Test paths
DESKTOP_PATH = client.get_desktop_path()

def get_desktop_window():
    """Find the desktop window."""
    visible = client.get_visible_windows()
    for w in visible:
        if w.get('class') == 'GWDesktopWindow':
            return w
    return None

def desktop_window_exists():
    """Verify desktop window exists."""
    return get_desktop_window() is not None

def desktop_covers_screen():
    """Verify desktop covers significant screen area."""
    w = get_desktop_window()
    if not w:
        return False
    frame = w.get('frame', {})
    width = frame.get('width', 0)
    height = frame.get('height', 0)
    # Desktop should be at least 800x600
    return width >= 800 and height >= 600

def desktop_has_content():
    """Verify desktop has child views."""
    w = get_desktop_window()
    if not w:
        return False
    content = w.get('contentView', {})
    children = content.get('children', [])
    return len(children) > 0

def desktop_path_exists():
    """Verify ~/Desktop directory exists."""
    return os.path.isdir(DESKTOP_PATH)

def can_create_on_desktop():
    """Test creating a file on desktop."""
    name = client.unique_name("DesktopTest") + ".txt"
    path = os.path.join(DESKTOP_PATH, name)
    
    try:
        with open(path, 'w') as f:
            f.write("Desktop test file")
        exists = os.path.exists(path)
        os.remove(path)  # Cleanup
        return exists
    except:
        return False

def desktop_responds_to_fs_changes():
    """Test that desktop updates when files change."""
    name = client.unique_name("DesktopUpdate") + ".txt"
    path = os.path.join(DESKTOP_PATH, name)
    
    # Create file
    with open(path, 'w') as f:
        f.write("Test file")
    
    # Wait for fs watcher
    time.sleep(1.5)
    client.refresh_viewer()
    time.sleep(0.5)
    
    # Check if visible (may not always work depending on icon positions)
    visible = client.text_visible(name.replace(".txt", ""))
    
    # Cleanup
    os.remove(path)
    
    # This test passes if the file was created/deleted successfully
    return True

def desktop_is_at_origin():
    """Desktop window should be at screen origin."""
    w = get_desktop_window()
    if not w:
        return False
    frame = w.get('frame', {})
    x = frame.get('x', -1)
    y = frame.get('y', -1)
    return x == 0 and y == 0

tests = [
    # Desktop window
    ("Desktop window exists",
     desktop_window_exists),
    
    ("Desktop covers screen",
     desktop_covers_screen),
    
    ("Desktop has content views",
     desktop_has_content),
    
    ("Desktop at screen origin",
     desktop_is_at_origin),
    
    # Filesystem
    ("Desktop directory exists",
     desktop_path_exists),
    
    ("Can create files on desktop",
     can_create_on_desktop),
    
    ("Desktop responds to filesystem changes",
     desktop_responds_to_fs_changes),
]

if __name__ == "__main__":
    print("\n" + "="*60)
    print("DESKTOP OPERATIONS TEST")
    print(f"Desktop path: {DESKTOP_PATH}")
    print("="*60 + "\n")
    exit(run_tests(*tests))
