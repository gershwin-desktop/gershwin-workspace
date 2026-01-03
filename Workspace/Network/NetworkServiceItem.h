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
}

@property (nonatomic, retain) NSString *name;
@property (nonatomic, retain) NSString *type;
@property (nonatomic, retain) NSString *domain;
@property (nonatomic, retain) NSString *hostName;
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
 * Returns the icon name for this service type.
 */
- (NSString *)iconName;

@end
