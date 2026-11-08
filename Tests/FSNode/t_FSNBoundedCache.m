/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 */

/* The bounded cache behind FSNodeRep's icon caches: it never keeps more than
 * its capacity and drops the entries used longest ago. */

#import <Foundation/Foundation.h>
#import "Testing.h"
#import "FSNBoundedCache.h"

int
main(void)
{
  NSAutoreleasePool *arp = [NSAutoreleasePool new];
  FSNBoundedCache *cache = [[FSNBoundedCache alloc] initWithCapacity: 8];
  NSUInteger i;
  BOOL bounded = YES;

  for (i = 0; i < 100; i++)
    {
      [cache setObject: @"v" forKey: [NSString stringWithFormat: @"k%lu", (unsigned long)i]];
      if ([cache count] > 8)
        {
          bounded = NO;
        }
    }
  PASS(bounded, "a cache never holds more entries than its capacity");
  PASS([cache objectForKey: @"k99"] != nil, "the entry stored last is kept");
  PASS([cache objectForKey: @"k0"] == nil, "the entry stored first is dropped");

  [cache removeAllObjects];
  for (i = 0; i < 8; i++)
    {
      [cache setObject: @"v" forKey: [NSString stringWithFormat: @"k%lu", (unsigned long)i]];
    }
  /* k0 is the oldest entry, but reading it counts as a use. */
  PASS([cache objectForKey: @"k0"] != nil, "a full cache still has its first entry");
  [cache setObject: @"v" forKey: @"new"];
  PASS([cache objectForKey: @"k0"] != nil, "an entry read recently is kept when the cache overflows");
  PASS([cache objectForKey: @"k1"] == nil, "the entry used longest ago goes first");
  PASS([cache objectForKey: @"new"] != nil, "the entry that overflowed the cache is kept");

  [cache setObject: @"w" forKey: @"new"];
  PASS_EQUAL([cache objectForKey: @"new"], @"w", "storing under a key replaces its entry");
  [cache removeObjectForKey: @"new"];
  PASS([cache objectForKey: @"new"] == nil, "a removed entry is gone");
  [cache removeAllObjects];
  PASS([cache count] == 0, "removeAllObjects empties the cache");

  [cache release];
  [arp release];
  return 0;
}
