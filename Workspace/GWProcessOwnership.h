/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

#ifndef GWPROCESSOWNERSHIP_H
#define GWPROCESSOWNERSHIP_H

#import <Foundation/Foundation.h>
#include <sys/types.h>

/* userInfo key naming the X display a launch is meant for.  Set on the
 * NSWorkspaceWillLaunchApplicationNotification Workspace posts, because that
 * notification is sent before the application has a process identifier. */
extern NSString * const GWLaunchDisplayKey;

/**
 * Decides whether a process belongs to the session this Workspace serves:
 * it runs as the current user AND on the same X display and screen.
 *
 * Workspace notifications travel through the per-user distributed
 * notification center, which every session of the same user shares (e.g. a
 * second X display), and X11 window lists contain windows of every user
 * allowed on the display.  Neither may put icons into this session's Dock.
 */
@interface GWProcessOwnership : NSObject

/** The display this Workspace talks to (DISPLAY), or nil. */
+ (NSString *)currentDisplay;

/** YES when both names denote the same X server and screen.  Unparsable
 * names never match. */
+ (BOOL)display:(NSString *)display isSameAsDisplay:(NSString *)other;

/** YES when pid is alive and its effective user is the current user. */
+ (BOOL)isProcessOwnedByCurrentUser:(pid_t)pid;

/** DISPLAY from the environment of pid, or nil if it has none or the
 * environment is not readable (another user's process). */
+ (NSString *)displayOfProcess:(pid_t)pid;

/** Owned by the current user and running on the current display/screen. */
+ (BOOL)isProcessInCurrentSession:(pid_t)pid;

/** Attributes a workspace notification by its NSApplicationProcessIdentifier
 * or, when there is none yet, by its GWLaunchDisplayKey.  Notifications that
 * carry neither cannot be attributed and are not ours. */
+ (BOOL)isNotificationInfoInCurrentSession:(NSDictionary *)info;

@end

#endif
