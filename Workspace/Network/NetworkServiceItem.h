/* NetworkServiceItem.h
 *  
 * Author: Simon Peter
 * Date: January 2026
 *
 */

#import <Foundation/Foundation.h>

/**
 * NetworkServiceItem represents a discovered network service.
 * This is a value object that holds information about an mDNS service.
 */
@interface NetworkServiceItem : NSObject <NSCopying>
{
  NSString *name;
  NSString *type;         // e.g., "_sftp-ssh._tcp." or "_afpovertcp._tcp."
  NSString *domain;
  NSString *hostName;
  int port;
  NSArray *addresses;
  NSNetService *netService;
  BOOL resolved;
  
  /* Manual connection support - these override TXT record values if set */
  NSString *manualUsername;
  NSString *manualRemotePath;
}

@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *type;
@property (nonatomic, copy) NSString *domain;
@property (nonatomic, copy) NSString *hostName;
@property (nonatomic, assign) int port;
@property (nonatomic, retain) NSArray *addresses;
@property (nonatomic, retain) NSNetService *netService;
@property (nonatomic, assign) BOOL resolved;

+ (instancetype)itemWithNetService:(NSNetService *)service;

- (instancetype)initWithNetService:(NSNetService *)service;

/**
 * Returns a user-friendly display name for the service.
 */
- (NSString *)displayName;

/**
 * Returns a unique identifier for this service.
 */
- (NSString *)identifier;

/**
 * Returns YES if this is an SFTP/SSH service.
 */
- (BOOL)isSFTPService;

/**
 * Returns YES if this is an AFP service.
 */
- (BOOL)isAFPService;

/**
 * Returns YES if this is a WebDAV service (HTTP or HTTPS).
 */
- (BOOL)isWebDAVService;

/**
 * Returns YES if this is a secure WebDAV service (HTTPS).
 */
- (BOOL)isSecureWebDAV;

/**
 * Returns the icon name for this service type.
 */
- (NSString *)iconName;

/**
 * Returns the remote path from the TXT record, if available.
 * For SFTP services, this is often in the 'path' key.
 * Returns nil if no path is specified.
 * Can be set manually for non-discovered services.
 */
- (NSString *)remotePath;
- (void)setRemotePath:(NSString *)path;

/**
 * Returns the username from the TXT record, if available.
 * For SFTP services, this is often in the 'u' key.
 * Returns nil if no username is specified.
 * Can be set manually for non-discovered services.
 */
- (NSString *)username;
- (void)setUsername:(NSString *)user;

@end
