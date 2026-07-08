/* GWVolumeID.h
 *
 * Stable volume identifier for .DS_Store per-volume cache.
 * Provides volume UUID from statfs, network/read-only detection,
 * and cache path generation matching macOS Finder's convention:
 *   ~/Library/Caches/com.apple.finder/<VOLUME_ID>.DS_Store
 *
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-2.0-or-later
 */

#import <Foundation/Foundation.h>

@interface GWVolumeID : NSObject

/**
 * Return a stable identifier string for the volume containing @p path.
 * On Linux: hex-encoded f_fsid (two 32-bit ints) from statfs.
 * Falls back to an MD5 hash of the mount source if f_fsid is zero.
 * Results are cached in-process.
 */
+ (NSString *)volumeIDForPath:(NSString *)path;

/**
 * Return the cache directory ~/Library/Caches/com.apple.finder/,
 * creating it if necessary.
 */
+ (NSString *)cacheDirectory;

/**
 * Return the full path to the per-volume cache file for @p path:
 *   ~/Library/Caches/com.apple.finder/<VOLUME_ID>.DS_Store
 */
+ (NSString *)cacheFilePathForPath:(NSString *)path;

/**
 * Return YES if @p path resides on a network mount.
 * On Linux: checks f_type for NFS (0x6969), CIFS/SMB (0xFF534D42),
 * or any FUSE mount (0xBEEF) whose source contains common network
 * indicators (sshfs, gvfsd, etc.).
 */
+ (BOOL)isNetworkMount:(NSString *)path;

/**
 * Return YES if @p path resides on a read-only volume.
 * Checks statfs f_flags & MS_RDONLY (Linux) or MNT_RDONLY (BSD).
 */
+ (BOOL)isReadOnlyVolume:(NSString *)path;

/**
 * Return the filesystem type name (e.g. @"ext4", @"nfs", @"fuseblk").
 * Uses statfs f_type mapped to well-known magic numbers.
 */
+ (NSString *)filesystemTypeForPath:(NSString *)path;

/**
 * Return the mount source device path for the volume containing @p path.
 * On Linux reads /proc/self/mountinfo; on BSD uses f_mntfromname.
 */
+ (NSString *)mountSourceForPath:(NSString *)path;

/**
 * Return the mount point for the volume containing @p path.
 */
+ (NSString *)mountPointForPath:(NSString *)path;

/**
 * Flush the in-process volume-ID cache (useful when volumes change).
 */
+ (void)flushCache;

@end
