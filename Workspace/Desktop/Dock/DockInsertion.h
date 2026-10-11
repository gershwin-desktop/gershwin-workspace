/* DockInsertion.h
 *
 * How an item added to the Dock grows in: its cell opens from nothing to a
 * full cell while the item grows with it, and the items around it slide
 * apart instead of jumping.  Foundation-only inline code so that it can be
 * tested headless.
 *
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

#ifndef DOCK_INSERTION_H
#define DOCK_INSERTION_H

#import <Foundation/Foundation.h>

/* How long an added item takes to grow in. */
#define DOCK_INSERTION_DURATION 0.3

/* How much of its cell an item added elapsed seconds ago takes, from 0 to 1.
 * It starts fast and settles (a cubic ease-out), so the gap opens at once
 * where the item arrives. */
static inline CGFloat
DockInsertionPresence(NSTimeInterval elapsed, NSTimeInterval duration)
{
  double t, rest;

  if (duration <= 0)
    return 1.0;
  t = elapsed / duration;
  if (t <= 0)
    return 0.0;
  if (t >= 1)
    return 1.0;
  rest = 1.0 - t;
  return 1.0 - rest * rest * rest;
}

/* The Dock window takes the size of the whole Dock at once, centred, while
 * the bar inside it only grows as its items do.  Starting the items this far
 * in keeps the bar centred, so the items already there stay where they were
 * on the screen and only slide apart.  missing is the length the growing
 * items do not take yet. */
static inline CGFloat
DockInsertionLead(CGFloat missing)
{
  return missing / 2.0;
}

#endif
