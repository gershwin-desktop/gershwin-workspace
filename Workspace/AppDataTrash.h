/* AppDataTrash.h
 *
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * Offers to move an application's user data (caches, logs, preferences,
 * application support) to the Trash along with the application bundle.
 */

#ifndef APPDATA_TRASH_H
#define APPDATA_TRASH_H

#import <Foundation/Foundation.h>

@interface AppDataTrash : NSObject

/* Returns the existing related user-data paths for the application bundle
 * at appPath (user domain only), or nil when none exist or appPath is not
 * a bundle.  Never scans arbitrary filesystem locations. */
+ (NSArray *)relatedUserDataPathsForApplicationAtPath:(NSString *)appPath;

/* Shows the confirmation dialog listing relatedPaths (each with its own
 * checkbox) that would be moved to the Trash along with appName.  Returns
 * YES to proceed (trash the app bundle), NO to cancel.  If YES,
 * *pathsToMove is set to the subset of relatedPaths the user checked. */
+ (BOOL)confirmTrashForApplicationNamed:(NSString *)appName
                          relatedPaths:(NSArray *)relatedPaths
                           pathsToMove:(NSArray **)pathsToMove;

/* Moves each path in paths to the user's Trash, resolving name collisions
 * by appending _copy, _copy2, ...  Items that are missing or fail to move
 * are skipped so one failure never blocks the others. */
+ (void)movePathsToTrash:(NSArray *)paths;

@end

#endif
