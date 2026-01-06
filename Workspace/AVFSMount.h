/* AVFSMount.h
 *
 * AVFS (A Virtual File System) support for mounting and browsing archives
 * using FUSE. AVFS provides transparent access to compressed files and
 * archives (tar, tar.gz, tar.bz2, zip, rar, 7z, etc.) as well as remote
 * filesystems (ftp, http, webdav, etc.).
 *
 * Note: For SSH/SFTP, sshfs is given precedence as it's already implemented
 * in the Network subsystem and provides a better user experience.
 */

#ifndef AVFSMOUNT_H
#define AVFSMOUNT_H

#import <Foundation/Foundation.h>

/**
 * File type categories supported by AVFS
 * Note: Disk images (ISO, DMG, etc.) are NOT handled by AVFS - use fuseiso/darling-dmg
 */
typedef NS_ENUM(NSInteger, AVFSFileType) {
  AVFSFileTypeUnknown = 0,
  AVFSFileTypeArchive,       /* tar, zip, rar, 7z, ar, cpio, lha, zoo, rpm, deb */
  AVFSFileTypeCompressed,    /* gz, bz2, xz, lzma, zstd, lzip */
  AVFSFileTypeCompressedArchive, /* tar.gz, tar.bz2, tar.xz, etc. */
  AVFSFileTypeRemote,        /* ftp, http, webdav (note: ssh handled by sshfs) */
  AVFSFileTypePatch          /* patch files via patchfs */
};

/**
 * Result object returned from AVFS mount attempts
 */
@interface AVFSMountResult : NSObject
{
  BOOL success;
  NSString *virtualPath;   /* The AVFS virtual path (e.g., ~/.avfs/path/file.tar.gz#) */
  NSString *errorMessage;
}

@property(nonatomic, assign) BOOL success;
@property(nonatomic, retain) NSString *virtualPath;
@property(nonatomic, retain) NSString *errorMessage;

+ (instancetype)successWithPath:(NSString *)path;
+ (instancetype)failureWithError:(NSString *)error;

@end

/**
 * AVFSMount handles all AVFS-related operations
 */
@interface AVFSMount : NSObject
{
  NSString *avfsBasePath;   /* Usually ~/.avfs */
  BOOL avfsDaemonRunning;
}

/**
 * Returns the shared singleton instance
 */
+ (AVFSMount *)sharedInstance;

/**
 * Check if avfsd (AVFS FUSE daemon) is available on the system
 * @return YES if avfsd binary exists and is executable
 */
- (BOOL)isAvfsAvailable;

/**
 * Check if the AVFS daemon is currently running and mounted
 * @return YES if ~/.avfs is mounted via avfsd
 */
- (BOOL)isAvfsDaemonRunning;

/**
 * Ensure the AVFS daemon is running, starting it if necessary
 * @return YES if daemon is now running, NO on failure
 */
- (BOOL)ensureAvfsDaemonRunning;

/**
 * Stop the AVFS daemon (typically called on application shutdown)
 * @return YES if successfully stopped
 */
- (BOOL)stopAvfsDaemon;

/**
 * Get the AVFS base path (typically ~/.avfs)
 * @return The base path where AVFS is mounted
 */
- (NSString *)avfsBasePath;

/**
 * Determine the AVFS file type for a given file extension
 * @param extension The file extension (without leading dot)
 * @return The AVFSFileType category
 */
- (AVFSFileType)fileTypeForExtension:(NSString *)extension;

/**
 * Check if a file can be handled by AVFS based on its extension
 * @param path The path to the file
 * @return YES if AVFS can provide virtual access to this file
 */
- (BOOL)canHandleFile:(NSString *)path;

/**
 * Get the virtual AVFS path for accessing a file's contents
 * The daemon will be started automatically if not running.
 * 
 * For archives (tar.gz, zip, etc.), this returns the path that can be
 * browsed like a directory.
 *
 * @param path The path to the archive/compressed file
 * @return AVFSMountResult with the virtual path or error
 */
- (AVFSMountResult *)virtualPathForFile:(NSString *)path;

/**
 * Get an array of all file extensions supported by AVFS
 * Note: Does not include ssh/sftp as those are handled by sshfs
 * @return Array of lowercase extension strings
 */
- (NSArray *)supportedExtensions;

/**
 * Get an array of archive file extensions
 * @return Array of archive extension strings (tar, zip, rar, 7z, etc.)
 */
- (NSArray *)archiveExtensions;

/**
 * Get an array of compressed file extensions (single-file compression)
 * @return Array of compression extension strings (gz, bz2, xz, etc.)
 */
- (NSArray *)compressionExtensions;

/**
 * Show alert dialog informing user that AVFS is not installed
 */
- (void)showAvfsNotInstalledAlert;

@end

#endif /* AVFSMOUNT_H */
