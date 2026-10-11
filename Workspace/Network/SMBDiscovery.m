/* SMBDiscovery.m
 *
 * Author: Simon Peter
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

#import "SMBDiscovery.h"
#import "NBNSProbe.h"
#import "WSDiscoveryProbe.h"
#import "NetworkServiceManager.h"

static NSString * const SMBHostCacheKey = @"GWSMBHostCacheV1";
static const NSTimeInterval SMBStartupDelay = 6.0;
static const NSTimeInterval SMBMinRoundGap = 45.0;
/* A host that was missed in this many rounds in a row leaves the list; one
   missed round is just a lost UDP datagram or a sleeping laptop. */
static const int SMBMaxMisses = 2;
/* Rounds otherwise only run when mDNS sees something, which on a network
   without mDNS services is never: a host that went away would stay. */
static const NSTimeInterval SMBPeriodicRound = 300.0;
/* How long a cached host gets to answer before it is shown at startup. */
static const NSTimeInterval SMBVerifyTimeout = 0.8;

@implementation SMBDiscovery

+ (instancetype)sharedDiscovery
{
  static SMBDiscovery *shared = nil;
  @synchronized(self) {
    if (shared == nil) {
      shared = [[SMBDiscovery alloc] init];
    }
  }
  return shared;
}

- (instancetype)init
{
  self = [super init];
  if (self) {
    hostCache = [[NSMutableDictionary alloc] init];
    wakeup = [[NSCondition alloc] init];
  }
  return self;
}

#pragma mark - Parsing

+ (NSDictionary *)hostRecordFromNodeStatusNames:(NSArray *)names
{
  NSString *serverName = nil;
  NSString *workgroup = nil;
  for (NSDictionary *entry in names) {
    int type = [[entry objectForKey:@"type"] intValue];
    BOOL group = [[entry objectForKey:@"group"] boolValue];
    NSString *name = [entry objectForKey:@"name"];
    if ([name length] == 0) {
      continue;
    }
    if (type == 0x20 && !group && !serverName) {
      serverName = name;
    } else if (type == 0x00 && group && !workgroup) {
      workgroup = name;
    }
  }
  if (!serverName) {
    return nil;
  }
  NSMutableDictionary *record = [NSMutableDictionary
      dictionaryWithObject:serverName forKey:@"name"];
  if (workgroup) {
    [record setObject:workgroup forKey:@"workgroup"];
  }
  return record;
}

+ (NSArray *)namesDroppedFromCache:(NSMutableDictionary *)cache
                       afterSeeing:(NSDictionary *)seen
                         networkUp:(BOOL)networkUp
{
  NSMutableArray *dropped = [NSMutableArray array];

  for (NSString *name in seen) {
    NSMutableDictionary *record = [NSMutableDictionary
        dictionaryWithDictionary:[seen objectForKey:name]];
    [record setObject:[NSNumber numberWithInt:0] forKey:@"misses"];
    [cache setObject:record forKey:name];
  }
  if (!networkUp) {
    return dropped;
  }
  for (NSString *name in [cache allKeys]) {
    if ([seen objectForKey:name]) {
      continue;
    }
    NSMutableDictionary *record = [cache objectForKey:name];
    int misses = [[record objectForKey:@"misses"] intValue] + 1;
    if (misses >= SMBMaxMisses) {
      [dropped addObject:name];
      [cache removeObjectForKey:name];
    } else {
      [record setObject:[NSNumber numberWithInt:misses] forKey:@"misses"];
    }
  }
  return dropped;
}

#pragma mark - Cache

- (void)loadCache
{
  NSDictionary *saved = [[NSUserDefaults standardUserDefaults]
                          dictionaryForKey:SMBHostCacheKey];
  for (NSString *name in saved) {
    NSDictionary *record = [saved objectForKey:name];
    if ([record isKindOfClass:[NSDictionary class]]
        && [[record objectForKey:@"address"] length] > 0) {
      [hostCache setObject:[NSMutableDictionary dictionaryWithDictionary:record]
                    forKey:name];
    }
  }
}

- (void)saveCache
{
  NSDictionary *snapshot;
  @synchronized(hostCache) {
    snapshot = [[hostCache copy] autorelease];
  }
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
  [defaults setObject:snapshot forKey:SMBHostCacheKey];
  [defaults synchronize];
}

- (void)publishHostNamed:(NSString *)name record:(NSDictionary *)record
{
  [manager addManualSMBServiceWithName:name
                               address:[record objectForKey:@"address"]
                                  port:445
                              hostName:[record objectForKey:@"address"]];
}

#pragma mark - Worker

- (void)startupWithServiceManager:(NetworkServiceManager *)aManager
{
  if (workerStarted) {
    return;
  }
  workerStarted = YES;
  manager = aManager;

  [self loadCache];

  refreshRequested = YES;
  [NSThread detachNewThreadSelector:@selector(workerMain)
                           toTarget:self
                         withObject:nil];
}

- (void)requestFallbackRefresh
{
  [wakeup lock];
  refreshRequested = YES;
  [wakeup signal];
  [wakeup unlock];
}

