/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 */

/* GSDirectoryDescriptionForPath is asked once per directory entry while a
 * folder loads, so besides giving the right answer it has to stay cheap: it
 * used to walk all 467 keys of the table per call, searching each one for a
 * "*", which made string search the biggest single cost of opening a folder. */

#import <AppKit/AppKit.h>
#import "Testing.h"
#import "FSNFunctions.h"

int
main(void)
{
  NSAutoreleasePool *arp = [NSAutoreleasePool new];
  NSDate *start;
  NSTimeInterval spent;
  NSUInteger i;

  PASS_EQUAL(GSDirectoryDescriptionForPath(@"/bin"),
             @"Essential user command binaries needed in single-user mode",
             "an exact path is described");
  PASS_EQUAL(GSDirectoryDescriptionForPath(@"/"),
             @"Root of the filesystem hierarchy",
             "the root is described");
  PASS_EQUAL(GSDirectoryDescriptionForPath(@"/dev/dri/card0"),
             @"Graphics device node (card, renderD, controlD)",
             "a path under a wildcard key is described");
  PASS(GSDirectoryDescriptionForPath(@"/no/such/place/at/all") == nil,
       "an unknown path has no description");
  PASS(GSDirectoryDescriptionForPath(@"") == nil,
       "an empty path has no description");

  /* A folder of a few thousand entries asks this once per entry. */
  start = [NSDate date];
  for (i = 0; i < 3000; i++)
    {
      GSDirectoryDescriptionForPath(@"/usr/share/man/man1/gzip.1.gz");
      GSDirectoryDescriptionForPath(@"/dev/dri/card0");
    }
  spent = -[start timeIntervalSinceNow];
  /* 26 ms when the wildcard keys are picked out once, 828 ms when they were
   * searched for per call. */
  PASS(spent < 0.2,
       "six thousand lookups cost a fraction of a second");
  printf("6000 lookups took %.0f ms\n", spent * 1000.0);

  [arp release];
  return 0;
}
