/* NetworkVolumeManager.h
 *  
 * Author: Simon Peter
 * Date: January 2026
 *
 * Manages mounting and unmounting of network volumes (SFTP, AFP, etc.)
 */

#import <Foundation/Foundation.h>

@class NetworkServiceItem;

/**
 * NetworkVolumeManager handles the mounting and unmounting of network
 * volumes using platform-specific tools like FUSE sshfs on Linux/BSD.
 *
 * This class provides an abstraction layer over different mounting mechanisms
 * and handles error conditions gracefully.
 */
@interface NetworkVolumeManager : NSObject
{
  NSMutableDictionary *mountedVolumes;  /* Maps service identifier to mount point */
  NSFileManager *fm;
}

/**
 * Returns the shared singleton instance.
 */
+ (NetworkVolumeManager *)sharedManager;

/**
 * Attempts to mount an SFTP service at a standard mount point.
 * Returns the mount point path on success, nil on failure.
 *
 * This method checks if sshfs is available and prompts the user if it's not.
 *
 * @param serviceItem The SFTP service to mount
 * @return The path where the service was mounted, or nil on failure
 */
- (NSString *)mountSFTPService:(NetworkServiceItem *)serviceItem;

/**
 * Unmounts a previously mounted network service.
 *
 * @param serviceItem The service to unmount
 * @return YES if unmounted successfully, NO otherwise
 */
- (BOOL)unmountService:(NetworkServiceItem *)serviceItem;

/**
 * Returns the mount point for a given service, if currently mounted.
 *
 * @param serviceItem The service to check
 * @return The mount point path, or nil if not mounted
 */
- (NSString *)mountPointForService:(NetworkServiceItem *)serviceItem;

/**
 * Returns YES if the given service is currently mounted.
 */
- (BOOL)isServiceMounted:(NetworkServiceItem *)serviceItem;

/**
 * Checks if sshfs (FUSE) is available on the system.
 *
 * @return YES if sshfs is available, NO otherwise
 */
- (BOOL)isSshfsAvailable;

/**
 * Unmounts all currently mounted network volumes.
 * Typically called during application shutdown.
 */
- (void)unmountAll;

@end
