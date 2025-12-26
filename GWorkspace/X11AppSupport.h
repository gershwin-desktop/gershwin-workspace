/* X11AppSupport.h
 *
 * Author: Gershwin Team
 * Date: December 2025
 */

#ifndef X11_APP_SUPPORT_H
#define X11_APP_SUPPORT_H

#import <Foundation/Foundation.h>

/**
 * X11AppSupport provides native X11 window management for non-GNUstep
 * applications in the Dock.
 *
 * This uses Xlib directly for window operations and simple timer-based
 * polling (250ms) to monitor process lifecycle.
 */

@class GWLaunchedApp;

#pragma mark - X11 Window Information

/**
 * Represents an X11 window with associated metadata.
 */
@interface GWX11WindowInfo : NSObject
{
    unsigned long windowID;
    NSString *windowName;
    NSString *windowClass;
    pid_t ownerPID;
    BOOL isHidden;
    BOOL isIconified;
}

@property (nonatomic, assign) unsigned long windowID;
@property (nonatomic, copy) NSString *windowName;
@property (nonatomic, copy) NSString *windowClass;
@property (nonatomic, assign) pid_t ownerPID;
@property (nonatomic, assign) BOOL isHidden;
@property (nonatomic, assign) BOOL isIconified;

+ (instancetype)infoWithWindowID:(unsigned long)wid;

@end

#pragma mark - X11 Window Operations

/**
 * Provides direct X11 window management operations.
 * All methods are thread-safe and handle X11 display connections internally.
 */
@interface GWX11WindowManager : NSObject

/**
 * Returns the shared window manager instance.
 */
+ (instancetype)sharedManager;

#pragma mark Window Discovery

/**
 * Returns all client windows from the window manager's client list.
 * @return Array of GWX11WindowInfo objects
 */
- (NSArray *)allClientWindows;

/**
 * Finds windows owned by a specific process.
 * @param pid The process ID to search for
 * @return Array of GWX11WindowInfo objects
 */
- (NSArray *)windowsForPID:(pid_t)pid;

/**
 * Finds windows matching a name substring (case-insensitive).
 * @param name The substring to search for in window names
 * @return Array of GWX11WindowInfo objects
 */
- (NSArray *)windowsMatchingName:(NSString *)name;

/**
 * Finds the first window matching a name substring.
 * @param name The substring to search for
 * @return Window ID or 0 if not found
 */
- (unsigned long)findWindowByName:(NSString *)name;

/**
 * Finds the first window owned by a specific process.
 * @param pid The process ID
 * @return Window ID or 0 if not found
 */
- (unsigned long)findWindowByPID:(pid_t)pid;

#pragma mark Window Activation

/**
 * Activates (raises and focuses) a window by ID.
 * Uses _NET_ACTIVE_WINDOW for EWMH-compliant window managers.
 * @param windowID The X11 window ID
 * @return YES if successful
 */
- (BOOL)activateWindow:(unsigned long)windowID;

/**
 * Activates all windows owned by a process.
 * @param pid The process ID
 * @return YES if at least one window was activated
 */
- (BOOL)activateWindowsForPID:(pid_t)pid;

/**
 * Activates windows matching a name substring.
 * @param name The substring to match
 * @return YES if at least one window was activated
 */
- (BOOL)activateWindowsMatchingName:(NSString *)name;

#pragma mark Window Hide/Show (Iconify)

/**
 * Iconifies (minimizes) a window.
 * @param windowID The X11 window ID
 * @return YES if successful
 */
- (BOOL)iconifyWindow:(unsigned long)windowID;

/**
 * Iconifies all windows owned by a process.
 * @param pid The process ID
 * @return YES if at least one window was iconified
 */
- (BOOL)iconifyWindowsForPID:(pid_t)pid;

/**
 * Iconifies windows matching a name substring.
 * @param name The substring to match
 * @return YES if at least one window was iconified
 */
- (BOOL)iconifyWindowsMatchingName:(NSString *)name;

/**
 * Restores (de-iconifies) a window.
 * @param windowID The X11 window ID
 * @return YES if successful
 */
- (BOOL)restoreWindow:(unsigned long)windowID;

/**
 * Restores all windows owned by a process.
 * @param pid The process ID
 * @return YES if at least one window was restored
 */
- (BOOL)restoreWindowsForPID:(pid_t)pid;

/**
 * Restores windows matching a name substring.
 * @param name The substring to match
 * @return YES if at least one window was restored
 */
- (BOOL)restoreWindowsMatchingName:(NSString *)name;

