/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-2.0-or-later
 */

#import <Foundation/Foundation.h>

/* Opening a stationery pad (fdFlags 0x0800) opens a new copy of it, as the
 * Finder does, and leaves the pad itself untouched. */
@interface GWStationery : NSObject

/* The first free name for the copy, next to the pad: "name copy.ext", then
 * "name copy 2.ext" and so on. */
+ (NSString *)copyPathForStationeryAtPath:(NSString *)path;

/* Copies the pad with its Finder metadata (type, creator, label, comment)
 * and clears the stationery flag on the copy only.  Returns the copy's path,
 * or nil with *error set when the copy or its metadata could not be made. */
+ (NSString *)makeCopyOfStationeryAtPath:(NSString *)path error:(NSError **)error;

@end
