/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

/* A cached SMB host that stops answering must leave the Network folder,
 * also on a network where it was the only SMB host: it is asked directly
 * every round, so its own silence is enough. */

#import <Foundation/Foundation.h>
#import "Testing.h"
#import "SMBDiscovery.h"

static NSMutableDictionary *
host(NSString *address, int misses)
{
  return [NSMutableDictionary dictionaryWithObjectsAndKeys:
            address, @"address",
            [NSNumber numberWithInt: misses], @"misses",
            nil];
}

static int
missesOf(NSDictionary *cache, NSString *name)
{
  return [[[cache objectForKey: name] objectForKey: @"misses"] intValue];
}

int
main(void)
{
  NSAutoreleasePool *arp = [NSAutoreleasePool new];
  NSMutableDictionary *cache;
  NSArray *dropped;

  START_SET("cache expiry")
    cache = [NSMutableDictionary dictionaryWithObject: host(@"192.0.2.52", 0)
                                               forKey: @"MUSIC"];
    dropped = [SMBDiscovery namesDroppedFromCache: cache
                                      afterSeeing: [NSDictionary dictionary]
                                        networkUp: YES];
    PASS([dropped count] == 0 && missesOf(cache, @"MUSIC") == 1,
         "the only host on the network not answering gets a miss");
    dropped = [SMBDiscovery namesDroppedFromCache: cache
                                      afterSeeing: [NSDictionary dictionary]
                                        networkUp: YES];
    PASS([dropped isEqual: [NSArray arrayWithObject: @"MUSIC"]]
         && [cache objectForKey: @"MUSIC"] == nil,
         "and leaves after the second round in a row without an answer");

    cache = [NSMutableDictionary dictionaryWithObject: host(@"192.0.2.52", 1)
                                               forKey: @"MUSIC"];
    dropped = [SMBDiscovery namesDroppedFromCache: cache
                                      afterSeeing: [NSDictionary dictionary]
                                        networkUp: NO];
    PASS([dropped count] == 0 && missesOf(cache, @"MUSIC") == 1,
         "a round without any network interface counts nothing");

    cache = [NSMutableDictionary dictionaryWithObjectsAndKeys:
               host(@"192.0.2.52", 1), @"MUSIC",
               host(@"192.0.2.53", 0), @"OFFICE", nil];
    dropped = [SMBDiscovery namesDroppedFromCache: cache
                                      afterSeeing: [NSDictionary dictionaryWithObject:
                                                     host(@"192.0.2.52", 0)
                                                                         forKey: @"MUSIC"]
                                        networkUp: YES];
    PASS([dropped count] == 0 && missesOf(cache, @"MUSIC") == 0
         && missesOf(cache, @"OFFICE") == 1,
         "an answer clears the misses, silence adds one");
  END_SET("cache expiry")

  [arp release];
  return 0;
}
