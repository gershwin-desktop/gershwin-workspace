/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#ifndef BOOTABLE_FILE_COPIER_H
#define BOOTABLE_FILE_COPIER_H

#import <Foundation/Foundation.h>

@class BootableFileCopier;

/**
 * Copy operation result
 */
@interface BootableCopyResult : NSObject
{
  BOOL _success;
  NSString *_errorMessage;
  NSString *_failedPath;
  unsigned long long _bytesCopied;
  unsigned long long _filesCopied;
  unsigned long long _directoriesCopied;
  unsigned long long _symlinksCopied;
  unsigned long long _hardlinksCopied;
  unsigned long long _specialFilesCopied;
  NSTimeInterval _elapsedTime;
}

@property (nonatomic, assign) BOOL success;
@property (nonatomic, copy) NSString *errorMessage;
@property (nonatomic, copy) NSString *failedPath;
@property (nonatomic, assign) unsigned long long bytesCopied;
@property (nonatomic, assign) unsigned long long filesCopied;
@property (nonatomic, assign) unsigned long long directoriesCopied;
@property (nonatomic, assign) unsigned long long symlinksCopied;
@property (nonatomic, assign) unsigned long long hardlinksCopied;
@property (nonatomic, assign) unsigned long long specialFilesCopied;
@property (nonatomic, assign) NSTimeInterval elapsedTime;

+ (instancetype)successWithStats:(NSDictionary *)stats;
+ (instancetype)failureWithError:(NSString *)error path:(NSString *)path;

- (NSString *)summaryString;

@end


/**
 * Delegate protocol for copy progress updates
 */
@protocol BootableFileCopierDelegate <NSObject>

@required
/**
 * Called when overall progress changes
 * @param copier The copier instance
 * @param bytesCompleted Bytes copied so far
 * @param bytesTotal Total bytes to copy
 * @param filesCompleted Files copied so far
 * @param filesTotal Total files to copy
 */
- (void)copier:(BootableFileCopier *)copier
    didProgress:(unsigned long long)bytesCompleted
        ofTotal:(unsigned long long)bytesTotal
          files:(unsigned long long)filesCompleted
    totalFiles:(unsigned long long)filesTotal;

@optional
/**
 * Called when starting to copy a specific file/directory
 */
- (void)copier:(BootableFileCopier *)copier willCopyPath:(NSString *)path;

/**
 * Called when a file/directory is successfully copied
 */
- (void)copier:(BootableFileCopier *)copier didCopyPath:(NSString *)path;

/**
 * Called when an error occurs (allows continue/abort decision)
 * @return YES to continue, NO to abort
 */
- (BOOL)copier:(BootableFileCopier *)copier 
    shouldContinueAfterError:(NSString *)error 
                      atPath:(NSString *)path;

/**
 * Called when copy operation is cancelled
 */
- (void)copierWasCancelled:(BootableFileCopier *)copier;

@end


/**
 * Copy options flags
 */
typedef NS_OPTIONS(NSUInteger, BootableCopyOptions) {
  BootableCopyOptionNone = 0,
  BootableCopyOptionPreservePermissions = 1 << 0,
  BootableCopyOptionPreserveOwnership = 1 << 1,
  BootableCopyOptionPreserveTimestamps = 1 << 2,
  BootableCopyOptionPreserveACLs = 1 << 3,
  BootableCopyOptionPreserveXattrs = 1 << 4,
  BootableCopyOptionPreserveHardlinks = 1 << 5,
  BootableCopyOptionFollowSymlinks = 1 << 6,  // Usually OFF for system copy
  BootableCopyOptionExcludeHome = 1 << 7,
  BootableCopyOptionCrossFilesystems = 1 << 8,  // Usually OFF
  BootableCopyOptionVerifyAfterCopy = 1 << 9,
  
  // Convenience preset for full system copy
  BootableCopyOptionSystemCopy = (BootableCopyOptionPreservePermissions |
                                   BootableCopyOptionPreserveOwnership |
                                   BootableCopyOptionPreserveTimestamps |
                                   BootableCopyOptionPreserveACLs |
                                   BootableCopyOptionPreserveXattrs |
                                   BootableCopyOptionPreserveHardlinks)
};


