/* WorkspaceApplication.m
 *  
 * Copyright (C) 2006-2016 Free Software Foundation, Inc.
 *
 * Author: Enrico Sersale <enrico@imago.ro>
 * Date: January 2006
 *
 * This file is part of the GNUstep Workspace application
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 * 
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 * 
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 31 Milk Street #960789 Boston, MA 02196 USA.
 */

#include <math.h>
#include <string.h>

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <GNUstepBase/GNUstep.h>

#import "Workspace.h"
#import "GWFunctions.h"
#import "FSNodeRep.h"
#import "FSNFunctions.h"
#import "Workspace.h"
#import "GWDesktopManager.h"
#import "Dock.h"
#import "DockIcon.h"
#import "GWViewersManager.h"
#import "Operation.h"
#import "StartAppWin.h"
#import "X11AppSupport.h"
// For checking whether a process identifier still exists
#include <signal.h>
#include <errno.h>
#include <limits.h>
#include <unistd.h>
#include <X11/Xlib.h>
#include <X11/Xatom.h>

@implementation Workspace (WorkspaceApplication)

/*
 * Sever X client connections for all clients except this process.
 * This is a last-resort action used during logout to ensure X11 clients
 * cannot keep running by holding onto the display connection. We attempt
 * to read the _NET_WM_PID property for windows and issue XKillClient()
 * against windows owned by other processes. This is aggressive but useful
 * during logout to avoid stubborn X clients persisting.
 */
- (void)severAllXClientsExceptSelf
{
  pid_t selfpid = getpid();
  Display *dpy = XOpenDisplay(NULL);

  if (dpy == NULL) {
    NSLog(@"severAllXClientsExceptSelf: could not open X display");
    return;
  }

  Atom pidAtom = XInternAtom(dpy, "_NET_WM_PID", False);
  Window root = DefaultRootWindow(dpy);

  /* Depth-first traversal of the window tree */
  NSMutableArray *stack = [NSMutableArray arrayWithObject: @(root)];

  while ([stack count]) {
    unsigned long w = [[stack lastObject] unsignedLongValue];
    [stack removeLastObject];

    Window root_ret, parent_ret;
    Window *children = NULL;
    unsigned int nchildren = 0;

    if (XQueryTree(dpy, (Window)w, &root_ret, &parent_ret, &children, &nchildren)) {
      for (unsigned int i = 0; i < nchildren; i++) {
        [stack addObject: @((unsigned long)children[i])];
      }
      if (children) XFree(children);
    }

    if (pidAtom == None)
      continue;

    Atom actualType;
    int actualFormat;
    unsigned long nitems, bytes_after;
    unsigned char *prop = NULL;
    int status = XGetWindowProperty(dpy, (Window)w, pidAtom, 0, 1, False, XA_CARDINAL,
                                    &actualType, &actualFormat, &nitems, &bytes_after, &prop);

    if (status == Success && prop != NULL && nitems >= 1) {
      unsigned long winpid = 0;

      /* The property is stored as 32-bit CARDINALs; copy safely */
      memcpy(&winpid, prop, sizeof(unsigned long));
      XFree(prop);

      if ((pid_t)winpid != selfpid && winpid != 0) {
        XKillClient(dpy, (Window)w);
        NSLog(@"severAllXClientsExceptSelf: killed X client owning window 0x%lx (pid %lu)", w, winpid);
      }
    }
  }

  XFlush(dpy);
  XCloseDisplay(dpy);
}

- (BOOL)performFileOperation:(NSString *)operation 
                      source:(NSString *)source 
                 destination:(NSString *)destination 
                       files:(NSArray *)files 
                         tag:(NSInteger *)tag
{
  if (loggingout == NO)
    {
      NSMutableDictionary *opdict = [NSMutableDictionary dictionary];

      if (operation != nil)
	[opdict setObject: operation forKey: @"operation"];
      else
	NSLog(@"performFileOperation: operation can't be nil");
 
      if (operation != nil)
	[opdict setObject: source forKey: @"source"];
      else
	NSLog(@"performFileOperation: source is nil");

      if (destination == nil && [operation isEqualToString:NSWorkspaceRecycleOperation])
	destination = [self trashPath];
      if (destination != nil)
	[opdict setObject: destination forKey: @"destination"];

      if (files != nil)
	[opdict setObject: files forKey: @"files"];

      [fileOpsManager performOperation: opdict];

      *tag = 0;
    
      return YES;
  
    }
  else
    {
      NSRunAlertPanel(nil, 
		      NSLocalizedString(@"Workspace is logging out!", @""),
		      NSLocalizedString(@"OK", @""), 
		      nil, 
		      nil);  
    }
  
  return NO;
}

- (BOOL)selectFile:(NSString *)fullPath
											inFileViewerRootedAtPath:(NSString *)rootFullpath
{
  FSNode *node = [FSNode nodeWithPath: fullPath];
  
  if (node && [node isValid]) {
    FSNode *base;
  
    if ((rootFullpath == nil) || ([rootFullpath length] == 0)) {
      base = [FSNode nodeWithPath: path_separator()];
    } else {
      base = [FSNode nodeWithPath: rootFullpath];
    }
  
    if (base && [base isValid]) {
      if (([base isDirectory] == NO) || [base isPackage]) {
        return NO;
      }
    
      [vwrsManager selectRepOfNode: node inViewerWithBaseNode: base];
      return YES;
    }
  }
   
  return NO;
}

- (int)extendPowerOffBy:(int)requested
{
  int req = (int)(requested / 1000);
  int ret;
  
  if (req > 0) {
    ret = (req < maxLogoutDelay) ? req : maxLogoutDelay;
  } else {
    ret = 0;
  }
  
  logoutDelay += ret;

  if (logoutTimer && [logoutTimer isValid]) {
    NSTimeInterval fireInterval = ([[logoutTimer fireDate] timeIntervalSinceNow] + ret);
    [logoutTimer setFireDate: [NSDate dateWithTimeIntervalSinceNow: fireInterval]];
  }
  
  return (ret * 1000);
}

- (NSArray *)launchedApplications
{
  NSMutableArray *launched = [NSMutableArray array];
  NSUInteger i;
  
  for (i = 0; i < [launchedApps count]; i++)
    {
      [launched addObject: [[launchedApps objectAtIndex: i] appInfo]];
    }

  return [launched makeImmutableCopyOnFail: NO];
}

- (NSDictionary *)activeApplication
{
  if (activeApplication != nil) {
    return [activeApplication appInfo];
  }
  return nil;
}

