/* VolumeManager.h
 *
 * Manages mounting and unmounting of disk image files (DMG, ISO, BIN, NRG, IMG, MDF).
 * DMG files are mounted by trying darling-dmg first, then apfs-fuse as a fallback;
 * ISO/BIN/NRG/IMG/MDF are handled by fuseiso.
 *
 * Also supports AVFS (A Virtual File System) for browsing archives and compressed
 * files (tar, tar.gz, tar.bz2, zip, rar, 7z, etc.) via FUSE.
 *
 * Note: For SSH/SFTP, sshfs is given precedence as it provides better user experience.
 * AVFS ssh/sftp handlers are not used.
 */

#import <Foundation/Foundation.h>
#import "FileViewer/GWVolumeID.h"

@class AVFSMount;

/**
 * Returns YES only if @p mountPoint is really attached in the kernel's own
 * mount table right now. stat()/statfs() on the path itself cannot answer
 * this safely: it is true for any directory that merely exists (including
 * one a FUSE helper mounted and then died under, leaving a stale, already
 * -unmounted directory behind), and it can BLOCK forever if the process
 * that mounted the path is still there but wedged, because that syscall
 * has to cross into whatever filesystem is mounted there to answer.
 * Reading the mount table instead never touches the path's own inode, so
 * it is both correct for a stale directory and unable to hang on a live
 * but unresponsive one. Header-only (not VolumeManager.m) so a test can
 * exercise it without pulling in VolumeManager's own AppKit/Workspace
 * dependencies.
 */
static inline BOOL VMPathIsActiveMountPoint(NSString *mountPoint)
{
  NSArray *table = [GWVolumeID mountedFilesystems];
  NSDictionary *entry;

  for (entry in table) {
    if ([[entry objectForKey:@"mountPoint"] isEqualToString:mountPoint]) {
      return YES;
    }
  }
  return NO;
}

/**
 * Result object for mount operations
 */
@interface VolumeMountResult : NSObject
{
  BOOL success;
  NSString *mountPoint;
  NSString *errorMessage;
  int processId;
}

@property (nonatomic, assign) BOOL success;
@property (nonatomic, copy) NSString *mountPoint;
@property (nonatomic, copy) NSString *errorMessage;
@property (nonatomic, assign) int processId;

+ (VolumeMountResult *)successWithPath:(NSString *)path pid:(int)pid;
+ (VolumeMountResult *)failureWithError:(NSString *)error;

@end

/**
 * VolumeManager handles mounting and unmounting of disk images and archives
 */
@interface VolumeManager : NSObject
{
  NSMutableDictionary *mountedVolumes;       /* Maps image path to mount point */
  NSMutableDictionary *mountedVolumesPIDs;   /* Maps image path to NSNumber(pid) */
  NSMutableSet *diskImageMountPoints;        /* Set of mount points that are disk images (DMG/ISO) */
  NSMutableSet *avfsVirtualPaths;            /* Set of active AVFS virtual paths */
  NSFileManager *fm;
}

/**
 * Returns the shared singleton instance
 */
+ (VolumeManager *)sharedManager;

/**
 * Check if a given path is a disk image mount point (DMG/ISO/etc)
 */
+ (BOOL)isDiskImageMount:(NSString *)path;

/**
 * Mount a DMG file and return the mount point path
 */
- (NSString *)mountDMGFile:(NSString *)dmgPath;

/**
 * Mount an ISO file and return the mount point path
 */
- (NSString *)mountISOFile:(NSString *)isoPath;

/**
 * Mount a fuseiso-supported image (ISO, BIN, NRG, IMG, MDF)
 */
- (NSString *)mountFuseisoImage:(NSString *)imagePath;

/**
 * Asynchronous variants of the two mount methods above: the mount itself -
 * launching the helper tool and waiting for it to attach, which alone can
 * take up to roughly ten seconds - runs on a background thread instead of
 * the caller's, so a caller on the main thread (typically reacting to a
 * double-click) stays responsive. selector is sent to target on the main
 * thread once mounting finishes, with the resulting mount point as its
 * single argument, or nil if mounting failed (a failure alert has already
 * been shown by then, exactly as the synchronous calls above do).
 */
- (void)mountDMGFile:(NSString *)dmgPath onMainThread:(id)target selector:(SEL)selector;
- (void)mountFuseisoImage:(NSString *)imagePath onMainThread:(id)target selector:(SEL)selector;

/**
 * Unmount an image file by its path
 */
- (BOOL)unmountImageFile:(NSString *)imagePath;

/**
 * Unmount by mount point path
 */
- (BOOL)unmountPath:(NSString *)mountPath;

/**
 * Returns YES if darling-dmg is available
 */
- (BOOL)isDarlingDmgAvailable;

/**
 * Returns YES if apfs-fuse is available
 */
- (BOOL)isApfsFuseAvailable;

/**
 * Returns YES if fuseiso is available
 */
- (BOOL)isFuseisoAvailable;

/**
 * Returns YES if AVFS is available
 */
- (BOOL)isAvfsAvailable;

/**
 * Check if a file can be opened via AVFS (archives, compressed files)
 * This does NOT include disk images (ISO, DMG) or SSH/SFTP (handled by sshfs)
 */
- (BOOL)isAvfsSupportedFile:(NSString *)path;

/**
 * Open an archive or compressed file via AVFS
 * Returns the virtual path that can be browsed like a directory
 * 
 * Supported formats include:
 * - Archives: tar, zip, rar, 7z, ar, cpio, lha, zoo, rpm, deb
 * - Compressed: gz, bz2, xz, lzma, zstd, lzip
 * - Combined: tar.gz, tar.bz2, tar.xz, tgz, tbz2, txz, etc.
 */
- (NSString *)openAvfsArchive:(NSString *)archivePath;

/**
 * Get an array of all file extensions supported by AVFS
 */
- (NSArray *)avfsSupportedExtensions;

/**
 * Unmount all mounted images on shutdown
 */
- (void)unmountAll;

@end
