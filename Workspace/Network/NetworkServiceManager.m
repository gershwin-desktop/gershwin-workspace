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
    threadShouldStop = NO;

    /* Check if mDNS-SD support is available */
    Class netServiceBrowserClass = NSClassFromString(@"NSNetServiceBrowser");
    mDNSAvailable = (netServiceBrowserClass != nil);

    if (mDNSAvailable) {
      NSDebugLLog(@"gwspace", @"NetworkServiceManager: mDNS-SD support is available");

      /* Spin up a dedicated background thread with its own run loop
         for all NSNetServiceBrowser / NSNetService operations.
         This keeps daemon connection attempts, service resolution,
         and DNS-SD callbacks off the main thread so the UI never
         blocks waiting for network services.

         Browsing starts automatically after a short delay (see
         -networkThreadMain), so callers merely need to observe the
         notifications — no explicit start is required. */
      networkThread = [[NSThread alloc] initWithTarget:self
                                              selector:@selector(networkThreadMain)
                                                object:nil];
      [networkThread setName:@"GWNetworkServiceThread"];
      [networkThread start];
    } else {
      NSDebugLLog(@"gwspace", @"NetworkServiceManager: mDNS-SD support is NOT available");
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

#pragma mark - Background Thread

- (void)networkThreadMain
{
  @autoreleasepool {
    NSRunLoop *runLoop = [NSRunLoop currentRunLoop];

    /* Keep the thread alive with a port-based run loop source so the
       run loop does not exit immediately when there are no timers. */
    [runLoop addPort:[NSPort port] forMode:NSDefaultRunLoopMode];

    /* Wait a few seconds before starting the actual browse so that
       Workspace.app startup / window restoration completes first.
       The user never waits on this — it's purely background. */
    [self performSelector:@selector(startBrowsing)
               withObject:nil
               afterDelay:3.0];

    NSDebugLLog(@"gwspace", @"NetworkServiceManager: network thread running");

    while (!threadShouldStop) {
      @autoreleasepool {
        [runLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:1.0]];
      }
    }

    NSDebugLLog(@"gwspace", @"NetworkServiceManager: network thread exiting");
  }
}

#pragma mark - Browsing Control

- (void)startBrowsing
{
  /* If called from a thread other than the dedicated network thread,
     re-dispatch so that all NSNetServiceBrowser operations happen on
     the same thread (the one that runs the mDNS run loop). */
  if (networkThread && [NSThread currentThread] != networkThread) {
    [self performSelector:@selector(startBrowsing)
                 onThread:networkThread
               withObject:nil
            waitUntilDone:NO];
    return;
  }

  if (!mDNSAvailable) {
    NSDebugLLog(@"gwspace", @"NetworkServiceManager: Cannot start browsing - mDNS-SD not available");
    return;
  }

  if (isSearching) {
    NSDebugLLog(@"gwspace", @"NetworkServiceManager: Already browsing for services");
    return;
  }

  NSDebugLLog(@"gwspace", @"NetworkServiceManager: Starting to browse for SFTP, AFP, and WebDAV services...");

  /* Wrap browser creation and search in @try/@catch to handle the case
     where NSNetServiceBrowser class exists (GNUstep built with libdns_sd)
     but the mDNS daemon (Avahi, mDNSResponder) is not running.
     See: https://github.com/gershwin-desktop/gershwin-workspace/issues/93 */
  @try {
    /* Start browsing for SFTP-SSH services */
    sftpBrowser = [[NSNetServiceBrowser alloc] init];
    [sftpBrowser setDelegate:self];
    [sftpBrowser searchForServicesOfType:@"_sftp-ssh._tcp." inDomain:@"local."];
    NSDebugLLog(@"gwspace", @"NetworkServiceManager: Started searching for _sftp-ssh._tcp. services");

    /* Start browsing for AFP over TCP services */
    afpBrowser = [[NSNetServiceBrowser alloc] init];
    [afpBrowser setDelegate:self];
    [afpBrowser searchForServicesOfType:@"_afpovertcp._tcp." inDomain:@"local."];
    NSDebugLLog(@"gwspace", @"NetworkServiceManager: Started searching for _afpovertcp._tcp. services");

    /* Start browsing for WebDAV services (HTTP) */
    webdavBrowser = [[NSNetServiceBrowser alloc] init];
    [webdavBrowser setDelegate:self];
    [webdavBrowser searchForServicesOfType:@"_webdav._tcp." inDomain:@"local."];
    NSDebugLLog(@"gwspace", @"NetworkServiceManager: Started searching for _webdav._tcp. services");

    /* Start browsing for WebDAV services (HTTPS) */
    webdavsBrowser = [[NSNetServiceBrowser alloc] init];
    [webdavsBrowser setDelegate:self];
    [webdavsBrowser searchForServicesOfType:@"_webdavs._tcp." inDomain:@"local."];
    NSDebugLLog(@"gwspace", @"NetworkServiceManager: Started searching for _webdavs._tcp. services");

    isSearching = YES;
  } @catch (NSException *exception) {
    NSWarnMLog(@"NetworkServiceManager: mDNS browsing failed with exception: %@ - disabling mDNS support", exception);

    /* Clean up any browsers that were created before the exception */
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

    /* Disable mDNS so future calls don't attempt browsing again */
    mDNSAvailable = NO;
    isSearching = NO;
  }
}

- (void)stopBrowsing
{
  if (!isSearching) {
    return;
  }

  NSDebugLLog(@"gwspace", @"NetworkServiceManager: Stopping service browsing");

  /* Signal the background thread to exit */
  threadShouldStop = YES;

  /* Stop and release browsers */
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
  for (NSNetService *svc in pendingResolutions) {
    [svc stop];
  }
  [pendingResolutions removeAllObjects];

  isSearching = NO;
}

