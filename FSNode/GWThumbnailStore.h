/*
 * GWThumbnailStore.h
 *
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

/* The one place Workspace keeps whatever is expensive to make again:
 * thumbnails from the Thumbnailer bundles, AppImage icons, application
 * icons and custom icons, as PNG files of one size in
 * ~/GNUstep/Library/Thumbnails, named by GWThumbnailer's counter and
 * listed in thumbnails.plist by source path. Each entry records its
 * source's mtime and size and is used only while they match; each PNG
 * carries the same facts in its text chunks, so the index can be rebuilt
 * from the files.
 *
 * Thread-safe: any thread may read and store. Index changes are merged
 * into thumbnails.plist under an flock, so two processes sharing the
 * directory do not lose each other's entries, and written atomically, at
 * most about once a second. */

#ifndef GW_THUMBNAIL_STORE_H
#define GW_THUMBNAIL_STORE_H

#import <Foundation/Foundation.h>
#import "GWThumbnailFormat.h"

/* The largest icon size, in points, any Workspace view draws (the icon
 * view's size slider ends there); the store keeps every image at this
 * size times the scale factor, or smaller when its source is smaller. */
#define GWThumbnailMaximumPoints 512

/* Posted (distributed, by GWThumbnailer) when entries appear or go:
 * userInfo "created" and "deleted" hold arrays of source paths. */
extern NSString * const GWThumbnailsDidChangeNotification;

/* stat() of a readable regular file. A file the user cannot read must
 * not be looked up, stored or recorded as failed. */
BOOL GWThumbnailStampForPath(NSString *path, GWThumbnailFileStamp *stamp);

@class GWWorkerPool;

@interface GWThumbnailStore : NSObject
{
  GWWorkerPool *writer;
  NSString *directory;
  NSString *indexPath;
  NSString *lockPath;
  NSUInteger pixelSize;
  NSRecursiveLock *lock;
  NSMutableDictionary *index;
  NSMutableDictionary *pending;
  long counter;
  BOOL flushScheduled;
  BOOL writable;
}

/* ~/GNUstep/Library/Thumbnails, at GWThumbnailMaximumPoints times the
 * desktop's scale factor. Read-only unless setSharedStoreWritable: was
 * called first: only Workspace keeps the store, every other process
 * linking FSNode (tools, test suites) only reads it. */
+ (GWThumbnailStore *)sharedStore;

/* Called by Workspace at start, before anything asks for the store. */
+ (void)setSharedStoreWritable:(BOOL)flag;

/* Makes store the shared one, before anything asked for it: for tests and
 * tools that must not touch the user's own store. */
+ (void)setSharedStore:(GWThumbnailStore *)store;

/* Loads thumbnails.plist (rebuilding it from the PNGs when it is missing
 * or unreadable, and turning bare file names from older Workspace
 * versions into entries). */
- (id)initWithDirectory:(NSString *)aDirectory
              pixelSize:(NSUInteger)pixels
               writable:(BOOL)flag;

/* A writable store. */
- (id)initWithDirectory:(NSString *)aDirectory pixelSize:(NSUInteger)pixels;

/* A read-only store finds valid entries but never writes: storing,
 * removing and cleaning up do nothing, and index entries of older
 * Workspace versions are not migrated. */
- (BOOL)isWritable;

- (NSString *)directory;
- (NSUInteger)pixelSize;
/* pixelSize / GWThumbnailMaximumPoints: device pixels per point. */
- (CGFloat)scaleFactor;

/* Files inside the store are never stored themselves. */
- (BOOL)containsPath:(NSString *)path;

/* The entry for path as the index holds it, or nil. */
- (NSDictionary *)entryForPath:(NSString *)path;

/* The stored file of a valid entry of that kind: source is the file the
 * entry is validated against (nil: path itself). nil when there is none
 * or its source changed. */
- (NSString *)fileForPath:(NSString *)path
                     kind:(NSString *)kind
                   source:(NSString *)source;
- (NSData *)dataForPath:(NSString *)path
                   kind:(NSString *)kind
                 source:(NSString *)source;

/* Whether making an image of path already failed on this very source. */
- (BOOL)hasFailureForPath:(NSString *)path source:(NSString *)source;

/* Stores an image, scaled to pixelSize at most, as PNG and returns the
 * PNG; nil when the source cannot be stamped or nothing can be decoded.
 * watchCTime is for sources whose content changes without their mtime
 * (icons kept in extended attributes). */
- (NSData *)storeRGBA:(NSData *)rgba
                width:(NSUInteger)width
               height:(NSUInteger)height
              forPath:(NSString *)path
                 kind:(NSString *)kind
               source:(NSString *)source
           watchCTime:(BOOL)watchCTime;
- (NSData *)storeImageData:(NSData *)data
                   forPath:(NSString *)path
                      kind:(NSString *)kind
                    source:(NSString *)source;

/* storeRGBA:... on a background worker, for callers on the main thread,
 * which keep showing the image they already have meanwhile. */
- (void)storeRGBAInBackground:(NSData *)rgba
                        width:(NSUInteger)width
                       height:(NSUInteger)height
                      forPath:(NSString *)path
                         kind:(NSString *)kind
                       source:(NSString *)source
                   watchCTime:(BOOL)watchCTime;

- (BOOL)storeFailureForPath:(NSString *)path source:(NSString *)source;

/* Drops the entry of path and its file, whatever its state. */
- (BOOL)removeEntryForPath:(NSString *)path;

/* The cleanup: drops entries whose source is gone or changed (a source
 * whose whole directory is missing only after GWThumbnailOrphanAge), and
 * files no entry references - or adopts such a file when its text chunks
 * still describe its source, as after an index update lost in a crash.
 * Returns the source paths dropped. */
- (NSArray *)removeStaleEntries;

/* The same for the entries of the given paths and of everything inside
 * them, for files and folders just moved or deleted. */
- (NSArray *)removeStaleEntriesForPaths:(NSArray *)paths;

/* Moves the entries an earlier Workspace build kept in a cache directory
 * of the ~/.cache/thumbnails layout (normal/, large/, x-large/,
 * xx-large/ and fail/<software>-<version>/), those whose Software text
 * chunk is software, into this store, and deletes them there. Entries of
 * other programs are left alone, and so are entries this store already
 * has, which are at least as good. Returns how many were moved. */
- (NSUInteger)importEntriesFromCacheDirectory:(NSString *)cacheDirectory
                                     software:(NSString *)software;

/* Writes pending index changes now; otherwise they follow within about a
 * second. */
- (void)flush;

@end

#endif
