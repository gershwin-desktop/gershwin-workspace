/* NetworkServiceManager.m
 *
 * Author: Simon Peter
 * Date: January 2026
 *
 */

#import "NetworkServiceManager.h"
#import "NetworkServiceItem.h"
#import "NBNSProbe.h"
#import "SMBDiscovery.h"
#import <signal.h>
#ifndef _WIN32
#import <sys/socket.h>
#import <netinet/in.h>
#import <arpa/inet.h>
#endif
#import <setjmp.h>

#ifdef _WIN32
/* MinGW has neither sigaction() nor sigsetjmp()/siglongjmp(), and there is
 * no Avahi to abort() on us.  Reduce the SIGABRT trap below to plain
 * setjmp()/longjmp() with an inert sigaction(). */
typedef jmp_buf sigjmp_buf;
#define sigsetjmp(env, savesigs) setjmp(env)
#define siglongjmp(env, val) longjmp((env), (val))
struct sigaction {
  void (*sa_handler)(int);
  int sa_mask;
  int sa_flags;
};
#define SA_NODEFER 0
#define sigemptyset(set) ((void)(set))
#define sigaction(sig, act, oact) ((void)(sig), (void)(act), (void)(oact), 0)
#endif

NSString * const NetworkServicesDidChangeNotification = @"NetworkServicesDidChangeNotification";
NSString * const NetworkServiceDidResolveNotification = @"NetworkServiceDidResolveNotification";

static NetworkServiceManager *sharedManager = nil;

/* Signal handling for crash-safe Avahi/mDNS probe.

   Backends such as Avahi on Linux abort the process via assert() when
   the mDNS daemon is not running (e.g., avahi-daemon.service is stopped).
   C-level assert() sends SIGABRT, which @try/@catch cannot handle.

   We install a SIGABRT handler on the network thread and wrap the entire
   thread body in sigsetjmp/siglongjmp so that any assertion from the
   mDNS C library causes a graceful thread exit rather than a crash. */
static sigjmp_buf mdnsProbeJmpBuf;
static volatile sig_atomic_t mdnsProbeActive = 0;

