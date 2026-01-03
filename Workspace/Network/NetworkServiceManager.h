/* NetworkServiceManager.h
 *  
 * Author: Simon Peter
 * Date: January 2026
 *
 */

#import <Foundation/Foundation.h>

@class NetworkServiceItem;

/**
 * Notification posted when the list of discovered services changes.
 * The userInfo dictionary contains:
 *   - "addedServices": NSArray of NetworkServiceItem objects that were added
 *   - "removedServices": NSArray of NetworkServiceItem objects that were removed
 */
extern NSString * const NetworkServicesDidChangeNotification;

/**
 * Notification posted when a service is fully resolved.
 * The userInfo dictionary contains:
 *   - "service": The NetworkServiceItem that was resolved
 */
extern NSString * const NetworkServiceDidResolveNotification;

/**
 * NetworkServiceManager is a singleton that manages mDNS service discovery
 * for network file sharing services (_sftp-ssh and _afpovertcp).
 *
 * This class can be used throughout Workspace to access the current list
 * of available network services.
 */
@interface NetworkServiceManager : NSObject <NSNetServiceBrowserDelegate, NSNetServiceDelegate>
{
  NSNetServiceBrowser *sftpBrowser;
  NSNetServiceBrowser *afpBrowser;
  NSMutableArray *services;           // Array of NetworkServiceItem
  NSMutableArray *pendingResolutions; // Array of NSNetService being resolved
  BOOL isSearching;
  BOOL mDNSAvailable;
}

/**
 * Returns the shared instance of the NetworkServiceManager.
 */
+ (instancetype)sharedManager;

/**
 * Returns YES if mDNS/DNS-SD support is available.
 */
- (BOOL)isMDNSAvailable;

/**
 * Starts browsing for network services if not already browsing.
 */
- (void)startBrowsing;

/**
 * Stops browsing for network services.
 */
- (void)stopBrowsing;

/**
 * Returns YES if currently browsing for services.
 */
- (BOOL)isBrowsing;

/**
 * Returns an array of all currently discovered NetworkServiceItem objects.
 * The returned array is a copy and can be safely used.
 */
- (NSArray *)allServices;

/**
 * Returns an array of SFTP/SSH service items only.
 */
- (NSArray *)sftpServices;

/**
 * Returns an array of AFP service items only.
 */
- (NSArray *)afpServices;

/**
 * Returns the number of discovered services.
 */
- (NSUInteger)serviceCount;

/**
 * Returns the service at the given index.
 */
- (NetworkServiceItem *)serviceAtIndex:(NSUInteger)index;

/**
 * Returns the service with the given identifier, or nil if not found.
 */
- (NetworkServiceItem *)serviceWithIdentifier:(NSString *)identifier;

@end
