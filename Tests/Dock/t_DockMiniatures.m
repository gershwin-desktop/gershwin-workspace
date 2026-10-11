/* t_DockMiniatures.m - headless coverage for which minimized windows the
 * Dock shows as live miniatures.
 *
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

#import <Foundation/Foundation.h>
#import "Testing.h"
#import "DockMiniatures.h"

static NSArray *
W(int a, int b, int c, int d)
{
  NSMutableArray *r = [NSMutableArray array];
  int v[4] = { a, b, c, d };
  int i;

  for (i = 0; i < 4; i++)
    if (v[i] != 0)
      [r addObject: [NSNumber numberWithInt: v[i]]];
  return r;
}

int
main(void)
{
  NSAutoreleasePool *arp = [NSAutoreleasePool new];

  PASS([DockMiniaturesToShow(W(1, 2, 0, 0), W(0, 0, 0, 0), W(0, 0, 0, 0), 8)
         isEqual: W(1, 2, 0, 0)],
       "listed windows get tiles in list order");
  PASS([DockMiniaturesToShow(W(3, 1, 2, 0), W(2, 1, 0, 0), W(0, 0, 0, 0), 8)
         isEqual: W(2, 1, 3, 0)],
       "tiles shown already keep their places, new ones follow");
  PASS([DockMiniaturesToShow(W(2, 0, 0, 0), W(1, 2, 0, 0), W(0, 0, 0, 0), 8)
         isEqual: W(2, 0, 0, 0)],
       "a window no longer listed loses its tile");
  PASS([DockMiniaturesToShow(W(1, 2, 3, 4), W(0, 0, 0, 0), W(0, 0, 0, 0), 3)
         isEqual: W(1, 2, 3, 0)],
       "no more tiles than the limit");
  PASS([DockMiniaturesToShow(W(1, 2, 3, 4), W(1, 2, 3, 0), W(4, 0, 0, 0), 3)
         isEqual: W(1, 2, 3, 0)],
       "a window beyond the limit gets no tile");
  PASS([DockMiniaturesToShow(W(2, 3, 4, 0), W(2, 3, 0, 0), W(4, 0, 0, 0), 3)
         isEqual: W(2, 3, 0, 0)],
       "a window left out stays out when room frees up");
  PASS([DockMiniaturesToShow(W(2, 3, 5, 0), W(2, 3, 0, 0), W(4, 0, 0, 0), 3)
         isEqual: W(2, 3, 5, 0)],
       "a window minimized after the room freed up gets a tile");
  PASS([DockMiniaturesToShow(W(1, 2, 0, 0), W(0, 0, 0, 0), W(0, 0, 0, 0), 0)
         isEqual: W(0, 0, 0, 0)],
       "a limit of 0 shows none");

  [arp release];
  return 0;
}
