#!/usr/bin/env python3
"""
Interactive Test Suite - File Operations

These tests perform real file operations and verify them:
- Create folders
- Create files
- Delete items
- Move to Trash

IMPORTANT: These tests create and delete files in ~/Desktop.
Run only when you understand what they do.
"""

import sys, os, time
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'python'))

from uitest import WorkspaceTestClient, run_tests

client = WorkspaceTestClient()

# Test configuration
TEST_DIR = client.get_desktop_path()
TEST_PREFIX = "UITest"

def cleanup_test_files():
    """Remove any leftover test files from previous runs."""
    for item in client.list_directory(TEST_DIR):
        if item.startswith(TEST_PREFIX):
            client.delete_path(os.path.join(TEST_DIR, item))
    return True

def create_folder_via_filesystem():
    """Create a test folder directly on filesystem."""
    name = client.unique_name(TEST_PREFIX + "Folder")
    path = client.create_test_directory(TEST_DIR, name)
    return client.file_exists(path)

def verify_folder_appears_in_ui():
    """Verify created folder appears in Workspace UI after refresh."""
    name = client.unique_name(TEST_PREFIX + "Visible")
    path = client.create_test_directory(TEST_DIR, name)
    
    # Give filesystem watcher time to notice
    time.sleep(1.0)
    client.refresh_viewer()
    time.sleep(0.5)
    
    # Check if name appears in UI
    return client.text_visible(name)

def create_file_via_filesystem():
    """Create a test file directly on filesystem."""
    name = client.unique_name(TEST_PREFIX + "File") + ".txt"
    path = client.create_test_file(TEST_DIR, name, "Test content for UI testing")
    return client.file_exists(path)

def delete_folder_via_filesystem():
    """Delete a test folder and verify it's gone."""
    name = client.unique_name(TEST_PREFIX + "Delete")
    path = client.create_test_directory(TEST_DIR, name)
    
    # Verify exists
    if not client.file_exists(path):
        return False
    
    # Delete it
    client.delete_path(path)
    
    # Verify gone
    return not client.file_exists(path)

def cleanup_at_end():
    """Clean up all test files."""
    return cleanup_test_files()

# Run cleanup first
cleanup_test_files()

tests = [
    # Basic filesystem operations
    ("Can create folder via filesystem",
     create_folder_via_filesystem),
    
    ("Created folder appears in UI",
     verify_folder_appears_in_ui),
    
    ("Can create file via filesystem",
     create_file_via_filesystem),
    
    ("Can delete folder via filesystem",
     delete_folder_via_filesystem),
    
    # Cleanup
    ("Cleanup test files",
     cleanup_at_end),
]

if __name__ == "__main__":
    print("\n" + "="*60)
    print("INTERACTIVE FILE OPERATIONS TEST")
    print(f"Test directory: {TEST_DIR}")
    print("="*60 + "\n")
    exit(run_tests(*tests))