/**
 * BootableFileCopier performs the filesystem copy for bootable installation.
 *
 * Features:
 * - Recursive copy with progress indication
 * - Preserves permissions, ownership, ACLs, xattrs
 * - Handles hardlinks and symlinks correctly
 * - Excludes virtual/runtime directories
 * - Optional /home exclusion
 * - Verification of copy completion
 * - Cancellation support
 */
@interface BootableFileCopier : NSObject
{
  NSFileManager *_fm;
  id<BootableFileCopierDelegate> _delegate;
  BootableCopyOptions _options;
  
  // Statistics
  unsigned long long _bytesTotal;
  unsigned long long _bytesCopied;
  unsigned long long _filesTotal;
  unsigned long long _filesCopied;
  unsigned long long _directoriesCopied;
  unsigned long long _symlinksCopied;
  unsigned long long _hardlinksCopied;
  unsigned long long _specialFilesCopied;
  
  // Hardlink tracking (inode -> first copied path)
  NSMutableDictionary *_hardlinkMap;
  
  // State
  BOOL _cancelled;
  BOOL _running;
  NSDate *_startTime;
  NSString *_currentPath;
  
  // Exclusion patterns
  NSSet *_excludedPaths;
  NSSet *_excludedPrefixes;
}

@property (nonatomic, assign) id<BootableFileCopierDelegate> delegate;
@property (nonatomic, assign) BootableCopyOptions options;
@property (nonatomic, readonly) BOOL isRunning;
@property (nonatomic, readonly) BOOL isCancelled;
@property (nonatomic, readonly) NSString *currentPath;

#pragma mark - Initialization

/**
 * Create a copier with default system copy options
 */
+ (instancetype)systemCopier;

/**
 * Create a copier with specified options
 */
+ (instancetype)copierWithOptions:(BootableCopyOptions)options;

- (instancetype)initWithOptions:(BootableCopyOptions)options;

#pragma mark - Configuration

/**
 * Add additional paths to exclude from copy
 */
- (void)addExcludedPath:(NSString *)path;

/**
 * Add a prefix - all paths starting with this will be excluded
 */
- (void)addExcludedPrefix:(NSString *)prefix;

/**
 * Clear custom exclusions (keeps default system exclusions)
 */
- (void)clearCustomExclusions;

/**
 * Get list of paths that will be excluded
 */
- (NSArray *)excludedPaths;

#pragma mark - Pre-copy Analysis

/**
 * Calculate total size and file count for source
 * This is used for progress indication
 * @param sourcePath The source root (typically "/")
 * @param excludeHome Whether to exclude /home
 * @return Dictionary with "totalBytes" and "totalFiles" keys
 */
- (NSDictionary *)calculateSizeForSource:(NSString *)sourcePath
                            excludeHome:(BOOL)excludeHome;

/**
 * Check if source supports all required features for full copy
 * (ACLs, xattrs, etc.)
 */
- (BOOL)sourceSupportsFullCopy:(NSString *)sourcePath 
                        reason:(NSString **)reason;

/**
 * Check if target supports all required features for full copy
 */
- (BOOL)targetSupportsFullCopy:(NSString *)targetPath 
                        reason:(NSString **)reason;

#pragma mark - Copy Operations

/**
 * Copy root filesystem to target
 * This is the main entry point for bootable installation
 *
 * @param sourcePath Source root (typically "/")
 * @param targetPath Target mount point
 * @param excludeHome Whether to exclude /home directory
 * @return Result object with success/failure and statistics
 */
- (BootableCopyResult *)copyRootFilesystem:(NSString *)sourcePath
                                  toTarget:(NSString *)targetPath
                             excludingHome:(BOOL)excludeHome;

