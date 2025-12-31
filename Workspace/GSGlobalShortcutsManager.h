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
    NSDictionary *shortcuts;
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

@end

#endif