#pragma mark Window State Queries

/**
 * Checks if a window is currently iconified (minimized).
 * @param windowID The X11 window ID
 * @return YES if iconified
 */
- (BOOL)isWindowIconified:(unsigned long)windowID;

/**
 * Checks if a window is currently visible (mapped and not iconified).
 * @param windowID The X11 window ID
 * @return YES if visible
 */
- (BOOL)isWindowVisible:(unsigned long)windowID;

/**
 * Checks if any window exists for a process.
 * @param pid The process ID
 * @return YES if at least one window exists
 */
- (BOOL)hasWindowsForPID:(pid_t)pid;

/**
 * Checks if any window exists matching a name.
 * @param name The substring to match
 * @return YES if at least one window exists
 */
- (BOOL)hasWindowsMatchingName:(NSString *)name;

#pragma mark Window Closing

/**
 * Requests a window to close gracefully using WM_DELETE_WINDOW.
 * @param windowID The X11 window ID
 * @return YES if the request was sent
 */
- (BOOL)closeWindow:(unsigned long)windowID;

/**
 * Requests all windows for a process to close gracefully.
 * @param pid The process ID
 * @return YES if at least one close request was sent
 */
- (BOOL)closeWindowsForPID:(pid_t)pid;

@end

#pragma mark - X11 Application Manager

/**
 * Delegate protocol for X11 application events.
 */
@protocol GWX11AppManagerDelegate <NSObject>

- (void)x11AppDidLaunch:(NSString *)appName path:(NSString *)appPath pid:(pid_t)pid;
- (void)x11AppDidTerminate:(NSString *)appName path:(NSString *)appPath;
- (void)x11AppWindowsDidAppear:(NSString *)appName path:(NSString *)appPath;

@end

/**
 * Manages X11 (non-GNUstep) applications for dock integration,
 * window management, and process lifecycle monitoring.
 *
 * Uses simple 250ms timer polling to check process status - efficient
 * and portable across all Unix-like systems.
 */
@interface GWX11AppManager : NSObject
{
    NSMutableDictionary *x11Apps;
    NSTimer *monitorTimer;
    id<GWX11AppManagerDelegate> delegate;
}

@property (nonatomic, assign) id<GWX11AppManagerDelegate> delegate;

/**
 * Returns the shared X11 app manager instance.
 */
+ (instancetype)sharedManager;

/**
 * Registers an X11 application for monitoring.
 * @param appName The application name (for window matching)
 * @param appPath The full path to the application
 * @param pid The process ID of the launched application
 * @param windowSearchString Optional string to match window names (defaults to appName)
 */
- (void)registerX11App:(NSString *)appName
                  path:(NSString *)appPath
                   pid:(pid_t)pid
    windowSearchString:(NSString *)windowSearchString;

/**
 * Unregisters an X11 application.
 * @param appName The application name
 */
- (void)unregisterX11App:(NSString *)appName;

/**
 * Checks if an application is registered as X11.
 * @param appName The application name
 * @return YES if registered
 */
- (BOOL)isX11App:(NSString *)appName;

/**
 * Activates an X11 application's windows.
 * @param appName The application name
 * @return YES if windows were activated
 */
- (BOOL)activateX11App:(NSString *)appName;

/**
 * Hides (iconifies) an X11 application's windows.
 * @param appName The application name
 * @return YES if windows were hidden
 */
- (BOOL)hideX11App:(NSString *)appName;

/**
 * Unhides (restores) an X11 application's windows.
 * @param appName The application name
 * @return YES if windows were restored
 */
- (BOOL)unhideX11App:(NSString *)appName;

/**
 * Checks if an X11 application has visible windows.
 * @param appName The application name
 * @return YES if the app has visible windows
 */
- (BOOL)x11AppHasVisibleWindows:(NSString *)appName;

/**
 * Gets the PID of a registered X11 application.
 * @param appName The application name
 * @return The PID or 0 if not registered
 */
- (pid_t)pidForX11App:(NSString *)appName;

/**
 * Requests an X11 application to quit gracefully.
 * @param appName The application name
 * @param timeout Seconds to wait before force-killing
 * @return YES if the quit was initiated
 */
- (BOOL)quitX11App:(NSString *)appName timeout:(NSTimeInterval)timeout;

/**
 * Checks if a process exists and is running.
 * @param pid The process ID
 * @return YES if the process exists
 */
- (BOOL)processExists:(pid_t)pid;

@end

#endif /* X11_APP_SUPPORT_H */