- (BOOL)openFile:(NSString *)fullPath
          withApplication:(NSString *)appname
            andDeactivate:(BOOL)flag
{
  NSString *appPath, *appName;
  GWLaunchedApp *app;
  id application;

  if (loggingout) {
    NSRunAlertPanel(nil, 
                  NSLocalizedString(@"Workspace is logging out!", @""),
					        NSLocalizedString(@"OK", @""), 
                  nil, 
                  nil);  
    return NO;
  }
      
  if (appname == nil) {
    NSString *ext = [[fullPath pathExtension] lowercaseString];
    
    appname = [ws getBestAppInRole: nil forExtension: ext];
    
    if (appname == nil) {
      appname = defEditor;      
    }
  }

  [self applicationName: &appName andPath: &appPath forName: appname];
  
  app = [self launchedAppWithPath: appPath andName: appName];
  
  if (app == nil) {
    NSArray *args = [NSArray arrayWithObjects: @"-GSFilePath", fullPath, nil];
    
    return [self launchApplication: appname arguments: args];
  
  } else {  
    /* Check if app is still running before trying to use it */
    if (![app isRunning]) {
      /* App entry exists but process is not running - clean up and re-launch */
      NSArray *args = [NSArray arrayWithObjects: @"-GSFilePath", fullPath, nil];
      [self applicationTerminated: app];
      return [self launchApplication: appname arguments: args];
    }
    
    /*
    * If we are opening many files together and our app is a non-GNUstep X11 app,
    * we must wait a little for the last launched task to terminate.
    * Else we'd end waiting two seconds in -connectApplication.
    */
    GWProcessStartupRunLoop(0.1);
    
    application = [app application];
    
    if (application == nil) {
      /* Non-GNUstep/X11 app - it's running but has no DO connection.
       * We can't open files in it via DO, so just activate it. */
      [self activateAppWithPath: appPath andName: appName];
      return YES;

    } else {
      NS_DURING
	      {
	    if (flag == NO) {
	      [application application: NSApp openFileWithoutUI: fullPath];
      } else {
	      [application application: NSApp openFile: fullPath];
	    }
	      }
      NS_HANDLER
	      {
      [self applicationTerminated: app]; 
	    NSWarnLog(@"Failed to contact '%@' to open file", appName);
	    return NO;
	      }
      NS_ENDHANDLER
    }
  }
  
  if (flag) {
    [NSApp deactivate];
  }

  return YES;
}

- (BOOL)launchApplication:(NSString *)appname
		             showIcon:(BOOL)showIcon
	             autolaunch:(BOOL)autolaunch
{
  NSString *appPath, *appName;
  GWLaunchedApp *app;
  id application;
  NSArray	*args = nil;

  if (loggingout) {
    NSRunAlertPanel(nil, 
                  NSLocalizedString(@"Workspace is logging out!", @""),
					        NSLocalizedString(@"OK", @""), 
                  nil, 
                  nil);  
    return NO;
  }

  [self applicationName: &appName andPath: &appPath forName: appname];
 
  app = [self launchedAppWithPath: appPath andName: appName];
 
  if (app == nil) {
    if (autolaunch) {
	    args = [NSArray arrayWithObjects: @"-autolaunch", @"YES", nil];
	  }
    
    return [self launchApplication: appname arguments: args];
  
  } else {
    /* Check if app is still running before trying to activate */
    if ([app isRunning]) {
      /* App is running - activate it instead of re-launching */
      application = [app application];
      
      if (application != nil) {
        /* GNUstep app with DO connection - activate normally */
        [application activateIgnoringOtherApps: YES];
      } else {
        /* Non-GNUstep/X11 app - use X11 window activation */
        [self activateAppWithPath: appPath andName: appName];
      }
      return YES;
    } else {
      /* App entry exists but process is not running - clean up and re-launch */
      [self applicationTerminated: app];

      if (autolaunch) {
	      args = [NSArray arrayWithObjects: @"-autolaunch", @"YES", nil];
	    }
             
      return [self launchApplication: appname arguments: args];
    }
  }

  return YES;
}

- (BOOL)openTempFile:(NSString *)fullPath
{
  NSString *ext = [[fullPath pathExtension] lowercaseString];
  NSString *name = [ws getBestAppInRole: nil forExtension: ext];
  NSString *appPath, *appName;
  GWLaunchedApp *app;
  id application;

  if (loggingout) {
    NSRunAlertPanel(nil, 
                  NSLocalizedString(@"Workspace is logging out!", @""),
					        NSLocalizedString(@"OK", @""), 
                  nil, 
                  nil);  
    return NO;
  }
  
  if (name == nil) {
    NSWarnLog(@"No known applications for file extension '%@'", ext);
    return NO;
  }
  
  [self applicationName: &appName andPath: &appPath forName: name];  
    
  app = [self launchedAppWithPath: appPath andName: appName];
    
  if (app == nil) {
    NSArray *args = [NSArray arrayWithObjects: @"-GSTempPath", fullPath, nil];
    
    return [self launchApplication: name arguments: args];
  
  } else {
    /* Check if app is still running before trying to use it */
    if (![app isRunning]) {
      /* App entry exists but process is not running - clean up and re-launch */
      NSArray *args = [NSArray arrayWithObjects: @"-GSTempPath", fullPath, nil];
      [self applicationTerminated: app];
      return [self launchApplication: name arguments: args];
    }
    
    application = [app application];
    
    if (application == nil) {
      /* Non-GNUstep/X11 app - it's running but has no DO connection.
       * We can't open temp files in it via DO, so just activate it. */
      [self activateAppWithPath: appPath andName: appName];
      return YES;
      
    } else {
      NS_DURING
	      {
	    [application application: NSApp openTempFile: fullPath];
	      }
      NS_HANDLER
	      {
      [self applicationTerminated: app];
	    NSWarnLog(@"Failed to contact '%@' to open temp file", appName);
	    return NO;
	      }
      NS_ENDHANDLER
    }
  }    

  [NSApp deactivate];

  return YES;
}

@end


@implementation Workspace (Applications)

- (void)initializeWorkspace
{
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

  autoLogoutDelay = [defaults integerForKey: @"GSAutoLogoutDelay"];

  maxLogoutDelay = [defaults integerForKey: @"GSMaxLogoutDelay"];
  
  if (autoLogoutDelay == 0) {
    maxLogoutDelay = 30;
  }  

  wsnc = [ws notificationCenter];
  
  [wsnc addObserver: self
	         selector: @selector(appWillLaunch:)
		           name: NSWorkspaceWillLaunchApplicationNotification
		         object: nil];

  [wsnc addObserver: self
	         selector: @selector(appDidLaunch:)
		           name: NSWorkspaceDidLaunchApplicationNotification
		         object: nil];    

  [wsnc addObserver: self
	         selector: @selector(appDidTerminate:)
		           name: NSWorkspaceDidTerminateApplicationNotification
		         object: nil];    

  [wsnc addObserver: self
	         selector: @selector(appDidBecomeActive:)
		           name: NSApplicationDidBecomeActiveNotification
		         object: nil];

  [wsnc addObserver: self
	         selector: @selector(appDidResignActive:)
		           name: NSApplicationDidResignActiveNotification
		         object: nil];    

  [wsnc addObserver: self
	         selector: @selector(appDidHide:)
		           name: NSApplicationDidHideNotification
		         object: nil];

  [wsnc addObserver: self
	         selector: @selector(appDidUnhide:)
		           name: NSApplicationDidUnhideNotification
		         object: nil];    
    
  [self checkLastRunningApps];

  logoutTimer = nil;
  logoutDelay = 0;
  loggingout = NO;

  // Init fallback timers dict for non-GNUstep apps' dock dot
  launchDotFallbacks = [NSMutableDictionary new];
  
  // Set up X11 app manager delegate for non-GNUstep app lifecycle events
  [[GWX11AppManager sharedManager] setDelegate: (id<GWX11AppManagerDelegate>)self];
}

