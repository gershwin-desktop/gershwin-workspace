/* SMBDiscovery.h
 *
 * Finds SMB/Windows hosts that do not announce themselves through mDNS:
 * Windows 10 and 11 answer WS-Discovery (what its "Network" view uses) and,
 * when NetBIOS over TCP/IP is enabled, node status queries.  The hosts found
 * are handed to NetworkServiceManager as _smb._tcp. items so that they show
 * up in the sidebar and in the Network viewer next to the mDNS services.
 *
 * Author: Simon Peter
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

#import <Foundation/Foundation.h>

@class NetworkServiceManager;

@interface SMBDiscovery : NSObject
{
  NetworkServiceManager *manager;
  NSMutableDictionary *hostCache;   // NetBIOS name -> record
  NSCondition *wakeup;
  BOOL refreshRequested;
  BOOL workerStarted;
  NSDate *lastRound;
}

+ (instancetype)sharedDiscovery;

/**
 * Loads the host cache and starts the background worker.  The worker shows
 * the cached hosts that still answer at their address, then runs the first
 * probe round a few seconds later so that Workspace startup is not slowed
 * down, and another one every few minutes.
 */
- (void)startupWithServiceManager:(NetworkServiceManager *)aManager;

/**
 * Asks for another probe round.  Rounds are coalesced and keep at least
 * 45 seconds apart; the call never blocks.  mDNS events call this because a
 * network that just came up is the moment new hosts appear.
 */
- (void)requestFallbackRefresh;

/**
 * Picks the file server name and the workgroup out of the NBSTAT names
 * list (the "names" array of +[NBNSProbe nodeStatusOfHost:timeout:]).
 * Returns a dictionary with "name" and optionally "workgroup", or nil when
 * the host does not register a file server (type 0x20) name.  Class-level so
 * tests need no network.
 */
+ (NSDictionary *)hostRecordFromNodeStatusNames:(NSArray *)names;

/**
 * Brings the host cache (name -> mutable record with "misses") up to date
 * after a round in which the hosts in seen answered: every cached host that
 * did not answer gets one more miss, and one missed often enough leaves the
 * cache.  Every cached host is asked directly in each round, so silence is
 * its own answer; only a round with no network interface to ask on counts
 * nothing.  Returns the names that left.  Class-level so tests need no
 * network.
 */
+ (NSArray *)namesDroppedFromCache:(NSMutableDictionary *)cache
                       afterSeeing:(NSDictionary *)seen
                         networkUp:(BOOL)networkUp;

@end
