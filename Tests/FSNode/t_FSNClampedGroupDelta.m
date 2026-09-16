/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 */

/* Headless coverage for FSNClampedGroupDelta, which keeps a dragged group of
 * icons inside its view, both while the drag runs (FSNIcon) and when icons
 * are dropped back into the view (FSNIconsView).  It is a Foundation-only
 * inline in FSNIconPlacement.h, so it runs without gnustep-gui. */

#import <Foundation/Foundation.h>
#import "Testing.h"
#import "FSNIconPlacement.h"

int
main(void)
{
  NSAutoreleasePool *arp = [NSAutoreleasePool new];

  NSRect bounds = NSMakeRect(0, 0, 400, 300);
  NSRect icon = NSMakeRect(100, 100, 64, 64);
  NSSize d;

  d = FSNClampedGroupDelta(icon, bounds, NSMakeSize(50, -30));
  PASS(d.width == 50 && d.height == -30,
       "a move that stays inside the view is left alone");

  d = FSNClampedGroupDelta(icon, bounds, NSMakeSize(1000, 0));
  PASS(icon.origin.x + d.width + icon.size.width == NSMaxX(bounds),
       "a move past the right edge stops at the edge");

  d = FSNClampedGroupDelta(icon, bounds, NSMakeSize(-1000, 0));
  PASS(icon.origin.x + d.width == NSMinX(bounds),
       "a move past the left edge stops at the edge");

  d = FSNClampedGroupDelta(icon, bounds, NSMakeSize(0, 1000));
  PASS(icon.origin.y + d.height + icon.size.height == NSMaxY(bounds),
       "a move past the top edge stops at the edge");

  d = FSNClampedGroupDelta(icon, bounds, NSMakeSize(0, -1000));
  PASS(icon.origin.y + d.height == NSMinY(bounds),
       "a move past the bottom edge stops at the edge");

  /* A multiple selection is clamped by one delta, so the icons keep their
   * offsets to each other at the edge. */
  {
    NSRect a = NSMakeRect(300, 100, 64, 64);
    NSRect b = NSMakeRect(200, 100, 64, 64);
    NSRect group = NSUnionRect(a, b);
    NSSize gd = FSNClampedGroupDelta(group, bounds, NSMakeSize(500, 0));

    PASS(NSMaxX(a) + gd.width == NSMaxX(bounds),
         "the leading icon of a group stops at the edge");
    PASS((a.origin.x + gd.width) - (b.origin.x + gd.width) == 100,
         "the icons of a group keep their spacing");
  }

  /* A group wider than the view cannot fit: pin it to the left edge rather
   * than leave it hanging off both sides. */
  {
    NSRect wide = NSMakeRect(-50, 100, 600, 64);
    NSSize wd = FSNClampedGroupDelta(wide, bounds, NSMakeSize(0, 0));

    PASS(wide.origin.x + wd.width == NSMinX(bounds),
         "a group wider than the view is pinned to the left edge");
  }

  /* A view scrolled to a non-zero bounds origin clamps to that origin. */
  {
    NSRect scrolled = NSMakeRect(0, 500, 400, 300);
    NSSize sd = FSNClampedGroupDelta(NSMakeRect(100, 600, 64, 64), scrolled,
                                     NSMakeSize(0, -1000));

    PASS(600 + sd.height == NSMinY(scrolled),
         "clamping follows the view's own bounds origin");
  }

  [arp release];
  return 0;
}