/**
 * Copy a single file with all attributes
 */
- (BOOL)copyFile:(NSString *)sourcePath 
          toPath:(NSString *)destPath
           error:(NSError **)error;

/**
 * Copy a directory recursively
 */
- (BOOL)copyDirectory:(NSString *)sourcePath 
               toPath:(NSString *)destPath
                error:(NSError **)error;

/**
 * Copy a symbolic link
 */
- (BOOL)copySymlink:(NSString *)sourcePath 
             toPath:(NSString *)destPath
              error:(NSError **)error;

/**
 * Copy a special file (device node, socket, FIFO)
 */
- (BOOL)copySpecialFile:(NSString *)sourcePath 
                 toPath:(NSString *)destPath
                  error:(NSError **)error;

#pragma mark - Attribute Preservation

/**
 * Copy POSIX permissions from source to dest
 */
- (BOOL)copyPermissions:(NSString *)sourcePath
                 toPath:(NSString *)destPath
                  error:(NSError **)error;

/**
 * Copy ownership (uid/gid) from source to dest
 */
- (BOOL)copyOwnership:(NSString *)sourcePath
               toPath:(NSString *)destPath
                error:(NSError **)error;

/**
 * Copy timestamps from source to dest
 */
- (BOOL)copyTimestamps:(NSString *)sourcePath
                toPath:(NSString *)destPath
                 error:(NSError **)error;

/**
 * Copy ACLs from source to dest (platform-specific)
 */
- (BOOL)copyACLs:(NSString *)sourcePath
          toPath:(NSString *)destPath
           error:(NSError **)error;

/**
 * Copy extended attributes from source to dest
 */
- (BOOL)copyXattrs:(NSString *)sourcePath
            toPath:(NSString *)destPath
             error:(NSError **)error;

#pragma mark - Verification

/**
 * Verify that the copy completed successfully
 * Checks file counts, sizes, and optionally checksums
 */
- (BOOL)verifyTarget:(NSString *)targetPath
          withSource:(NSString *)sourcePath
              reason:(NSString **)reason;

/**
 * Quick verification - just checks file counts and structure
 */
- (BOOL)quickVerifyTarget:(NSString *)targetPath
               withSource:(NSString *)sourcePath
                   reason:(NSString **)reason;

#pragma mark - Control

/**
 * Cancel the current copy operation
 * The delegate will receive copierWasCancelled:
 */
- (void)cancel;

/**
 * Check if operation was cancelled
 */
- (BOOL)isCancelled;

#pragma mark - Progress Information

/**
 * Get current progress as a value 0.0-1.0
 */
- (double)progress;

/**
 * Get estimated time remaining in seconds
 */
- (NSTimeInterval)estimatedTimeRemaining;

/**
 * Get current copy speed in bytes per second
 */
- (double)currentSpeed;

/**
 * Get statistics dictionary
 */
- (NSDictionary *)statistics;

@end


#pragma mark - Directory Layout Creation

/**
 * Category for creating target directory layout
 */
@interface BootableFileCopier (DirectoryLayout)

/**
 * Create the basic directory structure for a bootable system
 * Creates: /bin, /boot, /dev, /etc, /home, /lib, /proc, /root,
 *          /run, /sbin, /sys, /tmp, /usr, /var, etc.
 */
- (BOOL)createBootableLayoutAtPath:(NSString *)targetPath
                             error:(NSError **)error;

/**
 * Create essential empty directories that should exist
 * but not be copied from source (proc, sys, dev, etc.)
 */
- (BOOL)createVirtualDirectoriesAtPath:(NSString *)targetPath
                                 error:(NSError **)error;

/**
 * Fix permissions on critical directories after copy
 */
- (BOOL)fixCriticalPermissionsAtPath:(NSString *)targetPath
                               error:(NSError **)error;

@end

#endif /* BOOTABLE_FILE_COPIER_H */
