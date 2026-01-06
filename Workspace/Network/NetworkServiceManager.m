/* NetworkServiceManager.m
 *  
 * Author: Simon Peter
 * Date: January 2026
 *
 */

#import "NetworkServiceManager.h"
#import "NetworkServiceItem.h"

NSString * const NetworkServicesDidChangeNotification = @"NetworkServicesDidChangeNotification";
NSString * const NetworkServiceDidResolveNotification = @"NetworkServiceDidResolveNotification";

static NetworkServiceManager *sharedManager = nil;

@implementation NetworkServiceManager

+ (instancetype)sharedManager
{
  if (sharedManager == nil) {
    sharedManager = [[NetworkServiceManager alloc] init];
  }
  return sharedManager;
}

- (instancetype)init
{
  self = [super init];
  if (self) {
    services = [[NSMutableArray alloc] init];
    pendingResolutions = [[NSMutableArray alloc] init];
    isSearching = NO;
    
    /* Check if mDNS-SD support is available */
    Class netServiceBrowserClass = NSClassFromString(@"NSNetServiceBrowser");
    mDNSAvailable = (netServiceBrowserClass != nil);
    
    if (mDNSAvailable) {
      NSLog(@"NetworkServiceManager: mDNS-SD support is available");
    } else {
      NSLog(@"NetworkServiceManager: mDNS-SD support is NOT available");
    }
  }
  return self;
}

- (void)dealloc
{
  [self stopBrowsing];
  [services release];
  [pendingResolutions release];
  [super dealloc];
}

- (BOOL)isMDNSAvailable
{
  return mDNSAvailable;
}

- (void)startBrowsing
{
  if (!mDNSAvailable) {
    NSLog(@"NetworkServiceManager: Cannot start browsing - mDNS-SD not available");
    return;
  }
  
  if (isSearching) {
    NSLog(@"NetworkServiceManager: Already browsing for services");
    return;
  }
  
  NSLog(@"NetworkServiceManager: Starting to browse for SFTP, AFP, and WebDAV services...");
  isSearching = YES;
  
  /* Start browsing for SFTP-SSH services */
  sftpBrowser = [[NSNetServiceBrowser alloc] init];
  [sftpBrowser setDelegate:self];
  [sftpBrowser searchForServicesOfType:@"_sftp-ssh._tcp." inDomain:@"local."];
  NSLog(@"NetworkServiceManager: Started searching for _sftp-ssh._tcp. services");
  
  /* Start browsing for AFP over TCP services */
  afpBrowser = [[NSNetServiceBrowser alloc] init];
  [afpBrowser setDelegate:self];
  [afpBrowser searchForServicesOfType:@"_afpovertcp._tcp." inDomain:@"local."];
  NSLog(@"NetworkServiceManager: Started searching for _afpovertcp._tcp. services");
  
  /* Start browsing for WebDAV services (HTTP) */
  webdavBrowser = [[NSNetServiceBrowser alloc] init];
  [webdavBrowser setDelegate:self];
  [webdavBrowser searchForServicesOfType:@"_webdav._tcp." inDomain:@"local."];
  NSLog(@"NetworkServiceManager: Started searching for _webdav._tcp. services");
  
  /* Start browsing for WebDAV services (HTTPS) */
  webdavsBrowser = [[NSNetServiceBrowser alloc] init];
  [webdavsBrowser setDelegate:self];
  [webdavsBrowser searchForServicesOfType:@"_webdavs._tcp." inDomain:@"local."];
  NSLog(@"NetworkServiceManager: Started searching for _webdavs._tcp. services");
}

- (void)stopBrowsing
{
  if (!isSearching) {
    return;
  }
  
  NSLog(@"NetworkServiceManager: Stopping service browsing");
  isSearching = NO;
  
  if (sftpBrowser) {
    [sftpBrowser stop];
    [sftpBrowser release];
    sftpBrowser = nil;
  }
  
  if (afpBrowser) {
    [afpBrowser stop];
    [afpBrowser release];
    afpBrowser = nil;
  }
  
  if (webdavBrowser) {
    [webdavBrowser stop];
    [webdavBrowser release];
    webdavBrowser = nil;
  }
  
  if (webdavsBrowser) {
    [webdavsBrowser stop];
    [webdavsBrowser release];
    webdavsBrowser = nil;
  }
  
  /* Stop any pending resolutions */
  for (NSNetService *service in pendingResolutions) {
    [service stop];
  }
  [pendingResolutions removeAllObjects];
}