- (BOOL)isBrowsing
{
  return isSearching;
}

#pragma mark - Service Accessors (thread-safe)

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
  NSArray *added;

  @synchronized(services) {
    /* Check if we already have this service */
    if ([self existingServiceMatchingNetService:[item netService]] != nil) {
      NSDebugLLog(@"gwspace", @"NetworkServiceManager: Service already exists: %@", [item displayName]);
      return;
    }

    [services addObject:item];
    added = [NSArray arrayWithObject:item];
    NSDebugLLog(@"gwspace", @"NetworkServiceManager: Added service: %@ (total: %lu)",
          [item displayName], (unsigned long)[services count]);
  }

  /* Post notification on main thread */
  NSDictionary *userInfo = @{@"addedServices": added, @"removedServices": @[]};
  [self performSelectorOnMainThread:@selector(postServicesChangedOnMainThread:)
                         withObject:userInfo
                      waitUntilDone:NO];
}

- (void)removeServiceMatchingNetService:(NSNetService *)netService
{
  NetworkServiceItem *itemToRemove = nil;
  NSArray *removed;

  @synchronized(services) {
    itemToRemove = [self existingServiceMatchingNetService:netService];
    if (itemToRemove == nil) {
      return;
    }

    [[itemToRemove retain] autorelease];
    [services removeObject:itemToRemove];
    removed = [NSArray arrayWithObject:itemToRemove];
    NSDebugLLog(@"gwspace", @"NetworkServiceManager: Removed service: %@ (total: %lu)",
          [itemToRemove displayName], (unsigned long)[services count]);
  }

  /* Post notification on main thread */
  NSDictionary *userInfo = @{@"addedServices": @[], @"removedServices": removed};
  [self performSelectorOnMainThread:@selector(postServicesChangedOnMainThread:)
                         withObject:userInfo
                      waitUntilDone:NO];
}

- (void)updateServiceItem:(NetworkServiceItem *)item fromNetService:(NSNetService *)netService
{
  @synchronized(services) {
    item.hostName = [netService hostName];
    item.port = [netService port];
    item.addresses = [netService addresses];
    item.resolved = YES;

    NSDebugLLog(@"gwspace", @"NetworkServiceManager: Resolved service: %@ -> %@:%d",
          [item displayName], [item hostName], [item port]);
  }

  /* Post resolution notification on main thread */
  [self performSelectorOnMainThread:@selector(postServiceResolvedOnMainThread:)
                         withObject:item
                      waitUntilDone:NO];
}

#pragma mark - Main-thread Notification Posters
/* These are invoked via performSelectorOnMainThread: from the network thread. */

- (void)postServicesChangedOnMainThread:(NSDictionary *)userInfo
{
  [[NSNotificationCenter defaultCenter]
    postNotificationName:NetworkServicesDidChangeNotification
                  object:self
                userInfo:userInfo];
}

- (void)postServiceResolvedOnMainThread:(NetworkServiceItem *)item
{
  NSDictionary *userInfo = @{@"service": item};
  [[NSNotificationCenter defaultCenter]
    postNotificationName:NetworkServiceDidResolveNotification
                  object:self
                userInfo:userInfo];
}

#pragma mark - NSNetServiceBrowserDelegate
/* All delegate callbacks arrive on the network thread. */

- (void)netServiceBrowserWillSearch:(NSNetServiceBrowser *)browser
{
  NSString *browserType;
  if (browser == sftpBrowser) browserType = @"SFTP";
  else if (browser == afpBrowser) browserType = @"AFP";
  else if (browser == webdavBrowser) browserType = @"WebDAV";
  else if (browser == webdavsBrowser) browserType = @"WebDAVS";
  else browserType = @"Unknown";
  NSDebugLLog(@"gwspace", @"NetworkServiceManager: %@ browser will search", browserType);
}

- (void)netServiceBrowserDidStopSearch:(NSNetServiceBrowser *)browser
{
  NSString *browserType;
  if (browser == sftpBrowser) browserType = @"SFTP";
  else if (browser == afpBrowser) browserType = @"AFP";
  else if (browser == webdavBrowser) browserType = @"WebDAV";
  else if (browser == webdavsBrowser) browserType = @"WebDAVS";
  else browserType = @"Unknown";
  NSDebugLLog(@"gwspace", @"NetworkServiceManager: %@ browser stopped searching", browserType);
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
  NSDebugLLog(@"gwspace", @"NetworkServiceManager: %@ browser found service: %@ (type: %@, domain: %@)",
        browserType, [netService name], [netService type], [netService domain]);

  /* Create a service item and add it */
  NetworkServiceItem *item = [NetworkServiceItem itemWithNetService:netService];
  [self addServiceItem:item];

  /* Start resolving the service to get host/port info */
  [netService setDelegate:self];
  [netService resolveWithTimeout:10.0];
  [pendingResolutions addObject:netService];
  NSDebugLLog(@"gwspace", @"NetworkServiceManager: Starting resolution for: %@", [netService name]);
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
  NSDebugLLog(@"gwspace", @"NetworkServiceManager: %@ browser removed service: %@",
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
  NSDebugLLog(@"gwspace", @"NetworkServiceManager: %@ browser failed to search: %@",
        browserType, errorDict);
}

#pragma mark - NSNetServiceDelegate

- (void)netServiceDidResolveAddress:(NSNetService *)netService
{
  NSDebugLLog(@"gwspace", @"NetworkServiceManager: Service resolved: %@ -> %@:%ld",
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
  NSDebugLLog(@"gwspace", @"NetworkServiceManager: Failed to resolve service %@: %@",
        [netService name], errorDict);

  [pendingResolutions removeObject:netService];
}

@end
