/* NetworkFSNode.h
 *  
 * Author: Simon Peter
 * Date: January 2026
 *
 */

#import <Foundation/Foundation.h>
#import "FSNode.h"

@class NetworkServiceItem;

/**
 * The virtual path that represents the Network location.
 * This path doesn't exist on disk but is handled specially.
 */
extern NSString * const NetworkVirtualPath;

/**
 * NetworkFSNode is a subclass of FSNode that represents network services
 * discovered via mDNS. It allows network services to be displayed in
 * standard Workspace views (icons, list, browser) alongside regular files.
 */
@interface NetworkFSNode : FSNode
{
  NetworkServiceItem *serviceItem;
  BOOL isNetworkRoot;  /* YES if this is the /Network container */
}

/**
 * Creates a node representing the Network root container.
 * This node's subnodes are the discovered network services.
 */
+ (instancetype)networkRootNode;

/**
 * Creates a node representing a specific network service.
 */
+ (instancetype)nodeWithServiceItem:(NetworkServiceItem *)item;

/**
 * Initializes with a network service item.
 */
- (instancetype)initWithServiceItem:(NetworkServiceItem *)item
                             parent:(FSNode *)aparent;

/**
 * Returns the wrapped service item, or nil if this is the network root.
 */
- (NetworkServiceItem *)serviceItem;

/**
 * Returns YES if this is the /Network root container node.
 */
- (BOOL)isNetworkRoot;

/**
 * Returns YES if this represents a network service (not the root).
 */
- (BOOL)isNetworkService;

/**
 * Checks if a path represents a network virtual path.
 */
+ (BOOL)isNetworkPath:(NSString *)apath;

/**
 * Returns the icon name for this network node.
 */
- (NSString *)iconName;

/**
 * Opens the network service. For SFTP services, this mounts the volume.
 * Returns the path to open (mount point for SFTP, or original path otherwise).
 * Returns nil if the operation failed.
 */
- (NSString *)openNetworkService;

@end
