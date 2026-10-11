/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

#import <Foundation/Foundation.h>

/** argv[1] of the privileged re-exec of the application binary. */
extern const char * const FinderInfoLockHelperFlag;

/**
 * Finder's "Locked" is the user-immutable flag.  The model talks to it only
 * through this protocol so tests can substitute a recorder.
 */
@protocol FinderInfoLocking <NSObject>
- (BOOL)isImmutableAtPath:(NSString *)path;
- (BOOL)setImmutable:(BOOL)immutable atPath:(NSString *)path error:(NSError **)error;
@end

/**
 * BSD: the owner changes UF_IMMUTABLE with chflags(2) directly.  Linux:
 * FS_IMMUTABLE_FL needs CAP_LINUX_IMMUTABLE, so the change goes through the
 * application's own binary re-executed under sudo -A (the Gershwin
 * privileged helper pattern); reading the flag needs no privilege.
 */
@interface FinderInfoSystemLocker : NSObject <FinderInfoLocking>
+ (BOOL)isSupported;
@end

/**
 * The one privileged action: set or clear the immutable flag on one path.
 * Runs as root without AppKit.  Refuses relative paths, symlinks, anything
 * but regular files and folders, and (when started through sudo) files the
 * invoking user does not own, so it cannot be used to touch other people's
 * files.  requiredOwner < 0 disables the owner check.  Returns YES, or NO
 * with a one-line reason in *failure.
 */
BOOL FinderInfoApplyImmutable(NSString *path, BOOL immutable, long requiredOwner,
                              NSString **failure);

/**
 * Entry point for "<app> --set-immutable <args.plist>".  The plist holds
 * exactly Path (string) and Immutable (bool).  Prints "DONE:" or
 * "FATAL:<reason>" on stdout and returns the exit status.
 */
int FinderInfoLockHelperMain(const char *argsPlistPath);