- (void)applicationName:(NSString **)appName
                andPath:(NSString **)appPath
                forName:(NSString *)name
{
  *appName = [[name lastPathComponent] stringByDeletingPathExtension];
  *appPath = [ws fullPathForApplication: *appName];
}
                
- (BOOL)launchApplication:(NSString *)appname
		            arguments:(NSArray *)args
{
  NSString *appPath, *appName;
  NSTask *task;
  GWLaunchedApp *app;
  NSString *path;
  NSDictionary *userinfo;
  NSString *host;

  path = [ws locateApplicationBinary: appname];
  
  if (path == nil) {
	  return NO;
	}

  /*
  * Try to ensure that apps we launch display in this workspace
  * ie they have the same -NSHost specification.
  */
  host = [[NSUserDefaults standardUserDefaults] stringForKey: @"NSHost"];
      
  if (host != nil) {
    NSHost *h = [NSHost hostWithName: host];
    
    if ([h isEqual: [NSHost currentHost]] == NO) {
      if ([args containsObject: @"-NSHost"] == NO) {
		    NSMutableArray *a;

		    if (args == nil) {
		      a = [NSMutableArray arrayWithCapacity: 2];
		    } else {
		      a = AUTORELEASE ([args mutableCopy]);
		    }
		    
        [a insertObject: @"-NSHost" atIndex: 0];
		    [a insertObject: host atIndex: 1];
		    args = a;
		  }
    }
	}

  [self applicationName: &appName andPath: &appPath forName: appname];
  
  if (appPath == nil) {
    [ws findApplications];
    [self applicationName: &appName andPath: &appPath forName: appname];
  }

  if (appPath == nil && [appname isAbsolutePath] == YES)
    {
      appPath = appname;
    }
  
  /* Check if this app is already running (either tracked by Workspace or found via X11) */
  if (appPath && appName) {
    GWLaunchedApp *existing = [self launchedAppWithPath: appPath andName: appName];
    if (existing && [existing isRunning]) {
      /* Our tracked instance is running; don't launch again. Activate instead. */
      GWDebugLog(@"App \"%@\" already running (tracked); activating instead of launching.", appName);
      [[dtopManager dock] appDidLaunch: appPath appName: appName];
      [self activateAppWithPath: appPath andName: appName];
      return YES;
    }
    
    /* Also check if the app is running on the system via X11 (external launch) */
    GWX11WindowManager *wm = [GWX11WindowManager sharedManager];
    
    /* Priority 1: Check if there's a known PID from a previous dock icon */
    DockIcon *dockIcon = [[dtopManager dock] iconForApplicationName: appName];
    pid_t knownPID = dockIcon ? [dockIcon appPID] : 0;
    BOOL hasWindows = NO;
    
    if (knownPID > 0) {
      hasWindows = [wm hasWindowsForPID: knownPID];
    }
    
    /* Priority 2: Fall back to name matching */
    if (!hasWindows) {
      hasWindows = [wm hasWindowsMatchingName: appName];
    }
    
    if (hasWindows) {
      /* App is running somewhere on the system (possibly launched externally).
         Notify the Dock so the icon's "running" dot appears, and activate the app
         to raise/unminimize its window immediately. */
      GWDebugLog(@"App \"%@\" already running (X11 window found); notifying Dock and activating.", appName);
      [[dtopManager dock] appDidLaunch: appPath appName: appName];
      /* Activate the app to raise/unminimize its window immediately */
      [self activateAppWithPath: appPath andName: appName pid: knownPID];
      return YES;
    }
  }
  
  userinfo = [NSDictionary dictionaryWithObjectsAndKeys: appName, 
			                                                   @"NSApplicationName",
	                                                       appPath, 
                                                         @"NSApplicationPath",
	                                                       nil];
                 
  [wsnc postNotificationName: NSWorkspaceWillLaunchApplicationNotification
	                    object: ws
	                  userInfo: userinfo];

  task = [NSTask launchedTaskWithLaunchPath: path arguments: args];
  
  if (task == nil) {
	  return NO;
	}
  
  app = [GWLaunchedApp appWithApplicationPath: appPath
                              applicationName: appName
                                 launchedTask: task];
  
  if (app) {
    [launchedApps addObject: app];
    return YES;
  }
  
  return NO;    
}

- (void)appWillLaunch:(NSNotification *)notif
{
  NSDictionary *info = [notif userInfo];
  NSString *path = [info objectForKey: @"NSApplicationPath"];
  NSString *name = [info objectForKey: @"NSApplicationName"];
  
  if (path && name) {
    [[dtopManager dock] appWillLaunch: path appName: name];
    GWDebugLog(@"appWillLaunch: \"%@\" %@", name, path);
    // Schedule 10s fallback: if no window/connection appears but the
    // process hasn't exited, show the dock dot anyway.
    [self _scheduleLaunchDotFallbackForPath: path name: name];
  } else {
    GWDebugLog(@"appWillLaunch: unknown application!");
  }
}

- (void)appDidLaunch:(NSNotification *)notif
{
  NSDictionary *info = [notif userInfo];
  NSString *name = [info objectForKey: @"NSApplicationName"];
  NSString *path = [info objectForKey: @"NSApplicationPath"];
  NSNumber *ident = [info objectForKey: @"NSApplicationProcessIdentifier"];
  GWLaunchedApp *app = [self launchedAppWithPath: path andName: name];

  if (app) {
    [app setIdentifier: ident];
    
  } else { 
    /*
    * if launched by an other process
    */
    app = [GWLaunchedApp appWithApplicationPath: path
                                applicationName: name
                              processIdentifier: ident
                                   checkRunning: NO];
    
    if (app && [app application]) {
      [launchedApps addObject: app];
    }  
  }

  /*
   * For GNUstep apps (with NSConnection), notify dock at launch time.
   * For non-GNUstep apps (no connection), register with X11AppManager
   * for process monitoring and window management.
   */
  if (app && [app application]) {
    pid_t pid = ident ? (pid_t)[ident intValue] : 0;
    [[dtopManager dock] appDidLaunch: path appName: name pid: pid];
    GWDebugLog(@"\"%@\" appDidLaunch (%@) [dock notified]", name, path);
    // No need for fallback if connection established
    [self _cancelLaunchDotFallbackForPath: path name: name];
  } else if (app && ident) {
    /* Non-GNUstep app: register with X11AppManager for monitoring */
    pid_t pid = (pid_t)[ident intValue];
    if (pid > 0) {
      [app setIsX11App: YES];
      [app setWindowSearchString: name];
      [[GWX11AppManager sharedManager] registerX11App: name
                                                 path: path
                                                  pid: pid
                                   windowSearchString: name];
      GWDebugLog(@"\"%@\" appDidLaunch (%@) [registered as X11 app, pid=%d]", name, path, pid);
    }
  }
}