- (BOOL)isBrowsing
{
  return isSearching;
}

- (NSArray *)allServices
{
  @synchronized(services) {
    return [[services copy] autorelease];
  }
}

- (NSArray *)sftpServices
{
  @synchronized(services) {
    NSMutableArray *result = [NSMutableArray array];
    for (NetworkServiceItem *item in services) {
      if ([item isSFTPService]) {
        [result addObject:item];
      }
    }
    return result;
  }
}

- (NSArray *)afpServices
{
  @synchronized(services) {
    NSMutableArray *result = [NSMutableArray array];
    for (NetworkServiceItem *item in services) {
      if ([item isAFPService]) {
        [result addObject:item];
      }
    }
    return result;
  }
}

- (NSArray *)webdavServices
{
  @synchronized(services) {
    NSMutableArray *result = [NSMutableArray array];
    for (NetworkServiceItem *item in services) {
      if ([item isWebDAVService]) {
        [result addObject:item];
      }
    }
    return result;
  }
}

- (NSUInteger)serviceCount
{
  @synchronized(services) {
    return [services count];
  }
}

- (NetworkServiceItem *)serviceAtIndex:(NSUInteger)index
{
  @synchronized(services) {
    if (index < [services count]) {
      return [[[services objectAtIndex:index] retain] autorelease];
    }
    return nil;
  }
}

- (NetworkServiceItem *)serviceWithIdentifier:(NSString *)identifier
{
  @synchronized(services) {
    for (NetworkServiceItem *item in services) {
      if ([[item identifier] isEqual:identifier]) {
        return [[[item retain] autorelease] retain];
      }
    }
    return nil;
  }
}

#pragma mark - Private Methods

- (NetworkServiceItem *)existingServiceMatchingNetService:(NSNetService *)netService
{
  NSString *serviceName = [netService name];
  NSString *serviceType = [netService type];
  
  for (NetworkServiceItem *item in services) {
    if ([[item name] isEqual:serviceName] && [[item type] isEqual:serviceType]) {
      return item;
    }
  }
  return nil;
}

- (void)addServiceItem:(NetworkServiceItem *)item
{
  NSArray *addedServices;
  
  @synchronized(services) {
    /* Check if we already have this service */
    if ([self existingServiceMatchingNetService:[item netService]] != nil) {
      NSLog(@"NetworkServiceManager: Service already exists: %@", [item displayName]);
      return;
    }
    
    [services addObject:item];
    addedServices = [NSArray arrayWithObject:item];
    NSLog(@"NetworkServiceManager: Added service: %@ (total: %lu)", 
          [item displayName], (unsigned long)[services count]);
  }
  
  /* Post notification on main thread */
  NSDictionary *userInfo = @{
    @"addedServices": addedServices,
    @"removedServices": @[]
  };
  
  [[NSNotificationCenter defaultCenter] 
    postNotificationName:NetworkServicesDidChangeNotification
                  object:self
                userInfo:userInfo];
}

- (void)removeServiceMatchingNetService:(NSNetService *)netService
{
  NetworkServiceItem *itemToRemove = nil;
  NSArray *removedServices;
  
  @synchronized(services) {
    itemToRemove = [self existingServiceMatchingNetService:netService];
    if (itemToRemove == nil) {
      return;
    }
    
    [[itemToRemove retain] autorelease];
    [services removeObject:itemToRemove];
    removedServices = [NSArray arrayWithObject:itemToRemove];
    NSLog(@"NetworkServiceManager: Removed service: %@ (total: %lu)", 
          [itemToRemove displayName], (unsigned long)[services count]);
  }
  
  /* Post notification on main thread */
  NSDictionary *userInfo = @{
    @"addedServices": @[],
    @"removedServices": removedServices
  };
  
  [[NSNotificationCenter defaultCenter] 
    postNotificationName:NetworkServicesDidChangeNotification
                  object:self
                userInfo:userInfo];
}

- (void)updateServiceItem:(NetworkServiceItem *)item fromNetService:(NSNetService *)netService
{
  @synchronized(services) {
    item.hostName = [netService hostName];
    item.port = [netService port];
    item.addresses = [netService addresses];
    item.resolved = YES;
    
    NSLog(@"NetworkServiceManager: Resolved service: %@ -> %@:%d", 
          [item displayName], [item hostName], [item port]);
  }
  
  /* Post resolution notification */
  NSDictionary *userInfo = @{@"service": item};
  [[NSNotificationCenter defaultCenter] 
    postNotificationName:NetworkServiceDidResolveNotification
                  object:self
                userInfo:userInfo];
}

