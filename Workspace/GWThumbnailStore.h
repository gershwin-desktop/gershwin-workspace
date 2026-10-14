/*
 * GWThumbnailStore.h
 *
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

/* One program's view of the shared thumbnail cache: reads entries
 * any program wrote, writes its own (0600, atomically via a temporary file
 * and rename) together with failure records, and sweeps away only entries
 * it wrote itself. Immutable after init and built on plain POSIX calls, so
 * one instance can serve several background threads at once. */

#ifndef GW_THUMBNAIL_STORE_H
#define GW_THUMBNAIL_STORE_H

#import <Foundation/Foundation.h>
#import "GWThumbnailSpec.h"

/* stat() of a readable regular file. The standard forbids reading or
 * writing the cache for an original the user cannot read, so a NO here
 * means: leave the cache alone. */
BOOL GWThumbnailStampForPath(NSString *path, GWThumbnailFileStamp *stamp);

@interface GWThumbnailStore : NSObject
{
  NSString *directory;
  NSString *software;
  NSString *mimeType;
  NSString *program;
  NSString *failureDirectory;
}

/* $XDG_CACHE_HOME/thumbnails or $HOME/.cache/thumbnails of this process. */
+ (NSString *)defaultDirectory;

/* software goes into the Software key and is how the sweep recognises
 * its own entries; program and version name the fail/ subdirectory. */
- (id)initWithDirectory:(NSString *)aDirectory
               software:(NSString *)aSoftware
               mimeType:(NSString *)aMimeType
                program:(NSString *)aProgram
                version:(NSString *)aVersion;

- (NSString *)directory;

/* Files inside the cache are never thumbnailed themselves. */
- (BOOL)containsPath:(NSString *)path;

/* The valid entry for path in the size directory for pixels, or nil. */
- (NSData *)thumbnailForPath:(NSString *)path
                       stamp:(GWThumbnailFileStamp)stamp
                      pixels:(NSUInteger)pixels;

/* Whether this program already failed on exactly this version of path. */
- (BOOL)hasFailureForPath:(NSString *)path
                    stamp:(GWThumbnailFileStamp)stamp;

/* Scales a PNG icon into the size box for pixels, writes it with the
 * standard's metadata and returns the written PNG; nil when icon is not
 * a PNG. A failed write is logged, the thumbnail is still returned. */
- (NSData *)storeIconData:(NSData *)icon
                  forPath:(NSString *)path
                    stamp:(GWThumbnailFileStamp)stamp
                   pixels:(NSUInteger)pixels;

- (BOOL)storeFailureForPath:(NSString *)path
                      stamp:(GWThumbnailFileStamp)stamp;

/* Deletes this program's entries whose original is gone or changed, in
 * every size directory and in every fail/ directory of this program
 * (older versions included). Returns how many were deleted. */
- (NSUInteger)removeStaleEntries;

/* The same for the entries of one original, for a file Workspace itself
 * just deleted or moved away. */
- (NSUInteger)removeStaleEntriesForPath:(NSString *)path;

@end

#endif