static void mdnsAbortHandler(int sig)
{
  /* Reset to default so a nested/second SIGABRT kills the process
     normally instead of risking infinite siglongjmp. */
  signal(SIGABRT, SIG_DFL);

  if (mdnsProbeActive) {
    siglongjmp(mdnsProbeJmpBuf, 1);
  }
}

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

    /* Check if the NSNetServiceBrowser class exists — i.e., GNUstep was
       built with libdns_sd / mDNSResponder support.  We do NOT yet know
       whether the underlying mDNS daemon is available; that is determined
       at runtime on the background thread via a sigsetjmp/siglongjmp
       SIGABRT handler (see -networkThreadMain).

       We always start the background thread if the class exists, and the
       thread exits gracefully if the daemon is absent.  This avoids any
       backend-specific assumptions (Avahi, mDNSResponder, etc.) and
       gracefully degrades when no mDNS daemon is present. */
    Class netServiceBrowserClass = NSClassFromString(@"NSNetServiceBrowser");
    BOOL classAvailable = (netServiceBrowserClass != nil);

    if (classAvailable) {

      /* Spin up a dedicated background thread with its own run loop
         for all NSNetServiceBrowser / NSNetService operations.
         This keeps daemon connection attempts, service resolution,
         and DNS-SD callbacks off the main thread so the UI never
         blocks waiting for network services.

         The thread body is wrapped in sigsetjmp/siglongjmp to safely
         catch any C-level assert() from the Avahi library when the
         daemon is absent. */
      mDNSAvailable = NO; /* Will be set to YES if the probe succeeds */
      networkThread = [[NSThread alloc] initWithTarget:self
                                              selector:@selector(networkThreadMain)
                                                object:nil];
      [networkThread setName:@"GWNetSvcThread"];
      [networkThread start];
    } else {
      mDNSAvailable = NO;
    }

    /* WS-Discovery and NetBIOS need neither the mDNS class nor its daemon,
       and Windows hosts mostly do not announce via mDNS at all. */
    [[SMBDiscovery sharedDiscovery] startupWithServiceManager:self];
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
    /* Install SIGABRT handler for the lifetime of this thread, so that
       any C-level assert() from the Avahi/ mDNSResponder library
       (triggered when the mDNS daemon is absent) is caught instead of
       aborting the process.  The handler uses siglongjmp to jump back
       to the sigsetjmp below, bypassing abort()'s process termination.

       We protect the ENTIRE thread body (not just a brief probe) because
       the assertion can fire at various points — during
       searchForServicesOfType:, during the D-Bus connection setup, or
       during run loop event processing.  A short-lived probe that only
       calls alloc] init] misses these. */
    struct sigaction oldAct;
    {
      struct sigaction sa;
      sigemptyset(&sa.sa_mask);
      sa.sa_flags = SA_NODEFER;
      sa.sa_handler = &mdnsAbortHandler;
      sigaction(SIGABRT, &sa, &oldAct);
    }

    mdnsProbeActive = 1;
    if (sigsetjmp(mdnsProbeJmpBuf, 1) == 0) {
      /* ---- Normal execution path ---- */

      /* The class exists in every libs-base build, but without an Avahi or
         mDNSResponder backend (e.g. Windows) +allocWithZone: returns nil,
         and alloc/init then crashes inside libobjc's objc_alloc_init. */
      id probeBrowser = nil;
      if (NSClassFromString(@"NSNetServiceBrowser") != nil) {
        probeBrowser = [NSNetServiceBrowser allocWithZone: NULL];
      }
      if (probeBrowser == nil) {
        mDNSAvailable = NO;
        mdnsProbeActive = 0;
        sigaction(SIGABRT, &oldAct, NULL);
        return;
      }
      [probeBrowser release];

      /* Tentatively mark mDNS as available.  If a SIGABRT occurs during
         the run loop (e.g. during startBrowsing's searchForServicesOfType:
         or during asynchronous D-Bus event processing), the else branch
         below resets this to NO. */
      mDNSAvailable = YES;

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


      while (!threadShouldStop) {
        @autoreleasepool {
          [runLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:1.0]];
        }
      }

      mdnsProbeActive = 0;
      sigaction(SIGABRT, &oldAct, NULL);
    } else {
      /* ---- SIGABRT was caught ---- */
      mdnsProbeActive = 0;
      mDNSAvailable = NO;
      isSearching = NO;

      /* Release any browsers that may have been partially initialized
         (safe to message nil so uninitialized ivars are fine). */
      [sftpBrowser stop]; [sftpBrowser release]; sftpBrowser = nil;
      [afpBrowser stop];  [afpBrowser release];  afpBrowser = nil;
      [webdavBrowser stop];  [webdavBrowser release];  webdavBrowser = nil;
      [webdavsBrowser stop]; [webdavsBrowser release]; webdavsBrowser = nil;
      [smbBrowser stop];  [smbBrowser release];  smbBrowser = nil;
      [pendingResolutions removeAllObjects];

      sigaction(SIGABRT, &oldAct, NULL);

      NSWarnMLog(@"NetworkServiceManager: mDNS daemon unavailable — "
                 "SIGABRT caught, network thread exiting");
    }
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
    return;
  }

  if (isSearching) {
    return;
  }


  /* The primary safety net is the sigsetjmp/siglongjmp SIGABRT handler
     installed in -networkThreadMain, which catches C-level assert()
     failures from the Avahi library.  The @try/@catch below is a
     secondary layer that covers ObjC-level exceptions from the backend
     (e.g., D-Bus errors surfaced as NSException). */
  @try {
    /* Start browsing for SFTP-SSH services */
    sftpBrowser = [[NSNetServiceBrowser alloc] init];
    [sftpBrowser setDelegate:self];
    [sftpBrowser searchForServicesOfType:@"_sftp-ssh._tcp." inDomain:@"local."];

    /* Start browsing for AFP over TCP services */
    afpBrowser = [[NSNetServiceBrowser alloc] init];
    [afpBrowser setDelegate:self];
    [afpBrowser searchForServicesOfType:@"_afpovertcp._tcp." inDomain:@"local."];

    /* Start browsing for WebDAV services (HTTP) */
    webdavBrowser = [[NSNetServiceBrowser alloc] init];
    [webdavBrowser setDelegate:self];
    [webdavBrowser searchForServicesOfType:@"_webdav._tcp." inDomain:@"local."];

    /* Start browsing for WebDAV services (HTTPS) */
    webdavsBrowser = [[NSNetServiceBrowser alloc] init];
    [webdavsBrowser setDelegate:self];
    [webdavsBrowser searchForServicesOfType:@"_webdavs._tcp." inDomain:@"local."];

    /* Start browsing for SMB (Windows file sharing) services */
    smbBrowser = [[NSNetServiceBrowser alloc] init];
    [smbBrowser setDelegate:self];
    [smbBrowser searchForServicesOfType:@"_smb._tcp." inDomain:@"local."];

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
    if (smbBrowser) {
      [smbBrowser stop];
      [smbBrowser release];
      smbBrowser = nil;
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

  if (smbBrowser) {
    [smbBrowser stop];
    [smbBrowser release];
    smbBrowser = nil;
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

- (NSArray *)smbServices
{
  @synchronized(services) {
    NSMutableArray *result = [NSMutableArray array];
    for (NetworkServiceItem *item in services) {
      if ([item isSMBService]) {
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

- (NetworkServiceItem *)existingServiceMatchingName:(NSString *)serviceName
                                              type:(NSString *)serviceType
{
  for (NetworkServiceItem *item in services) {
    if ([[item name] isEqual:serviceName] && [[item type] isEqual:serviceType]) {
      return item;
    }
  }
  return nil;
}

- (NetworkServiceItem *)existingServiceMatchingNetService:(NSNetService *)netService
{
  return [self existingServiceMatchingName:[netService name]
                                      type:[netService type]];
}

/* NetBIOS names are case-insensitive and mDNS lists the same machine under
   its own spelling, so a host found by both ways must be matched loosely. */
- (NetworkServiceItem *)existingSMBServiceNamed:(NSString *)serviceName
                                        address:(NSData *)address
{
  for (NetworkServiceItem *item in services) {
    if (![item isSMBService]) {
      continue;
    }
    if ([[item name] caseInsensitiveCompare:serviceName] == NSOrderedSame) {
      return item;
    }
    if (address && [[item addresses] containsObject:address]) {
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
    if ([self existingServiceMatchingName:[item name] type:[item type]] != nil) {
      return;
    }
    /* The same Windows host may already be listed by WS-Discovery. */
    if ([item isSMBService]
        && [self existingSMBServiceNamed:[item name] address:nil] != nil) {
      return;
    }

    [services addObject:item];
    added = [NSArray arrayWithObject:item];
  }

  /* Post notification on main thread */
  NSDictionary *userInfo = @{@"addedServices": added, @"removedServices": @[]};
  [self performSelectorOnMainThread:@selector(postServicesChangedOnMainThread:)
                         withObject:userInfo
                      waitUntilDone:NO];
}

- (void)addManualSMBServiceWithName:(NSString *)name
                            address:(NSString *)ipAddress
                               port:(int)port
                           hostName:(NSString *)hostName
{
  NSData *address = nil;
#ifndef _WIN32
  struct sockaddr_in sin;
  memset(&sin, 0, sizeof(sin));
  sin.sin_family = AF_INET;
  sin.sin_port = htons((uint16_t)port);
  if (inet_pton(AF_INET, [ipAddress UTF8String], &sin.sin_addr) == 1) {
    address = [NSData dataWithBytes:&sin length:sizeof(sin)];
  }
#endif

  NetworkServiceItem *item = [[[NetworkServiceItem alloc] init] autorelease];
  item.name = name;
  item.type = @"_smb._tcp.";
  item.domain = @"local.";
  item.hostName = hostName;
  item.port = port;
  item.addresses = address ? [NSArray arrayWithObject:address] : nil;
  item.resolved = YES;

  @synchronized(services) {
    if ([self existingSMBServiceNamed:name address:address] != nil) {
      return;
    }
    [services addObject:item];
  }

  NSDictionary *userInfo = @{@"addedServices": @[item], @"removedServices": @[]};
  [self performSelectorOnMainThread:@selector(postServicesChangedOnMainThread:)
                         withObject:userInfo
                      waitUntilDone:NO];
}

- (void)removeManualSMBServiceNamed:(NSString *)name
{
  NetworkServiceItem *removed = nil;

  @synchronized(services) {
    for (NetworkServiceItem *item in services) {
      /* Only hosts that were added by hand: an mDNS item has a netService
         and leaves through its own browser callback. */
      if ([item isSMBService] && [item netService] == nil
          && [[item name] caseInsensitiveCompare:name] == NSOrderedSame) {
        removed = [[item retain] autorelease];
        break;
      }
    }
    if (removed == nil) {
      return;
    }
    [services removeObject:removed];
  }

  NSDictionary *userInfo = @{@"addedServices": @[], @"removedServices": @[removed]};
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
}

- (void)netServiceBrowserDidStopSearch:(NSNetServiceBrowser *)browser
{
}

- (void)netServiceBrowser:(NSNetServiceBrowser *)browser
           didFindService:(NSNetService *)netService
               moreComing:(BOOL)moreComing
{
  /* Create a service item and add it */
  NetworkServiceItem *item = [NetworkServiceItem itemWithNetService:netService];
  [self addServiceItem:item];

  /* A network that just announced something is the moment to look for the
     hosts that never announce. */
  [[SMBDiscovery sharedDiscovery] requestFallbackRefresh];

  /* Start resolving the service to get host/port info */
  [netService setDelegate:self];
  [netService resolveWithTimeout:10.0];
  [pendingResolutions addObject:netService];
}

- (void)netServiceBrowser:(NSNetServiceBrowser *)browser
         didRemoveService:(NSNetService *)netService
               moreComing:(BOOL)moreComing
{
  [self removeServiceMatchingNetService:netService];
  [pendingResolutions removeObject:netService];
}

- (void)netServiceBrowser:(NSNetServiceBrowser *)browser
             didNotSearch:(NSDictionary *)errorDict
{
}

#pragma mark - NSNetServiceDelegate

- (void)netServiceDidResolveAddress:(NSNetService *)netService
{

  /* Find and update the corresponding item */
  @synchronized(services) {
    NetworkServiceItem *item = [self existingServiceMatchingNetService:netService];
    if (item) {
      [self updateServiceItem:item fromNetService:netService];

      /* If the resolved service is on the local machine itself
         (hostName is localhost/127.0.0.1, or has a loopback address),
         remove it from the list so it doesn't appear in the sidebar.
         This also posts NetworkServicesDidChangeNotification so the
         UI rebuilds immediately. */
      if ([item isLocalMachine]) {
        [services removeObject:item];
        // Post removal notification on main thread
        NSDictionary *userInfo = @{@"addedServices": @[], @"removedServices": @[item]};
        [self performSelectorOnMainThread:@selector(postServicesChangedOnMainThread:)
                               withObject:userInfo
                            waitUntilDone:NO];
      }
    }
  }

  [pendingResolutions removeObject:netService];
}

- (void)netService:(NSNetService *)netService
     didNotResolve:(NSDictionary *)errorDict
{

  [pendingResolutions removeObject:netService];
}

@end
