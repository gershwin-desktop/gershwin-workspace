/* t_DockInsertion.m - headless coverage for how items grow into the Dock.
 *
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

#import <Foundation/Foundation.h>
#import "Testing.h"
#import "DockInsertion.h"

#define CLOSE(a, b) (fabs((a) - (b)) < 0.001)

int
main(void)
{
  NSAutoreleasePool *arp = [NSAutoreleasePool new];
  NSTimeInterval d = DOCK_INSERTION_DURATION;
  CGFloat prev = -1;
  BOOL rising = YES;
  int i;

  PASS(CLOSE(DockInsertionPresence(0, d), 0.0), "an item just added takes no room");
  PASS(CLOSE(DockInsertionPresence(d, d), 1.0), "an item has its whole cell when the time is up");
  PASS(CLOSE(DockInsertionPresence(10 * d, d), 1.0), "and keeps it");
  PASS(CLOSE(DockInsertionPresence(-1, d), 0.0), "a clock that went back takes no room");
  PASS(CLOSE(DockInsertionPresence(0, 0), 1.0), "no duration means no animation");
  PASS(DockInsertionPresence(d / 2, d) > 0.5, "the gap opens fast and settles");
  for (i = 0; i <= 30; i++)
    {
      CGFloat p = DockInsertionPresence(d * i / 30, d);

      if (p < prev)
        rising = NO;
      prev = p;
    }
  PASS(rising, "the item never shrinks while it grows in");

  PASS(CLOSE(DockInsertionLead(64), 32), "the bar stays centred: half the missing length on either side");
  PASS(CLOSE(DockInsertionLead(0), 0), "nothing growing, nothing to make up");

  [arp release];
  return 0;
}
