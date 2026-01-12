/*
 * GWUnmountHelper.h
 *
 * Copyright (c) 2026 Simon Peter
 * SPDX-License-Identifier: BSD-2-Clause
 *
 * Shared utility for robust unmounting of volumes with privilege escalation
 */

#import <Foundation/Foundation.h>

@interface GWUnmountHelper : NSObject

/**
 * Find the sudo executable path (varies by OS).
 * Checks common locations: /usr/bin/sudo, /usr/local/bin/sudo, /opt/local/bin/sudo
 * @return Path to sudo executable
 */
+ (NSString *)findSudoPath;

/**
 * Robustly unmount a volume at the given path.
 * Tries multiple methods with increasing force:
 * 1. NSWorkspace unmountAndEjectDeviceAtPath (only if shouldEject=YES)
 * 2. sudo -A -E umount <path>
 * 3. sudo -A -E umount -f <path>  (force)
 * 4. sudo -A -E umount -l <path>  (lazy)
 *
 * @param mountPoint The path to unmount (e.g., "/media/user/VOLUME")
 * @param shouldEject YES to eject physical media (CD/DVD/USB), NO to only unmount filesystem
 * @return YES if unmount succeeded, NO if all attempts failed
 */
+ (BOOL)unmountPath:(NSString *)mountPoint eject:(BOOL)shouldEject;

/**
 * Unmount path with optional device path for logging.
 * Same as unmountPath:eject: but logs device path if provided.
 *
 * @param mountPoint The path to unmount
 * @param devicePath Optional device path for logging (can be nil)
 * @param shouldEject YES to eject physical media, NO to only unmount
 * @return YES if unmount succeeded, NO if all attempts failed
 */
+ (BOOL)unmountPath:(NSString *)mountPoint devicePath:(NSString *)devicePath eject:(BOOL)shouldEject;

/**
 * Convenience method: unmount and eject (default behavior for Workspace)
 */
+ (BOOL)unmountAndEjectPath:(NSString *)mountPoint;

/**
 * Convenience method: unmount without ejecting (for ISO writing, CDROM burning)
 */
+ (BOOL)unmountPath:(NSString *)mountPoint;

@end
