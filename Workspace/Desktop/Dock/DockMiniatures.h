/* DockMiniatures.h
 *
 * Which minimized windows the Dock shows as live miniatures.  The window
 * manager lists the windows being minimized or shown live; the Dock keeps a
 * tile for each of them, up to a limit, in the order they came.  A window
 * beyond the limit gets no tile and goes into its application's icon, as
 * every minimized window did before.  Foundation-only inline code so that
 * it can be tested headless.
 *
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

#ifndef DOCK_MINIATURES_H
#define DOCK_MINIATURES_H

#import <Foundation/Foundation.h>

/* The windows (NSNumber) to show, in tile order: the ones shown already and
 * still listed keep their places, and listed windows not shown yet follow
 * in list order while there is room.  A window once left out stays out
 * while it is listed: by then the window manager has minimized it the old
 * way, and a tile made later would show nothing. */
static inline NSArray *
DockMiniaturesToShow(NSArray *listed, NSArray *shown, NSArray *refused,
                     NSUInteger limit)
{
  NSMutableArray *result = [NSMutableArray array];
  NSEnumerator *e;
  NSNumber *w;

  e = [shown objectEnumerator];
  while ((w = [e nextObject]) != nil)
    {
      if ([listed containsObject: w] && ![result containsObject: w])
        [result addObject: w];
    }
  e = [listed objectEnumerator];
  while ((w = [e nextObject]) != nil)
    {
      if ([result count] >= limit)
        break;
      if (![result containsObject: w] && ![refused containsObject: w])
        [result addObject: w];
    }
  return result;
}

#endif
