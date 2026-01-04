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
    
    /* Set flags - network services appear as files, not directories */
    flags.readable = 1;
    flags.writable = 0;
    flags.executable = 0;
    flags.deletable = 0;
    flags.plain = 1;  /* Treat as plain file, not a directory */
    flags.directory = 0;  /* Not a directory - cannot be opened/traversed */
    flags.link = 0;
    flags.socket = 0;
    flags.charspecial = 0;
    flags.blockspecial = 0;
    flags.mountpoint = 0;  /* Not a mount point (TODO: implement mounting in future) */
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
  
  /* Ensure unique visible names by appending -2, -3, ... for duplicates */
  NSMutableDictionary *nameCounts = [NSMutableDictionary dictionaryWithCapacity:[services count]];
  for (NetworkServiceItem *item in services) {
    NSString *baseName = [item displayName];
    NSNumber *count = [nameCounts objectForKey:baseName];
    NSString *uniqueName = nil;
    if (!count) {
      [nameCounts setObject:@1 forKey:baseName];
      uniqueName = baseName;
    } else {
      NSUInteger newCount = [count unsignedIntegerValue] + 1;
      [nameCounts setObject:[NSNumber numberWithUnsignedInteger:newCount] forKey:baseName];
      /* Insert numbering before known suffixes like " (sftp)" and " (afp)" */
      NSString *suffix = nil;
      NSString *namePart = baseName;
      NSRange suffixRange = [baseName rangeOfString:@" (" options:NSBackwardsSearch];
      if (suffixRange.location != NSNotFound) {
        suffix = [baseName substringFromIndex:suffixRange.location];
        namePart = [baseName substringToIndex:suffixRange.location];
      }
      if (suffix && ([suffix isEqualToString:@" (sftp)"] || [suffix isEqualToString:@" (afp)"])) {
        uniqueName = [NSString stringWithFormat:@"%@-%lu%@", namePart, (unsigned long)newCount, suffix];
      } else {
        uniqueName = [NSString stringWithFormat:@"%@-%lu", baseName, (unsigned long)newCount];
      }
    }

    NetworkFSNode *node = [[NetworkFSNode alloc] initWithServiceItem:item parent:self];
    /* Override the node's visible name/path to use the unique name */
    ASSIGN(node->lastPathComponent, uniqueName);
    ASSIGN(node->name, uniqueName);
    if (parent) {
      NSString *fullPath = [NSString stringWithFormat:@"%@/%@", [self path], uniqueName];
      ASSIGN(node->path, fullPath);
      ASSIGN(node->relativePath, uniqueName);
    } else {
      NSString *fullPath = [NSString stringWithFormat:@"%@/%@", NetworkVirtualPath, uniqueName];
      ASSIGN(node->path, fullPath);
      ASSIGN(node->relativePath, fullPath);
    }

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
  
  /* Use the same uniqueness logic as -subNodes so names match nodes */
  NSMutableDictionary *nameCounts = [NSMutableDictionary dictionaryWithCapacity:[services count]];
  for (NetworkServiceItem *item in services) {
    NSString *baseName = [item displayName];
    NSNumber *count = [nameCounts objectForKey:baseName];
    NSString *uniqueName = nil;
    if (!count) {
      [nameCounts setObject:@1 forKey:baseName];
      uniqueName = baseName;
    } else {
      NSUInteger newCount = [count unsignedIntegerValue] + 1;
      [nameCounts setObject:[NSNumber numberWithUnsignedInteger:newCount] forKey:baseName];
      /* Insert numbering before known suffixes like " (sftp)" and " (afp)" */
      NSString *suffix = nil;
      NSString *namePart = baseName;
      NSRange suffixRange = [baseName rangeOfString:@" (" options:NSBackwardsSearch];
      if (suffixRange.location != NSNotFound) {
        suffix = [baseName substringFromIndex:suffixRange.location];
        namePart = [baseName substringToIndex:suffixRange.location];
      }
      if (suffix && ([suffix isEqualToString:@" (sftp)"] || [suffix isEqualToString:@" (afp)"])) {
        uniqueName = [NSString stringWithFormat:@"%@-%lu%@", namePart, (unsigned long)newCount, suffix];
      } else {
        uniqueName = [NSString stringWithFormat:@"%@-%lu", baseName, (unsigned long)newCount];
      }
    }
    [names addObject:uniqueName];
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
  /* Network service items are not directories - they cannot be traversed */
  if (isNetworkRoot) {
    return YES;  /* The /Network root is a directory */
  }
  return NO;  /* Service items are treated as files */
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
  /* Service items are not executable files */
  if (isNetworkRoot) {
    return YES;  /* The network root is executable/traversable */
  }
  return NO;  /* Service items are treated as plain files */
}

- (BOOL)isDeletable
{
  return NO;
}

- (BOOL)isMountPoint
{
  /* Network service items are not mount points (yet) */
  return NO;
}

- (BOOL)isPlain
{
  /* Service items are now plain files, not traversable */
  if (isNetworkRoot) {
    return NO;  /* The root network location is a directory, not plain */
  }
  return YES;  /* Service items are treated as plain files */
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
  if (isNetworkRoot) {
    return NSFileTypeDirectory;
  }
  /* Network service items are treated as regular files */
  return NSFileTypeRegular;
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

- (NSString *)iconName
{
  if (isNetworkRoot) {
    return @"Network";
  }
  
  if (serviceItem) {
    return [serviceItem iconName];
  }
  
  return @"Network";
}

@end