- (void)appDidTerminate:(NSNotification *)notif
{
  NSDictionary *info = [notif userInfo];
  NSString *name = [info objectForKey: @"NSApplicationName"];
  NSString *path = [info objectForKey: @"NSApplicationPath"];
  GWLaunchedApp *app = [self launchedAppWithPath: path andName: name];

  /*
   * Relying solely on the connection death notification misses apps that
   * never establish a connection (e.g. X11 or non-GNUstep apps). Use
   * the workspace termination notification as a fallback to update the Dock
   * and internal state.
   */
  if (app == nil && name)
    {
      NSUInteger i;

      for (i = 0; i < [launchedApps count]; i++)
        {
          GWLaunchedApp *candidate = [launchedApps objectAtIndex: i];

          if ([[candidate name] isEqual: name])
            {
              app = candidate;
              break;
            }
        }
    }

  if (app)
    {
      // Cancel any pending fallback when termination is observed
      [self _cancelLaunchDotFallbackForPath: [app path] name: [app name]];
      [self applicationTerminated: app];
    }
  else if (name)
    {
      /* Ensure undocked icons are cleared even if we did not track the app. */
      [self _cancelLaunchDotFallbackForPath: path name: name];
      [[dtopManager dock] appTerminated: name];
      GWDebugLog(@"appDidTerminate: \"%@\" not tracked; forcing dock cleanup.", name);
    }
}

- (void)appDidBecomeActive:(NSNotification *)notif
{
  NSDictionary *info = [notif userInfo];
  NSString *name = [info objectForKey: @"NSApplicationName"];
  NSString *path = [info objectForKey: @"NSApplicationPath"];
  GWLaunchedApp *app = [self launchedAppWithPath: path andName: name];

  if (app) {
    NSUInteger i;
    
    for (i = 0; i < [launchedApps count]; i++) {
      GWLaunchedApp *a = [launchedApps objectAtIndex: i];
      [a setActive: (a == app)];
    }
    
    activeApplication = app;
    GWDebugLog(@"\"%@\" appDidBecomeActive", name);

    /* If this is a non-GNUstep app (no connection), show dock dot now. */
    if ([app application] == nil && name && path) {
      pid_t pid = [app identifier] ? (pid_t)[[app identifier] intValue] : 0;
      [[dtopManager dock] appDidLaunch: path appName: name pid: pid];
      GWDebugLog(@"\"%@\" appDidBecomeActive -> dock notified (non-GNUstep)", name);
      [self _cancelLaunchDotFallbackForPath: path name: name];
    }

  } else {
    activeApplication = nil;
    GWDebugLog(@"appDidBecomeActive: \"%@\" unknown running application.", name);

    /* Heuristic: even if we don't track the app, activation implies a window
       is present. Ensure the dock shows the running dot. */
    if (name && path) {
      [[dtopManager dock] appDidLaunch: path appName: name];
      GWDebugLog(@"\"%@\" appDidBecomeActive (untracked) -> dock notified", name);
      [self _cancelLaunchDotFallbackForPath: path name: name];
    }
  }
}

#pragma mark - Non-GNUstep dock dot fallback helpers

- (NSString *)_launchKeyForPath:(NSString *)path name:(NSString *)name
{
  if (!path || !name) return nil;
  return [NSString stringWithFormat:@"%@\n%@", path, name];
}

- (BOOL)_pidExists:(pid_t)pid
{
  if (pid <= 0) return NO;
  // kill(pid, 0) returns 0 if process exists and we have permission,
  // or -1 with EPERM if it exists but we lack permission.
  int r = kill(pid, 0);
  if (r == 0) return YES;
  return (errno == EPERM);
}

- (void)_scheduleLaunchDotFallbackForPath:(NSString *)path name:(NSString *)name
{
  NSString *key = [self _launchKeyForPath:path name:name];
  if (!key) return;
  // Avoid duplicating timers
  if ([launchDotFallbacks objectForKey:key] != nil) return;

  NSDictionary *ui = [NSDictionary dictionaryWithObjectsAndKeys:
                      path, @"path",
                      name, @"name",
                      [NSNumber numberWithInt:0], @"retryCount",
                      nil];
  NSTimer *t = [NSTimer scheduledTimerWithTimeInterval:0.5
                                                target:self
                                              selector:@selector(_launchDotFallbackTimerFired:)
                                              userInfo:ui
                                               repeats:NO];
  [launchDotFallbacks setObject:t forKey:key];
}

- (void)_cancelLaunchDotFallbackForPath:(NSString *)path name:(NSString *)name
{
  NSString *key = [self _launchKeyForPath:path name:name];
  if (!key) return;
  NSTimer *t = [launchDotFallbacks objectForKey:key];
  if (t) {
    if ([t isValid]) [t invalidate];
    [launchDotFallbacks removeObjectForKey:key];
  }
}

- (void)_launchDotFallbackTimerFired:(NSTimer *)timer
{
  NSDictionary *ui = [timer userInfo];
  NSString *path = [ui objectForKey:@"path"];
  NSString *name = [ui objectForKey:@"name"];
  int retryCount = [[ui objectForKey:@"retryCount"] intValue];
  NSString *key = [self _launchKeyForPath:path name:name];

  if (!(path.length && name.length)) {
    if (key) [launchDotFallbacks removeObjectForKey:key];
    return;
  }

  GWLaunchedApp *app = [self launchedAppWithPath:path andName:name];
  BOOL shouldShowDot = NO;
  BOOL processRunning = NO;
  pid_t appPID = 0;

  /* Check if process is running and get the PID */
  if (app) {
    NSTask *task = [app task];
    if (task) {
      processRunning = [task isRunning];
      @try { appPID = [task processIdentifier]; } @catch (id ex) { appPID = 0; }
    } else {
      NSNumber *ident = [app identifier];
      if (ident) {
        appPID = (pid_t)[ident intValue];
        processRunning = [self _pidExists:appPID];
      }
    }
  }

  /* Check if a window is visible on X11 (faster response for non-GNUstep apps) */
  GWX11WindowManager *wm = [GWX11WindowManager sharedManager];
  
  /* Priority 1: Check by PID first */
  if (appPID > 0 && [wm hasWindowsForPID:appPID]) {
    shouldShowDot = YES;
  }
  
  /* Priority 2: Fall back to name matching */
  if (!shouldShowDot && [wm hasWindowsMatchingName: name]) {
    shouldShowDot = YES;
  }

  /* If no window yet but process is running, retry (up to 20 times = 10s) */
  if (!shouldShowDot && processRunning && retryCount < 20) {
    NSDictionary *newUi = [NSDictionary dictionaryWithObjectsAndKeys:
                           path, @"path",
                           name, @"name",
                           [NSNumber numberWithInt:retryCount + 1], @"retryCount",
                           nil];
    NSTimer *t = [NSTimer scheduledTimerWithTimeInterval:0.5
                                                  target:self
                                                selector:@selector(_launchDotFallbackTimerFired:)
                                                userInfo:newUi
                                                 repeats:NO];
    NSTimer *oldTimer = [launchDotFallbacks objectForKey:key];
    if (oldTimer && [oldTimer isValid]) {
      [oldTimer invalidate];
    }
    [launchDotFallbacks setObject:t forKey:key];
    return;
  }

  /* Show dot if window found or final timeout with running process */
  if (shouldShowDot || (processRunning && retryCount >= 20)) {
    [[dtopManager dock] appDidLaunch:path appName:name pid:appPID];
    GWDebugLog(@"Fallback: showing dock dot for \"%@\" (retry %d, pid=%d)", name, retryCount, appPID);
  }

  /* Clean up */
  if (key) {
    [launchDotFallbacks removeObjectForKey:key];
  }
}

#pragma mark - GWX11AppManagerDelegate

