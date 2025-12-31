/*
 * GSGlobalShortcutsManager.h
 *
 * Global shortcuts manager for GNUstep Workspace
 * Handles system-wide keyboard shortcuts and their associated commands
 */

#ifndef GS_GLOBAL_SHORTCUTS_MANAGER_H
#define GS_GLOBAL_SHORTCUTS_MANAGER_H

#import <Foundation/Foundation.h>
#include <X11/Xlib.h>

@interface GSGlobalShortcutsManager : NSObject
{
    NSMutableDictionary *shortcuts;
    Display *display;
    Window rootWindow;
    unsigned int numlock_mask;
    unsigned int capslock_mask;
    unsigned int scrolllock_mask;
    BOOL running;
    BOOL verbose;
    time_t lastDefaultsModTime;
    NSString *defaultsDomain;
    NSTimer *eventProcessingTimer;
}

/**
 * Get the shared global shortcuts manager instance
 */
+ (GSGlobalShortcutsManager *)sharedManager;

/**
 * Initialize and start the global shortcuts manager
 * This should be called during application startup
 */
- (BOOL)startWithVerbose:(BOOL)verboseLogging;

/**
 * Stop the global shortcuts manager
 */
- (void)stop;

/**
 * Load shortcuts from GNUstep defaults
 */
- (BOOL)loadShortcuts;

/**
 * Show alert when a global shortcut command fails to execute
 */
- (void)showCommandFailureAlert:(NSString *)command shortcut:(NSString *)shortcut;

/**
 * Process shortcuts data directly from IPC notification
 */
- (void)processShortcutsData:(NSArray *)shortcutsArray;

/**
 * Reload shortcuts if the configuration has changed
 */
- (void)reloadShortcutsIfChanged;

/**
 * Notification handler for GlobalShortcuts configuration changes
 */
- (void)globalShortcutsConfigurationChanged:(NSNotification *)notification;

/**
 * Ungrab a specific key combination
 */
- (void)ungrabKeyCombo:(NSString *)keyCombo;

/**
 * Ungrab all currently grabbed keys
 */
- (void)ungrabAllKeys;

/**
 * Temporarily disable all shortcuts (for key capture)
 */
- (void)temporarilyDisableAllShortcuts:(NSNotification *)notification;

/**
 * Re-enable all shortcuts after key capture
 */
- (void)reEnableAllShortcuts:(NSNotification *)notification;

/**
 * Check if a shortcut is already taken
 */
- (BOOL)isShortcutAlreadyTaken:(NSString *)keyCombo;

@end

#endif
