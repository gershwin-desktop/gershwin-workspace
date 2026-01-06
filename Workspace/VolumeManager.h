/* VolumeManager.h
 *
 * Manages mounting and unmounting of disk image files (DMG, ISO, BIN, NRG, IMG, MDF)
 * using darling-dmg and fuseiso tools
 */

#import <Foundation/Foundation.h>

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
 * VolumeManager handles mounting and unmounting of disk images
 */
@interface VolumeManager : NSObject
{
  NSMutableDictionary *mountedVolumes;       /* Maps image path to mount point */
  NSMutableDictionary *mountedVolumesPIDs;   /* Maps image path to NSNumber(pid) */
  NSMutableSet *diskImageMountPoints;        /* Set of mount points that are disk images (DMG/ISO) */
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
 * Returns YES if fuseiso is available
 */
- (BOOL)isFuseisoAvailable;

/**
 * Unmount all mounted images on shutdown
 */
- (void)unmountAll;

@end