#pragma mark - NSNetServiceBrowserDelegate

- (void)netServiceBrowserWillSearch:(NSNetServiceBrowser *)browser
{
  NSString *browserType;
  if (browser == sftpBrowser) browserType = @"SFTP";
  else if (browser == afpBrowser) browserType = @"AFP";
  else if (browser == webdavBrowser) browserType = @"WebDAV";
  else if (browser == webdavsBrowser) browserType = @"WebDAVS";
  else browserType = @"Unknown";
  NSLog(@"NetworkServiceManager: %@ browser will search", browserType);
}

- (void)netServiceBrowserDidStopSearch:(NSNetServiceBrowser *)browser
{
  NSString *browserType;
  if (browser == sftpBrowser) browserType = @"SFTP";
  else if (browser == afpBrowser) browserType = @"AFP";
  else if (browser == webdavBrowser) browserType = @"WebDAV";
  else if (browser == webdavsBrowser) browserType = @"WebDAVS";
  else browserType = @"Unknown";
  NSLog(@"NetworkServiceManager: %@ browser stopped searching", browserType);
}

- (void)netServiceBrowser:(NSNetServiceBrowser *)browser
           didFindService:(NSNetService *)netService
               moreComing:(BOOL)moreComing
{
  NSString *browserType;
  if (browser == sftpBrowser) browserType = @"SFTP";
  else if (browser == afpBrowser) browserType = @"AFP";
  else if (browser == webdavBrowser) browserType = @"WebDAV";
  else if (browser == webdavsBrowser) browserType = @"WebDAVS";
  else browserType = @"Unknown";
  NSLog(@"NetworkServiceManager: %@ browser found service: %@ (type: %@, domain: %@)", 
        browserType, [netService name], [netService type], [netService domain]);
  
  /* Create a service item and add it */
  NetworkServiceItem *item = [NetworkServiceItem itemWithNetService:netService];
  [self addServiceItem:item];
  
  /* Start resolving the service to get host/port info */
  [netService setDelegate:self];
  [netService resolveWithTimeout:10.0];
  [pendingResolutions addObject:netService];
  NSLog(@"NetworkServiceManager: Starting resolution for: %@", [netService name]);
}

- (void)netServiceBrowser:(NSNetServiceBrowser *)browser
         didRemoveService:(NSNetService *)netService
               moreComing:(BOOL)moreComing
{
  NSString *browserType;
  if (browser == sftpBrowser) browserType = @"SFTP";
  else if (browser == afpBrowser) browserType = @"AFP";
  else if (browser == webdavBrowser) browserType = @"WebDAV";
  else if (browser == webdavsBrowser) browserType = @"WebDAVS";
  else browserType = @"Unknown";
  NSLog(@"NetworkServiceManager: %@ browser removed service: %@", 
        browserType, [netService name]);
  
  [self removeServiceMatchingNetService:netService];
  [pendingResolutions removeObject:netService];
}

- (void)netServiceBrowser:(NSNetServiceBrowser *)browser
             didNotSearch:(NSDictionary *)errorDict
{
  NSString *browserType;
  if (browser == sftpBrowser) browserType = @"SFTP";
  else if (browser == afpBrowser) browserType = @"AFP";
  else if (browser == webdavBrowser) browserType = @"WebDAV";
  else if (browser == webdavsBrowser) browserType = @"WebDAVS";
  else browserType = @"Unknown";
  NSLog(@"NetworkServiceManager: %@ browser failed to search: %@", 
        browserType, errorDict);
}

#pragma mark - NSNetServiceDelegate

- (void)netServiceDidResolveAddress:(NSNetService *)netService
{
  NSLog(@"NetworkServiceManager: Service resolved: %@ -> %@:%ld", 
        [netService name], [netService hostName], (long)[netService port]);
  
  /* Find and update the corresponding item */
  @synchronized(services) {
    NetworkServiceItem *item = [self existingServiceMatchingNetService:netService];
    if (item) {
      [self updateServiceItem:item fromNetService:netService];
    }
  }
  
  [pendingResolutions removeObject:netService];
}

- (void)netService:(NSNetService *)netService
     didNotResolve:(NSDictionary *)errorDict
{
  NSLog(@"NetworkServiceManager: Failed to resolve service %@: %@", 
        [netService name], errorDict);
  
  [pendingResolutions removeObject:netService];
}

@end