- (void)x11AppDidLaunch:(NSString *)appName path:(NSString *)appPath pid:(pid_t)pid
{
  if (appName == nil || appPath == nil) return;
  GWDebugLog(@"X11 app launched: %@ (%@) pid=%d", appName, appPath, pid);
  [[dtopManager dock] appWillLaunch:appPath appName:appName pid:pid];
}

- (void)x11AppDidTerminate:(NSString *)appName path:(NSString *)appPath
{
  if (appName == nil) return;
  GWDebugLog(@"X11 app terminated: %@ (%@)", appName, appPath);
  
  /* Find and clean up the GWLaunchedApp entry */
  GWLaunchedApp *app = [self launchedAppWithPath:appPath andName:appName];
  if (app) {
    [self applicationTerminated:app];
  } else {
    /* Just update the dock directly if we don't have a tracked app */
    [[dtopManager dock] appTerminated:appName];
  }
}

- (void)x11AppWindowsDidAppear:(NSString *)appName path:(NSString *)appPath
{
  if (appName == nil || appPath == nil) return;
  
  /* Get the PID from X11AppManager for more reliable tracking */
  pid_t pid = [[GWX11AppManager sharedManager] pidForX11App:appName];
  
  GWDebugLog(@"X11 app windows appeared: %@ (%@) pid=%d", appName, appPath, pid);
  [[dtopManager dock] appDidLaunch:appPath appName:appName pid:pid];
  
  /* Cancel any pending fallback timer */
  [self _cancelLaunchDotFallbackForPath:appPath name:appName];
}

#pragma mark - X11 Activation (non-GNUstep apps)

- (BOOL)_x11ActivateForApp:(GWLaunchedApp *)app name:(NSString *)name
{
  GWX11WindowManager *wm = [GWX11WindowManager sharedManager];
  
  /* If app is registered with X11AppManager, use that */
  if (app && [app isX11App]) {
    return [[GWX11AppManager sharedManager] activateX11App: name];
  }
  
  /* Fallback: try by PID first, then by name */
  pid_t pid = 0;
  if ([app identifier]) pid = (pid_t)[[app identifier] intValue];
  if (pid <= 0 && [app task]) {
    @try { pid = [[app task] processIdentifier]; } @catch (id ex) { pid = 0; }
  }
  
  if (pid > 0) {
    if ([wm activateWindowsForPID: pid]) {
      return YES;
    }
  }
  
  if (name) {
    return [wm activateWindowsMatchingName: name];
  }
  
  return NO;
}

- (void)appDidResignActive:(NSNotification *)notif
{
  NSDictionary *info = [notif userInfo];
  NSString *name = [info objectForKey: @"NSApplicationName"];
  NSString *path = [info objectForKey: @"NSApplicationPath"];
  GWLaunchedApp *app = [self launchedAppWithPath: path andName: name];
  
  if (app) {
    [app setActive: NO];
    
    if (app == activeApplication) {
      activeApplication = nil;
    }
    
  } else {
    GWDebugLog(@"appDidResignActive: \"%@\" unknown running application.", name);
  }
}

- (void)activateAppWithPath:(NSString *)path
                    andName:(NSString *)name
{
  [self activateAppWithPath:path andName:name pid:0];
}

- (void)activateAppWithPath:(NSString *)path
                    andName:(NSString *)name
                        pid:(pid_t)pid
{
  GWLaunchedApp *app = [self launchedAppWithPath: path andName: name];
  GWX11WindowManager *wm = [GWX11WindowManager sharedManager];

  if (app) {
    [app activateApplication];
    if ([app application] == nil) {
      /* For X11/non-GNUstep apps, try PID first, then name matching */
      pid_t appPID = pid;
      if (appPID <= 0 && [app identifier]) {
        appPID = (pid_t)[[app identifier] intValue];
      }
      if (appPID > 0 && [wm activateWindowsForPID:appPID]) {
        return;
      }
      [self _x11ActivateForApp: app name: name];
    }
  } else {
    /* Fallback: try PID first if provided, then by name */
    if (pid > 0 && [wm activateWindowsForPID:pid]) {
      return;
    }
    [self _x11ActivateForApp: nil name: name];
  }
}

- (void)appDidHide:(NSNotification *)notif
{
  NSDictionary *info = [notif userInfo];
  NSString *name = [info objectForKey: @"NSApplicationName"];
  NSString *path = [info objectForKey: @"NSApplicationPath"];
  GWLaunchedApp *app = [self launchedAppWithPath: path andName: name];
  
  GWDebugLog(@"appDidHide: %@", name);
   
  if (app) {
    [app setHidden: YES];
    [[dtopManager dock] appDidHide: name];
  } else {
    GWDebugLog(@"appDidHide: \"%@\" unknown running application.", name);
  }
}

- (void)appDidUnhide:(NSNotification *)notif
{
  NSDictionary *info = [notif userInfo];
  NSString *name = [info objectForKey: @"NSApplicationName"];
  NSString *path = [info objectForKey: @"NSApplicationPath"];
  GWLaunchedApp *app = [self launchedAppWithPath: path andName: name];
    
  if (app) {
    [app setHidden: NO];
    [[dtopManager dock] appDidUnhide: name];
    GWDebugLog(@"\"%@\" appDidUnhide", name);
  } else {
    GWDebugLog(@"appDidUnhide: \"%@\" unknown running application.", name);
  }
}

- (void)unhideAppWithPath:(NSString *)path
                  andName:(NSString *)name
{
  GWLaunchedApp *app = [self launchedAppWithPath: path andName: name];

  if (app && [app isHidden]) {
    [app unhideApplication];
    if ([app application] == nil) {
      [self _x11ActivateForApp: app name: name];
    }
  } else if (!app) {
    // Fallback for non-tracked non-GNUstep apps: try to raise their X11 windows
    [self _x11ActivateForApp: nil name: name];
  }
}

- (void)applicationTerminated:(GWLaunchedApp *)app
{
  NSLog(@"WorkspaceApplication applicationTerminated: %@", [app name]);
  if (app == activeApplication) {
    activeApplication = nil;
  }
  
  [[dtopManager dock] appTerminated: [app name]];
  GWDebugLog(@"\"%@\" applicationTerminated", [app name]);  
  [launchedApps removeObject: app];  
  
  if (loggingout && ([launchedApps count] == 1)) {
    GWLaunchedApp *app = [launchedApps objectAtIndex: 0];

    if ([[app name] isEqual: gwProcessName]) {
      [NSApp terminate: self];
    }
  }
}

- (GWLaunchedApp *)launchedAppWithPath:(NSString *)path
                               andName:(NSString *)name
{
  if ((path != nil) && (name != nil))
    {
      NSUInteger i;

      for (i = 0; i < [launchedApps count]; i++)
        {
          GWLaunchedApp *app = [launchedApps objectAtIndex: i];

          if (([[app path] isEqual: path]) && ([[app name] isEqual: name]))
            {
              return app;
            }
        }
    }
    
  return nil;
}

