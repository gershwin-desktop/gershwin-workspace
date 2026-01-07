"""
Workspace GUI Testing Framework (Python bindings)

This package provides Python bindings for automated testing of the Workspace
file manager's user interface.

Quick Start:
    from uitest import WorkspaceTestClient, run_tests
    
    client = WorkspaceTestClient()
    client.open_about_dialog()
    
    exit(run_tests(
        ("Window exists", lambda: client.window_exists("About Workspace")),
        ("Text visible", lambda: client.text_visible("Version")),
    ))
"""

from .uitest import (
    WorkspaceTestClient,
    UITestException,
    WorkspaceNotRunningError,
    CommandFailedError,
    AssertionFailedError,
    test_workspace_responding,
    assert_about_opens,
    run_tests,
    simple_tests,  # Backward compatibility
)

__version__ = "1.0.0"
__all__ = [
    "WorkspaceTestClient",
    "UITestException",
    "WorkspaceNotRunningError",
    "CommandFailedError",
    "AssertionFailedError",
    "test_workspace_responding",
    "assert_about_opens",
    "run_tests",
    "simple_tests",
]
