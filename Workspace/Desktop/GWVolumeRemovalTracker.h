/* GWVolumeRemovalTracker.h
 *
 * Decides which volumes that vanished from the mount table the desktop
 * reports as "removed without being properly ejected".  Kept apart from
 * GWDesktopView so the decision can be exercised headless, without a
 * desktop, an alert panel or a live mount table.
 *
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

#ifndef GW_VOLUME_REMOVAL_TRACKER_H
#define GW_VOLUME_REMOVAL_TRACKER_H

#import <Foundation/Foundation.h>

@interface GWVolumeRemovalTracker : NSObject
{
  NSTimeInterval lifetime;
  NSMutableDictionary *announcements; /* mount point -> NSDate */
  NSMutableSet *reported;
}

- (id)initWithAnnouncementLifetime:(NSTimeInterval)seconds;

/* An unmount of the volume at path was announced (Workspace's own eject,
 * or another app posting NSWorkspaceWillUnmountNotification). */
- (void)noteUnmountAnnouncedAtPath:(NSString *)path date:(NSDate *)date;

/* A volume appeared at path; it starts with a clean slate. */
- (void)noteVolumeMountedAtPath:(NSString *)path;

/* The paths among vanished that deserve an alert, each at most once. */
- (NSArray *)removalsToReportForVanishedPaths:(NSArray *)vanished
                                         date:(NSDate *)now;

/* Re-checks candidates returned above just before the alert is shown,
 * dropping those whose unmount was announced in the meantime. */
- (NSArray *)confirmedRemovalsAmongPaths:(NSArray *)candidates
                                    date:(NSDate *)now;

@end

#endif