- (NSArray *)storedAppInfo
{
  NSDictionary *runningInfo = nil;
  NSDictionary *apps = nil;
  
  if ([storedAppinfoLock tryLock] == NO) {
    unsigned sleeps = 0;

    if ([[storedAppinfoLock lockDate] timeIntervalSinceNow] < -20.0) {
	    NS_DURING
	      {
	    [storedAppinfoLock breakLock];
	      }
	    NS_HANDLER
	      {
      NSLog(@"Unable to break lock %@ ... %@", storedAppinfoLock, localException);
	      }
	    NS_ENDHANDLER
    }
    
    for (sleeps = 0; sleeps < 10; sleeps++) {
	    if ([storedAppinfoLock tryLock] == YES) {
	      break;
	    }
	    
      sleeps++;
	    [NSThread sleepUntilDate: [NSDate dateWithTimeIntervalSinceNow: 0.1]];
	  }
    
    if (sleeps >= 10) {
      NSLog(@"Unable to obtain lock %@", storedAppinfoLock);
      return nil;
	  }
  }

  if ([fm isReadableFileAtPath: storedAppinfoPath]) {
    runningInfo = [NSDictionary dictionaryWithContentsOfFile: storedAppinfoPath];
  }
        
  [storedAppinfoLock unlock];
  
  if (runningInfo == nil) {
    return nil;
  }
  
  apps = [runningInfo objectForKey: @"GSLaunched"];
  
  if (apps != nil) {
    return [apps allValues];
  }
  
  return nil;
}

- (void)updateStoredAppInfoWithLaunchedApps:(NSArray *)apps
{
  CREATE_AUTORELEASE_POOL(arp);
  NSMutableDictionary *runningInfo = nil;
  NSDictionary *oldapps = nil;
  NSMutableDictionary *newapps = nil;
  BOOL modified = NO;
  NSUInteger i;
    
  if ([storedAppinfoLock tryLock] == NO)
    {
      unsigned sleeps = 0;

      if ([[storedAppinfoLock lockDate] timeIntervalSinceNow] < -20.0)
        {
          NS_DURING
            {
              [storedAppinfoLock breakLock];
            }
          NS_HANDLER
            {
              NSLog(@"Unable to break lock %@ ... %@", storedAppinfoLock, localException);
            }
          NS_ENDHANDLER
            }
    
    for (sleeps = 0; sleeps < 10; sleeps++) {
	    if ([storedAppinfoLock tryLock] == YES) {
	      break;
	    }
	    
      sleeps++;
	    [NSThread sleepUntilDate: [NSDate dateWithTimeIntervalSinceNow: 0.1]];
	  }
    
    if (sleeps >= 10) {
      NSLog(@"Unable to obtain lock %@", storedAppinfoLock);
      return;
	  }
  }

  if ([fm isReadableFileAtPath: storedAppinfoPath]) {
    runningInfo = [NSMutableDictionary dictionaryWithContentsOfFile: storedAppinfoPath];
  }

  if (runningInfo == nil) {
    runningInfo = [NSMutableDictionary dictionary];
    modified = YES;
  }

  oldapps = [runningInfo objectForKey: @"GSLaunched"];
  
  if (oldapps == nil) {
    newapps = [NSMutableDictionary new];
    modified = YES;
  } else {
    newapps = [oldapps mutableCopy];
  }
  
  for (i = 0; i < [apps count]; i++)
    {
      GWLaunchedApp *app = [apps objectAtIndex: i];
      NSString *appname = [app name];
      NSDictionary *oldInfo = [newapps objectForKey: appname];

      if ([app isRunning] == NO)
        {
          if (oldInfo != nil)
            {
              [newapps removeObjectForKey: appname];
	      modified = YES;
	    }

        }
      else
        {
          NSDictionary *info = [app appInfo];

          if ([info isEqual: oldInfo] == NO) {
            [newapps setObject: info forKey: appname];
            modified = YES;
          }
        }
    }
  
  if (modified)
    {
      [runningInfo setObject: newapps forKey: @"GSLaunched"];
      [runningInfo writeToFile: storedAppinfoPath atomically: YES];
    }

  RELEASE (newapps);  
  [storedAppinfoLock unlock];
  RELEASE (arp);
}

- (void)checkLastRunningApps
{
  NSArray *oldrunning = [self storedAppInfo];

  if (oldrunning && [oldrunning count])
    {
      NSMutableArray *toremove = [NSMutableArray array];
      NSUInteger i;
    
      for (i = 0; i < [oldrunning count]; i++)
        {
          NSDictionary *dict = [oldrunning objectAtIndex: i];
          NSString *name = [dict objectForKey: @"NSApplicationName"];
          NSString *path = [dict objectForKey: @"NSApplicationPath"];
          NSNumber *ident = [dict objectForKey: @"NSApplicationProcessIdentifier"];
    
          if (name && path && ident)
            {
              GWLaunchedApp *app = [GWLaunchedApp appWithApplicationPath: path
                                                         applicationName: name
                                                       processIdentifier: ident
                                                            checkRunning: YES];
        
              if ((app != nil) && [app isRunning])
                {
                  BOOL hidden = [app isApplicationHidden];
          
                  [launchedApps addObject: app];
                  [app setHidden: hidden];
                  [[dtopManager dock] appDidLaunch: path appName: name];
          
                  if (hidden)
                    {
                      [[dtopManager dock] appDidHide: name];
                    }
          
                }
              else if (app != nil)
                {
                  [toremove addObject: app];
                }
            }
        }
    
      if ([toremove count])
        {
          [self updateStoredAppInfoWithLaunchedApps: toremove];
        }
    }
}

- (void)startLogoutRestartShutdownWithType:(NSString *)type message:(NSString *)message systemAction:(NSString *)systemActionTitle pendingCommand:(NSString *)pendingCommand
{
  NSString *msg;

  // Only set loggingout = YES for actual logout, not for restart/shutdown
  loggingout = (pendingCommand == nil);
  logoutDelay = 30;
 
  msg = message;

  if (NSRunAlertPanel(systemActionTitle ? systemActionTitle : NSLocalizedString(@"Logout", @""),
                      msg,
                      systemActionTitle ? systemActionTitle : NSLocalizedString(@"Log out", @""),
                      NSLocalizedString(@"Cancel", @""),
                      nil))
    {
      if (pendingCommand) {
        // Set up for restart/shutdown
        _pendingSystemActionCommand = pendingCommand;
        _pendingSystemActionTitle = systemActionTitle;
      }
      [self doLogoutRestartShutdown:nil];
    }
  else
    {
      loggingout = NO;
      if (pendingCommand) {
        _pendingSystemActionCommand = nil;
        _pendingSystemActionTitle = nil;
      }
    }
}

- (void)startLogout
{
  [self startLogoutRestartShutdownWithType:@"logout"
                                   message:NSLocalizedString(@"Are you sure you want to quit\nall applications and log out now?", @"")
                              systemAction:nil
                             pendingCommand:nil];
}

