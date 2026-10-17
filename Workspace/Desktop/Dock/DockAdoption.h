/* DockAdoption.h
 *
 * Which applications the Dock adopts when Workspace starts while they are
 * already running. GNUstep applications are known from the registry of
 * launched applications libs-gui keeps; every other application is only
 * known by its windows, and the Dock lost track of them whenever Workspace
 * restarted: they ran on without an icon. This decides, from the windows of
 * this session and the application bundles NSWorkspace knows, which bundle
 * each running X11 application belongs to.
 *
 * Foundation-only so that it can be tested headless (t_DockAdoption).
 *
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-2.0-or-later
 */

#ifndef DOCK_ADOPTION_H
#define DOCK_ADOPTION_H

#import <Foundation/Foundation.h>

/* One client window of this session, as read from _NET_CLIENT_LIST. */
extern NSString * const DockAdoptionPIDKey;          /* NSNumber, _NET_WM_PID */
extern NSString * const DockAdoptionInstanceKey;     /* WM_CLASS res_name */
extern NSString * const DockAdoptionClassKey;        /* WM_CLASS res_class */
extern NSString * const DockAdoptionTitleKey;        /* _NET_WM_NAME */
extern NSString * const DockAdoptionHiddenKey;       /* NSNumber BOOL: minimized */
extern NSString * const DockAdoptionSkipsTaskbarKey; /* NSNumber BOOL */

/* One application to adopt: DockAdoptionPathKey, DockAdoptionNameKey,
 * DockAdoptionPIDKey and DockAdoptionHiddenKey (every window minimized). */
extern NSString * const DockAdoptionPathKey;
extern NSString * const DockAdoptionNameKey;

/* The applications to adopt, in the order their first window appears in
 * clients, at most one per bundle. applications maps bundle names to paths;
 * classMap is GWWindowOwnershipClassMap of them; trackedPaths are the
 * bundles Workspace already knows to be running. Nothing launched these
 * processes from here, so a window maps to a bundle only by its WM_CLASS
 * (GWWindowOwnership); a process whose windows fit no bundle, or more than
 * one, is left out. */
NSArray *DockAdoptionPlan(NSArray *clients, NSDictionary *applications,
                          NSDictionary *classMap, NSSet *trackedPaths);

#endif
