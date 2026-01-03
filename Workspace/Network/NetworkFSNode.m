/* NetworkFSNode.m
 *  
 * Author: Simon Peter
 * Date: January 2026
 *
 */

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <GNUstepBase/GNUstep.h>
#import "NetworkFSNode.h"
#import "NetworkServiceItem.h"
#import "NetworkServiceManager.h"
#import "FSNodeRep.h"

NSString * const NetworkVirtualPath = @"/Network";

@implementation NetworkFSNode

+ (instancetype)networkRootNode
{
  NetworkFSNode *node = [[NetworkFSNode alloc] init];
  if (node) {
    node->isNetworkRoot = YES;
    node->serviceItem = nil;
    node->parent = nil;
    ASSIGN(node->path, NetworkVirtualPath);
    ASSIGN(node->relativePath, NetworkVirtualPath);
    ASSIGN(node->lastPathComponent, @"Network");
    ASSIGN(node->name, NSLocalizedString(@"Network", @"Network virtual folder"));
    
    /* Set flags for a virtual directory */
    node->flags.readable = 1;
    node->flags.writable = 0;
    node->flags.executable = 1;
    node->flags.deletable = 0;
    node->flags.plain = 0;
    node->flags.directory = 1;
    node->flags.link = 0;
    node->flags.socket = 0;
    node->flags.charspecial = 0;
    node->flags.blockspecial = 0;
    node->flags.mountpoint = 0;
    node->flags.application = 0;
    node->flags.package = 0;
    node->flags.unknown = 0;
    
    NSLog(@"NetworkFSNode: Created network root node at %@", NetworkVirtualPath);
  }
  return [node autorelease];
}

+ (instancetype)nodeWithServiceItem:(NetworkServiceItem *)item
{
  return [[[NetworkFSNode alloc] initWithServiceItem:item parent:nil] autorelease];
}

- (instancetype)initWithServiceItem:(NetworkServiceItem *)item
                             parent:(FSNode *)aparent
{
  self = [super init];
  if (self) {
    ASSIGN(serviceItem, item);
    isNetworkRoot = NO;
    parent = aparent;
    
    fsnodeRep = [FSNodeRep sharedInstance];
    fm = [NSFileManager defaultManager];
    ws = [NSWorkspace sharedWorkspace];
    
    /* Build path based on service name */
    NSString *serviceName = [item displayName];
    ASSIGN(lastPathComponent, serviceName);
    ASSIGN(name, serviceName);
    
    if (aparent) {
      NSString *fullPath = [NSString stringWithFormat:@"%@/%@", [aparent path], serviceName];
      ASSIGN(path, fullPath);
      ASSIGN(relativePath, serviceName);
    } else {
      NSString *fullPath = [NSString stringWithFormat:@"%@/%@", NetworkVirtualPath, serviceName];
      ASSIGN(path, fullPath);
      ASSIGN(relativePath, path);
    }
    
    /* Set flags - network services appear as directories (mountable) */
    flags.readable = 1;
    flags.writable = 0;
    flags.executable = 1;
    flags.deletable = 0;
    flags.plain = 0;
    flags.directory = 1;  /* Appear as directory so they can be "opened" */
    flags.link = 0;
    flags.socket = 0;
    flags.charspecial = 0;
    flags.blockspecial = 0;
    flags.mountpoint = 1;  /* Mark as mount point */
    flags.application = 0;
    flags.package = 0;
    flags.unknown = 0;
    
    /* Set timestamps to now */
    ASSIGN(modDate, [NSDate date]);
    ASSIGN(crDate, [NSDate date]);
    
    NSLog(@"NetworkFSNode: Created service node: %@ (type: %@)", 
          serviceName, [item type]);
  }
  return self;
}

- (void)dealloc
{
  RELEASE(serviceItem);
  [super dealloc];
}

- (NetworkServiceItem *)serviceItem
{
  return serviceItem;
}

- (BOOL)isNetworkRoot
{
  return isNetworkRoot;
}

- (BOOL)isNetworkService
{
  return (serviceItem != nil);
}

+ (BOOL)isNetworkPath:(NSString *)apath
{
  return [apath isEqualToString:NetworkVirtualPath] ||
         [apath hasPrefix:[NetworkVirtualPath stringByAppendingString:@"/"]];
}

#pragma mark - FSNode Overrides

- (NSArray *)subNodes
{
  if (!isNetworkRoot) {
    /* Individual services don't have subnodes yet
       (TODO: could show shares on the server) */
    return [NSArray array];
  }
  
  /* Get all discovered services from the manager */
  NetworkServiceManager *manager = [NetworkServiceManager sharedManager];
  NSArray *services = [manager allServices];
  NSMutableArray *nodes = [NSMutableArray arrayWithCapacity:[services count]];
  
  NSLog(@"NetworkFSNode: Getting subnodes, %lu services available", 
        (unsigned long)[services count]);
  
  for (NetworkServiceItem *item in services) {
    NetworkFSNode *node = [[NetworkFSNode alloc] initWithServiceItem:item parent:self];
    [nodes addObject:node];
    RELEASE(node);
  }
  
  return nodes;
}

- (NSArray *)subNodeNames
{
  if (!isNetworkRoot) {
    return [NSArray array];
  }
  
  NetworkServiceManager *manager = [NetworkServiceManager sharedManager];
  NSArray *services = [manager allServices];
  NSMutableArray *names = [NSMutableArray arrayWithCapacity:[services count]];
  
  for (NetworkServiceItem *item in services) {
    [names addObject:[item displayName]];
  }
  
  return names;
}

- (BOOL)isValid
{
  /* Network nodes are always valid while the app is running */
  return YES;
}

- (BOOL)hasValidPath
{
  return YES;
}

- (BOOL)isDirectory
{
  return YES;
}

- (BOOL)isReadable
{
  return YES;
}

- (BOOL)isWritable
{
  return NO;
}

- (BOOL)isExecutable
{
  return YES;
}

- (BOOL)isDeletable
{
  return NO;
}

- (BOOL)isMountPoint
{
  return isNetworkRoot ? NO : YES;
}

- (BOOL)isPlain
{
  return NO;
}

- (BOOL)isLink
{
  return NO;
}

- (BOOL)isApplication
{
  return NO;
}

- (BOOL)isPackage
{
  return NO;
}

- (NSString *)typeDescription
{
  if (isNetworkRoot) {
    return NSLocalizedString(@"Network Location", @"Type for /Network");
  }
  
  if (serviceItem) {
    if ([serviceItem isSFTPService]) {
      return NSLocalizedString(@"SFTP Server", @"Type for SFTP services");
    } else if ([serviceItem isAFPService]) {
      return NSLocalizedString(@"AFP Server", @"Type for AFP services");
    }
  }
  
  return NSLocalizedString(@"Network Server", @"Generic network server type");
}

- (NSString *)fileType
{
  return NSFileTypeDirectory;
}

- (unsigned long long)fileSize
{
  return 0;
}

- (NSDate *)modificationDate
{
  return modDate ? modDate : [NSDate date];
}

- (NSDate *)creationDate
{
  return crDate ? crDate : [NSDate date];
}

- (NSString *)owner
{
  return @"network";
}

- (NSString *)group
{
  return @"network";
}

- (unsigned long)permissions
{
  return 0555; /* r-xr-xr-x */
}

@end