- (void)doLogoutRestartShutdown:(id)sender
{
  NSMutableArray *launched = [NSMutableArray array];
  GWLaunchedApp *gwapp = [self launchedAppWithPath: gwBundlePath andName: gwProcessName];
  NSUInteger i;
  
  [launched addObjectsFromArray: launchedApps];
  [launched removeObject: gwapp];

  /* Sever X client connections now (except our own) so stubborn X11 apps
     cannot keep the display connection alive and prevent logout. */
  [self severAllXClientsExceptSelf];

  for (i = 0; i < [launched count]; i++)
    [[launched objectAtIndex: i] terminateApplication];

  [launched removeAllObjects];
  [launched addObjectsFromArray: launchedApps];
  [launched removeObject: gwapp];
    
  if ([launched count])
    {
      ASSIGN (logoutTimer, [NSTimer scheduledTimerWithTimeInterval: logoutDelay
                                                            target: self 
                                                          selector: @selector(terminateTasksForLogoutRestartShutdown:) 
                                                          userInfo: nil 
                                                           repeats: NO]);
    }
  else
    {
      // For logout, terminate the app. For restart/shutdown, execute system command directly.
      if (_pendingSystemActionCommand) {
        // This is restart/shutdown - try system commands and reset state
        [self executeSystemCommandAndReset];
      } else {
        // This is logout - terminate the app
        [NSApp terminate: self];
      }
    }
}

- (void)terminateTasksForLogoutRestartShutdown:(id)sender
{
  BOOL canterminate = YES;

  if ([launchedApps count] > 1)
    {
      NSMutableArray *launched = [NSMutableArray array];
      GWLaunchedApp *gwapp = [self launchedAppWithPath: gwBundlePath andName: gwProcessName];
      NSMutableString *appNames = [NSMutableString string];
      NSString *msg = nil;
      NSUInteger count;
      NSUInteger i;

      [launched addObjectsFromArray: launchedApps];
      [launched removeObject: gwapp];
    
      count = [launched count];
    
      for (i = 0; i < count; i++)
        {
          GWLaunchedApp *app = [launched objectAtIndex: i];
      
          [appNames appendString: [app name]];

          if (i < (count - 1))
            [appNames appendString: @", "];
        }
    
      msg = [NSString stringWithFormat: @"%@\n%@\n%@",
                      NSLocalizedString(@"The following applications:", @""),
                      appNames, 
                      NSLocalizedString(@"refuse to terminate.", @"")];    

      if (NSRunAlertPanel(_pendingSystemActionTitle ? _pendingSystemActionTitle : NSLocalizedString(@"Logout", @""),
                          msg,
                          NSLocalizedString(@"Kill applications", @""),
                          NSLocalizedString(@"Cancel", @""),
                          nil))
        {
          /* First sever all X client connections so those apps cannot
             keep the display connection and delay logout/termination. */
          [self severAllXClientsExceptSelf];

          for (i = 0; i < [launched count]; i++)
            {
              [[launched objectAtIndex: i] terminateTask];      
            }    
        }
      else
        {
          canterminate = NO;
        }
    }
  
  if (canterminate)
    {
      // For logout, terminate the app. For restart/shutdown, execute system command directly.
      if (_pendingSystemActionCommand) {
        // This is restart/shutdown - try system commands and reset state
        [self executeSystemCommandAndReset];
      } else {
        // This is logout - terminate the app
        [NSApp terminate: self];
      }
    }
  else
    {
      // Cannot terminate other apps - reset state
      loggingout = NO;
      DESTROY(_pendingSystemActionCommand);
      DESTROY(_pendingSystemActionTitle);
    }
}



@end


@implementation GWLaunchedApp

+ (id)appWithApplicationPath:(NSString *)apath
             applicationName:(NSString *)aname
                launchedTask:(NSTask *)atask
{
  GWLaunchedApp *app = [GWLaunchedApp new];
  
  [app setPath: apath];
  [app setName: aname];
  [app setTask: atask];
  
  if (([app name] == nil) || ([app path] == nil)) {
    DESTROY (app);
  }
  
  return AUTORELEASE (app);  
}

+ (id)appWithApplicationPath:(NSString *)apath
             applicationName:(NSString *)aname
           processIdentifier:(NSNumber *)ident
                checkRunning:(BOOL)check
{
  GWLaunchedApp *app = [GWLaunchedApp new];
  
  [app setPath: apath];
  [app setName: aname];
  [app setIdentifier: ident];
  
  if (([app name] == nil) || ([app path] == nil) || ([app identifier] == nil)) {
    DESTROY (app);
  } else if (check) {
    [app connectApplication: NO];
  }
  
  return AUTORELEASE (app);  
}

+ (id)x11AppWithPath:(NSString *)apath
                name:(NSString *)aname
                 pid:(pid_t)pid
  windowSearchString:(NSString *)searchString
{
  GWLaunchedApp *app = [GWLaunchedApp new];
  
  [app setPath: apath];
  [app setName: aname];
  [app setIdentifier: [NSNumber numberWithInt: pid]];
  [app setIsX11App: YES];
  [app setWindowSearchString: searchString ? searchString : aname];
  
  if (([app name] == nil) || ([app path] == nil) || (pid <= 0)) {
    DESTROY (app);
    return nil;
  }
  
  /* Register with the X11 app manager for process monitoring and window management */
  [[GWX11AppManager sharedManager] registerX11App: aname
                                             path: apath
                                              pid: pid
                               windowSearchString: searchString ? searchString : aname];
  
  return AUTORELEASE (app);
}

- (void)dealloc
{
  [nc removeObserver: self];

  if (conn && [conn isValid]) {
    DESTROY (application);  
    RELEASE (conn);  
  }
  
  /* Unregister from X11 app manager if needed */
  if (isX11App && name) {
    [[GWX11AppManager sharedManager] unregisterX11App: name];
  }
  
  RELEASE (name);
  RELEASE (path);
  RELEASE (identifier);
  RELEASE (task);
  RELEASE (windowSearchString);
    
  [super dealloc];
}

- (id)init
{
  self = [super init];
  
  if (self) {
    task = nil;
    name = nil;
    path = nil; 
    identifier = nil;
    conn = nil;
    application = nil;
    active = NO;
    hidden = NO;
    isX11App = NO;
    windowSearchString = nil;
    
    gw = [Workspace gworkspace];
    nc = [NSNotificationCenter defaultCenter];      
  }
  
  return self;
}

- (NSUInteger)hash
{
  return ([name hash] | [path hash]);
}

- (BOOL)isEqual:(id)other
{
  if (other == self) {
    return YES;
  }
  
  if ([other isKindOfClass: [GWLaunchedApp class]]) {
    return ([[(GWLaunchedApp *)other name] isEqual: name]
                && [[(GWLaunchedApp *)other path] isEqual: path]);
  }
  
  return NO;
}

- (NSDictionary *)appInfo
{
  NSMutableDictionary *dict = [NSMutableDictionary dictionary];
  
  [dict setObject: name forKey: @"NSApplicationName"];
  [dict setObject: path forKey: @"NSApplicationPath"];
  
  if (identifier != nil) {
    [dict setObject: identifier forKey: @"NSApplicationProcessIdentifier"];
  }

  return [dict makeImmutableCopyOnFail: NO];
}

- (void)setTask:(NSTask *)atask
{
  if (task && (task != atask)) {
    [nc removeObserver: self
                  name: NSTaskDidTerminateNotification
                object: task];
  }

  ASSIGN (task, atask);

  if (task) {
    [nc addObserver: self
            selector: @selector(taskDidTerminate:)
                name: NSTaskDidTerminateNotification
              object: task];
  }
}

- (NSTask *)task
{
  return task;
}

- (void)setPath:(NSString *)apath
{
  ASSIGN (path, apath);
}

- (NSString *)path
{
  return path;
}

