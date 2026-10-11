/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-2.0-or-later
 */

#import <Foundation/Foundation.h>

/* The folders the user last showed in a viewer, for Go > Recent Folders.
 * Kept free of AppKit so the list rules can be tested headless. */
@interface GWRecentFolders : NSObject
{
  NSUserDefaults *defaults;
  NSString *defaultsKey;
  NSUInteger limit;
}

+ (GWRecentFolders *)sharedRecentFolders;

- (id)initWithDefaults:(NSUserDefaults *)aDefaults
                   key:(NSString *)aKey
                 limit:(NSUInteger)aLimit;

/* Moves the folder to the front; a path that is not a directory is ignored. */
- (void)noteFolderAtPath:(NSString *)path;

/* Most recent first, without folders that no longer exist. */
- (NSArray *)folderPaths;

- (void)clear;

@end
