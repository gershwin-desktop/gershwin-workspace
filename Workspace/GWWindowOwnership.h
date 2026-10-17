/* GWWindowOwnership.h
 *
 * Which application a window of another program belongs to. The Dock and
 * Workspace used to decide this by comparing the application's name with
 * the start or end of window titles, so a browser window titled "Claude
 * Desktop on Linux - ..." counted as a window of the docked Claude Desktop:
 * a click on that icon raised the browser, and the browser gave the icon its
 * running dot. Every place that has to tie a window to an application asks
 * this one decision instead, so the rules exist once:
 *
 * 1. Once the application's process is known, only windows of that process
 *    or of a process it started belong to it. Names are not consulted.
 * 2. Without a known process, the window's WM_CLASS (instance or class)
 *    must name the application: its bundle name or a class it declares with
 *    the GSX11WindowClass Info.plist key, compared without case, spaces,
 *    hyphens and underscores.
 * 3. A title alone never identifies a window. A title naming the
 *    application could only be accepted for a window of the launched
 *    process, which rule 1 already accepts.
 * 4. A window whose WM_CLASS names another known bundle never belongs to
 *    this one through a started process or a name.
 *
 * GSX11WindowClass (Info.plist, string or array of strings): the WM_CLASS
 * instance or class the program of a wrapper .app shows when it differs
 * from the bundle's name, e.g. "vlc" for "VLC media player.app".
 *
 * Foundation-only, so that it can be tested headless (t_GWWindowOwnership).
 *
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

#ifndef GW_WINDOW_OWNERSHIP_H
#define GW_WINDOW_OWNERSHIP_H

#import <Foundation/Foundation.h>
#include <sys/types.h>

/* The Info.plist key a wrapper bundle names its program's WM_CLASS with. */
extern NSString * const GWWindowClassInfoKey;

typedef enum
{
  /* Nothing ties the window to the application. */
  GWWindowNotOwned = 0,
  /* The application's process is known and the window comes from a process
   * that is neither it nor one it started. */
  GWWindowNotOwnedOtherProcess,
  /* The window's WM_CLASS names another known bundle. */
  GWWindowNotOwnedClassOfOtherBundle,
  /* Only the title names the application, and no process confirms it. */
  GWWindowNotOwnedTitleOnly,
  /* The window comes from the launched process itself. */
  GWWindowOwnedLaunchedProcess,
  /* The window comes from a process the launched process started. */
  GWWindowOwnedDescendantProcess,
  /* No process is known, and the window's WM_CLASS names the application. */
  GWWindowOwnedClass
} GWWindowOwnershipReason;

/* YES when pid was started, directly or further down, by ancestor. */
typedef BOOL (*GWProcessAncestryFunction)(pid_t pid, pid_t ancestor);

BOOL GWWindowOwnershipReasonIsOwned(GWWindowOwnershipReason reason);
NSString *GWWindowOwnershipReasonDescription(GWWindowOwnershipReason reason);

/* A WM_CLASS or bundle name without case, spaces, hyphens and underscores:
 * "brave-origin", "Brave Origin" and "Brave_Origin" all fold alike. */
NSString *GWWindowOwnershipFolded(NSString *name);

/* The classes an Info.plist declares under GWWindowClassInfoKey. */
NSArray *GWWindowOwnershipClassHintsInInfo(NSDictionary *info);

/* The same, read from the bundle at path. */
NSArray *GWWindowOwnershipClassHintsForBundle(NSString *path);

/* Folded WM_CLASS -> bundle path for every bundle in applications (name ->
 * path), from the bundles' names and the hints in hintsByPath (path ->
 * array of classes). Where two bundles fold alike, the first by sorted
 * name keeps the class. */
NSDictionary *GWWindowOwnershipClassMap(NSDictionary *applications,
                                        NSDictionary *hintsByPath);

/* The applications of an application list as make_services writes it
 * (.GNUstepAppList, "Name.app" -> path), by name. */
NSDictionary *GWWindowOwnershipApplicationsInAppList(NSDictionary *appList);

/* The applications of this user's application list, by name, or nil when
 * there is none. */
NSDictionary *GWWindowOwnershipInstalledApplications(void);

/* GWWindowOwnershipClassMap of the installed applications, with their
 * hints read from their bundles; read again when the list changes. */
NSDictionary *GWWindowOwnershipInstalledClassMap(void);

/* One application, asked about one window after another, on one thread. */
@interface GWWindowOwnership : NSObject
{
  NSString *appName;
  NSString *appPath;
  pid_t launchedPID;
  NSSet *ownClasses;
  NSDictionary *classMap;
  GWProcessAncestryFunction ancestry;
  NSMutableDictionary *descends;
}

- (id)initWithName:(NSString *)name
              path:(NSString *)path
       launchedPID:(pid_t)pid
        classHints:(NSArray *)hints
          classMap:(NSDictionary *)map
          ancestry:(GWProcessAncestryFunction)ancestryFunction;

- (NSString *)appName;
- (NSString *)appPath;
- (pid_t)launchedPID;

- (GWWindowOwnershipReason)reasonForWindowPID:(pid_t)pid
                                     instance:(NSString *)instance
                                  windowClass:(NSString *)windowClass
                                        title:(NSString *)title;

- (BOOL)ownsWindowPID:(pid_t)pid
             instance:(NSString *)instance
          windowClass:(NSString *)windowClass
                title:(NSString *)title;

@end

#endif
