/* GWViewSettingsManager.h
 *
 * Central orchestrator for .DS_Store view-settings persistence.
 *
 * Implements the read/write hierarchy from the spec:
 *
 *   **Read order** (section 2):
 *     1. $FOLDER/.DS_Store
 *     2. Per-volume cache (~/Library/Caches/com.apple.finder/<VOL_ID>.DS_Store)
 *     3. Defaults (DSStoreInfo with has* == NO)
 *
 *   **Write order** (section 3):
 *     1. Try $FOLDER/.DS_Store (if writable and not policy-blocked)
 *     2. On failure → per-volume cache
 *     3. On success → clean stale entry from cache
 *
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-2.0-or-later
 */

#import <Foundation/Foundation.h>

@class DSStoreInfo;
@class GWVolumeCache;

@interface GWViewSettingsManager : NSObject
{
  NSString       *_directoryPath;
  GWVolumeCache  *_volumeCache;
}

/**
 * Create a manager for the given directory path.
 * The path is normalised (standardised, symlinks resolved) on creation.
 */
+ (instancetype)managerForDirectoryPath:(NSString *)path;

/**
 * Designated initialiser.
 */
- (instancetype)initWithDirectoryPath:(NSString *)path;

/** The normalised directory path this manager serves. */
@property (nonatomic, readonly) NSString *directoryPath;

/** The per-volume cache instance for this path's volume. */
@property (nonatomic, readonly) GWVolumeCache *volumeCache;

/**
 * Read view settings following the spec hierarchy:
 *   1. $FOLDER/.DS_Store
 *   2. Per-volume cache
 *   3. Defaults (returned as a loaded=NO DSStoreInfo)
 *
 * The returned DSStoreInfo is always non-nil.  Check its `loaded`
 * property to distinguish "found in .DS_Store" (loaded=YES) from
 * "fallback to defaults or cache" (loaded may be YES for cache hit,
 * NO for pure defaults).
 *
 * The caller is responsible for releasing the returned object.
 */
- (DSStoreInfo *)readSettings;

/**
 * Write view settings following the spec hierarchy:
 *   1. Try $FOLDER/.DS_Store (atomically)
 *      - Skips if directory is not user-writable
 *      - Skips if DSDontWriteNetworkStores is set on a network mount
 *   2. On failure → merge into per-volume cache
 *   3. On per-folder success → remove stale record from cache
 *
 * Returns YES if at least one write succeeded (folder or cache).
 */
- (BOOL)writeSettings:(DSStoreInfo *)info;

/**
 * Convenience: returns YES if the directory is directly writable
 * (write+execute for the effective user).
 */
- (BOOL)isDirectoryWritable;

/**
 * Convenience: returns YES if writing to per-folder .DS_Store is
 * blocked due to the DSDontWriteNetworkStores preference on a
 * network-mounted volume.
 */
- (BOOL)isNetworkStoreWriteBlocked;

/**
 * Check the macOS DSDontWriteNetworkStores preference.
 * Reads `defaults read com.apple.desktopservices DSDontWriteNetworkStores`.
 * Returns YES if the value is 1 or true (meaning network .DS_Store
 * writes are blocked).
 */
+ (BOOL)dsDontWriteNetworkStores;

/**
 * Return the path to the per-folder .DS_Store file.
 */
- (NSString *)folderDSStorePath;

@end