- (void)setName:(NSString *)aname
{
  ASSIGN (name, aname);
}

- (NSString *)name
{
  return name;
}

- (void)setIdentifier:(NSNumber *)ident
{
  ASSIGN (identifier, ident);
}

- (NSNumber *)identifier
{
  return identifier;
}

- (id)application
{
  [self connectApplication: NO];
  return application;
}

- (void)setActive:(BOOL)value
{
  active = value;
}

- (BOOL)isActive
{
  return active;
}

- (void)activateApplication
{
  if (isX11App) {
    /* Use X11 window manager for X11 apps */
    [[GWX11AppManager sharedManager] activateX11App: name];
    return;
  }
  
  NS_DURING
    {
      [application activateIgnoringOtherApps: YES];
    }
  NS_HANDLER
    {
      NSLog(@"Unable to activate %@", name);
      NSLog(@"Workspace caught exception %@: %@", 
            [localException name], [localException reason]);
    }
  NS_ENDHANDLER
}    

- (void)setHidden:(BOOL)value
{
  hidden = value;
}

- (BOOL)isHidden
{
  return hidden;
}

- (void)hideApplication
{
  if (isX11App) {
    /* Use X11 window manager for X11 apps */
    if ([[GWX11AppManager sharedManager] hideX11App: name]) {
      hidden = YES;
    }
    return;
  }
  
  NS_DURING
    {
      [application hide: nil];
    }
  NS_HANDLER
    {
      NSLog(@"Unable to hide %@", name);
      NSLog(@"Workspace caught exception %@: %@", 
            [localException name], [localException reason]);
    }
  NS_ENDHANDLER
}    

- (void)unhideApplication
{
  if (isX11App) {
    /* Use X11 window manager for X11 apps */
    if ([[GWX11AppManager sharedManager] unhideX11App: name]) {
      hidden = NO;
    }
    return;
  }
  
  NS_DURING
    {
  [application unhideWithoutActivation];
    }
  NS_HANDLER
    {
  NSLog(@"Unable to unhide %@", name);
  NSLog(@"Workspace caught exception %@: %@", 
	        [localException name], [localException reason]);
    }
  NS_ENDHANDLER
}    

- (BOOL)isApplicationHidden
{
  if (isX11App) {
    /* For X11 apps, check if they have visible windows */
    return ![[GWX11AppManager sharedManager] x11AppHasVisibleWindows: name];
  }
  
  BOOL apphidden = NO;
  
  if (application != nil) {
    NS_DURING
      {
    apphidden = [application isHidden];
      }
    NS_HANDLER
      {
    NSLog(@"Workspace caught exception %@: %@", 
	                      [localException name], [localException reason]);
      }
    NS_ENDHANDLER
  }
  
  return apphidden;
}

- (BOOL)gwlaunched
{
  return (task != nil);
}

- (BOOL)isRunning
{
  /* For X11 apps, check if the process still exists by PID */
  if (isX11App) {
    if (identifier) {
      pid_t pid = (pid_t)[identifier intValue];
      if (pid > 0) {
        int result = kill(pid, 0);
        return (result == 0 || errno == EPERM);
      }
    }
    return NO;
  }
  
  /* For GNUstep apps, check if we have a DO connection */
  if (application != nil) {
    return YES;
  }
  
  /* Also check if we have a task that's still running */
  if (task != nil) {
    @try {
      return [task isRunning];
    } @catch (id ex) {
      return NO;
    }
  }
  
  /* Check by PID as a last resort */
  if (identifier) {
    pid_t pid = (pid_t)[identifier intValue];
    if (pid > 0) {
      int result = kill(pid, 0);
      return (result == 0 || errno == EPERM);
    }
  }
  
  return NO;
}

- (void)terminateApplication 
{  
  if (isX11App) {
    /* For X11 apps, use the X11 app manager to quit gracefully */
    [[GWX11AppManager sharedManager] quitX11App: name timeout: 5.0];
    return;
  }
  
  if (application) {
    NS_DURING
      {
    [application terminate: nil];
      }
    NS_HANDLER
      {
    GWDebugLog(@"Workspace caught exception %@: %@", 
	                      [localException name], [localException reason]);
      }
    NS_ENDHANDLER
  } else { 
    /* if the app has no DO connection */
    [gw applicationTerminated: self];
  }
}

- (void)terminateTask 
{
  if (isX11App && identifier) {
    /* For X11 apps, send SIGTERM to the process */
    pid_t pid = (pid_t)[identifier intValue];
    if (pid > 0) {
      kill(pid, SIGTERM);
    }
    return;
  }
  
  if (task && [task isRunning]) {
    NS_DURING
      {
    [task terminate];      
      }
    NS_HANDLER
      {
    GWDebugLog(@"Workspace caught exception %@: %@", 
	                      [localException name], [localException reason]);
      }
    NS_ENDHANDLER
  }
}

- (void)taskDidTerminate:(NSNotification *)notif
{
  if ([notif object] == task) {
    [gw applicationTerminated: self];
  }
}

- (void)connectApplication:(BOOL)showProgress
{
  if (application == nil) {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *host = [defaults stringForKey: @"NSHost"];
    id app = nil;
    
    if (host == nil) {
	    host = @"";
	  } else {
	    NSHost *h = [NSHost hostWithName: host];

      if ([h isEqual: [NSHost currentHost]]) {
	      host = @"";
	    }
	  }
  
    app = [NSConnection rootProxyForConnectionWithRegisteredName: name
                                                            host: host];

    if (app) {
      NSConnection *c = [app connectionForProxy];

	    [nc addObserver: self
	           selector: @selector(connectionDidDie:)
		             name: NSConnectionDidDieNotification
		           object: c];
      
      application = app;
      RETAIN (application);
      ASSIGN (conn, c);
      
    } else {
      if ((task == nil || [task isRunning] == NO)) {
        DESTROY (task);
        return;
      }

      // Non-blocking: try once quickly without UI, then return.
      GWProcessStartupRunLoop(0.05);
      app = [NSConnection rootProxyForConnectionWithRegisteredName: name host: host];
      if (app) {
        NSConnection *c = [app connectionForProxy];
        [nc addObserver: self
               selector: @selector(connectionDidDie:)
                   name: NSConnectionDidDieNotification
                 object: c];
        application = app;
        RETAIN (application);
        ASSIGN (conn, c);
      }
    }
  }
}

- (void)connectionDidDie:(NSNotification *)notif
{
  if (conn == (NSConnection *)[notif object]) {
    [nc removeObserver: self
	                name: NSConnectionDidDieNotification
	              object: conn];

    DESTROY (application);
    DESTROY (conn);
    
    GWDebugLog(@"\"%@\" application connection did die", name);

    [gw applicationTerminated: self];
  }
}

#pragma mark - X11 App Accessors

- (BOOL)isX11App
{
  return isX11App;
}

- (void)setIsX11App:(BOOL)value
{
  isX11App = value;
}

- (NSString *)windowSearchString
{
  return windowSearchString;
}

- (void)setWindowSearchString:(NSString *)searchString
{
  ASSIGN(windowSearchString, searchString);
}

@end


@implementation NSWorkspace (WorkspaceApplication)

- (id)_workspaceApplication
{
  return [Workspace gworkspace];
}

@end