/* The cache remembers hosts from earlier sessions, some of them long gone;
   each is shown only once it answers at its old address under its old name.
   The others wait for the round, which asks them again. */
- (void)showCachedHostsThatAnswer
{
  NSDictionary *snapshot;

  @synchronized(hostCache) {
    snapshot = [[hostCache copy] autorelease];
  }
  for (NSString *name in snapshot) {
    NSDictionary *record = [snapshot objectForKey:name];
    NSDictionary *status = [NBNSProbe nodeStatusOfHost:[record objectForKey:@"address"]
                                               timeout:SMBVerifyTimeout];
    NSDictionary *answer = [SMBDiscovery hostRecordFromNodeStatusNames:
                             [status objectForKey:@"names"]];
    if ([[[answer objectForKey:@"name"] uppercaseString] isEqual:name]) {
      [self publishHostNamed:name record:record];
    }
  }
}

- (void)workerMain
{
  @autoreleasepool {
    [[NSThread currentThread] setName:@"GWSMBDiscovery"];
    [self showCachedHostsThatAnswer];
    [NSThread sleepForTimeInterval:SMBStartupDelay];
  }

  for (;;) {
    @autoreleasepool {
      [wakeup lock];
      while (!refreshRequested) {
        if (![wakeup waitUntilDate:
               [NSDate dateWithTimeIntervalSinceNow:SMBPeriodicRound]]) {
          refreshRequested = YES;
        }
      }
      [wakeup unlock];

      if (lastRound) {
        NSTimeInterval wait = SMBMinRoundGap + [lastRound timeIntervalSinceNow];
        if (wait > 0) {
          [NSThread sleepForTimeInterval:wait];
        }
      }

      /* Requests that arrive during the round itself start the next one. */
      [wakeup lock];
      refreshRequested = NO;
      [wakeup unlock];

      [self runRound];
      [lastRound release];
      lastRound = [[NSDate date] retain];
    }
  }
}

#pragma mark - One probe round

- (void)runRound
{
  /* ip -> {address, name?, workgroup?} */
  NSMutableDictionary *candidates = [NSMutableDictionary dictionary];

  for (NSDictionary *device in
         [WSDiscoveryProbe probeComputerDevicesWithTimeout:3.0]) {
    NSString *ip = [device objectForKey:@"address"];
    if (ip) {
      [candidates setObject:[NSMutableDictionary dictionaryWithDictionary:device]
                     forKey:ip];
    }
  }

  for (NSString *ip in [NBNSProbe broadcastQueriedHostsWithTimeout:1.5]) {
    if (![candidates objectForKey:ip]) {
      [candidates setObject:[NSMutableDictionary
                              dictionaryWithObject:ip forKey:@"address"]
                     forKey:ip];
    }
  }

  /* Cached hosts that neither probe returned are asked directly: a unicast
     node status query gets through access points that drop broadcasts. */
  @synchronized(hostCache) {
    for (NSString *name in hostCache) {
      NSString *ip = [[hostCache objectForKey:name] objectForKey:@"address"];
      if (ip && ![candidates objectForKey:ip]) {
        [candidates setObject:[NSMutableDictionary
                                dictionaryWithObject:ip forKey:@"address"]
                       forKey:ip];
      }
    }
  }

  NSMutableDictionary *seen = [NSMutableDictionary dictionary];
  for (NSString *ip in candidates) {
    if ([NBNSProbe isLocalIPv4Address:ip]) {
      continue;
    }
    NSMutableDictionary *candidate = [candidates objectForKey:ip];
    NSString *name = [candidate objectForKey:@"name"];
    NSString *workgroup = [candidate objectForKey:@"workgroup"];

    if (!name) {
      NSDictionary *status = [NBNSProbe nodeStatusOfHost:ip timeout:0.8];
      NSDictionary *record = [SMBDiscovery hostRecordFromNodeStatusNames:
                               [status objectForKey:@"names"]];
      name = [record objectForKey:@"name"];
      if (!workgroup) {
        workgroup = [record objectForKey:@"workgroup"];
      }
    }
    if ([name length] == 0) {
      continue;
    }

    NSMutableDictionary *record = [NSMutableDictionary
        dictionaryWithObjectsAndKeys:ip, @"address", nil];
    if (workgroup) {
      [record setObject:workgroup forKey:@"workgroup"];
    }
    [seen setObject:record forKey:[name uppercaseString]];
  }

  [self mergeSeenHosts:seen];
}

- (void)mergeSeenHosts:(NSDictionary *)seen
{
  NSArray *dropped;
  /* With no interface up nothing could be asked, and silence means nothing. */
  BOOL networkUp = [[NBNSProbe localIPv4Addresses] count] > 0;

  @synchronized(hostCache) {
    dropped = [SMBDiscovery namesDroppedFromCache:hostCache
                                      afterSeeing:seen
                                        networkUp:networkUp];
    for (NSString *name in seen) {
      [self publishHostNamed:name record:[hostCache objectForKey:name]];
    }
  }

  for (NSString *name in dropped) {
    [manager removeManualSMBServiceNamed:name];
  }
  [self saveCache];
}

@end
