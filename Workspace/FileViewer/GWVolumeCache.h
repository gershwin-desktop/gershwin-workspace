/* GWVolumeCache.h
 *
 * Per-volume .DS_Store cache stored at:
 *   ~/Library/Caches/com.apple.finder/<VOLUME_ID>.DS_Store
 *
 * Each record inside the cache is keyed by the absolute POSIX path
 * of the directory.  This mirrors how macOS Finder's per-volume cache
 * works, allowing interoperability: both Workspace and Finder see the
 * same cached view settings.
 *
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-2.0-or-later
 */

#import <Foundation/Foundation.h>

@class DSStoreInfo;

@interface GWVolumeCache : NSObject
{
  NSString *_cacheFilePath;
}

/**
 * Create (or return a shared instance for) the volume cache that
 * serves @p path.  The cache file path is derived via GWVolumeID.
 */
+ (instancetype)cacheForPath:(NSString *)path;

/**
 * Designated initialiser.  @p cacheFilePath is the full path to the
 * per-volume .DS_Store cache file.
 */
- (instancetype)initWithCacheFilePath:(NSString *)cacheFilePath;

/** Full path to the cache file on disk. */
@property (nonatomic, readonly) NSString *cacheFilePath;

/**
 * Read the view settings for @p dirPath from the cache.
 * Returns a fully-populated DSStoreInfo (loaded=YES) if a record
 * exists, or nil if there is no cached record for this directory.
 */
- (DSStoreInfo *)readInfoForDirectoryPath:(NSString *)dirPath;

/**
 * Write (merge) the view settings from @p info into the cache,
 * keyed by @p dirPath.  Other folders' records in the cache are
 * preserved.  Returns YES on success.
 */
- (BOOL)writeInfo:(DSStoreInfo *)info forDirectoryPath:(NSString *)dirPath;

/**
 * Write icon positions for multiple files in @p dirPath to the cache.
 * This is a convenience for callers that only need to persist icon
 * positions without a full DSStoreInfo (e.g., drag-and-drop on
 * non-writable volumes like "/").
 *
 * @p positions is an array of NSDictionaries with keys:
 *   @"name"   — NSString, filename
 *   @"x"      — NSNumber, Iloc x (top-left coordinates)
 *   @"y"      — NSNumber, Iloc y
 *
 * Existing cached view settings for @p dirPath are preserved.
 * Returns YES on success.
 */
- (BOOL)writeIconPositions:(NSArray *)positions forDirectoryPath:(NSString *)dirPath;

/**
 * Remove all cached records for @p dirPath from the cache file.
 * Returns YES on success (including when no record existed).
 */
- (BOOL)removeRecordForDirectoryPath:(NSString *)dirPath;

/**
 * Return YES if the cache file exists on disk and is readable.
 */
- (BOOL)cacheFileExists;

@end
