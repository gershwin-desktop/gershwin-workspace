/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

/* t_GWQuickLookGeometry.m - Quick Look's window covers 80% of the screen's
 * visible frame, centered in it, regardless of the scale-factor convention
 * the visible frame itself already carries (see the
 * gnustep-scale-factor-pitfalls skill: NSScreen frames are device pixels
 * even at GSScaleFactor != 1, so the formula never multiplies by a scale
 * itself - it just takes 80% of whatever rect it is given).  Headless: no
 * display needed for plain NSRect arithmetic. */

#include <math.h>
#import <Foundation/Foundation.h>
#import "Testing.h"
#include "../../Workspace/QuickLook/GWQuickLookGeometry.m"

int main(void)
{
  NSAutoreleasePool *arp = [NSAutoreleasePool new];

  /* A 1.0-scale-like convention: a plain 1920x1080 screen with a menu
   * strip already excluded from the visible frame's height. */
  {
    NSRect visible = NSMakeRect(0, 0, 1920, 1058);
    NSRect got = GWQuickLookFrameForVisibleFrame(visible);

    PASS(got.size.width == floor(visible.size.width * 0.8),
      "width is 80%% of the visible frame (1.0 convention)");
    PASS(got.size.height == floor(visible.size.height * 0.8),
      "height is 80%% of the visible frame (1.0 convention)");
    PASS(EQ(NSMinX(got) - NSMinX(visible), NSMaxX(visible) - NSMaxX(got)),
      "centered horizontally (1.0 convention)");
    PASS(EQ(NSMinY(got) - NSMinY(visible), NSMaxY(visible) - NSMaxY(got)),
      "centered vertically (1.0 convention)");
    PASS(NSContainsRect(visible, got),
      "the 80%% rect stays fully inside the visible frame (1.0 convention)");
  }

  /* A 1.25-scale-like convention: the larger device-pixel numbers a higher
   * GSScaleFactor already bakes into NSScreen's own frame, with a non-zero
   * origin (as if this were a secondary monitor) so a formula that
   * silently assumes the frame starts at (0,0) would be caught. */
  {
    NSRect visible = NSMakeRect(2400, 60, 2400, 1260);
    NSRect got = GWQuickLookFrameForVisibleFrame(visible);

    PASS(got.size.width == floor(visible.size.width * 0.8),
      "width is 80%% of the visible frame (1.25 convention)");
    PASS(got.size.height == floor(visible.size.height * 0.8),
      "height is 80%% of the visible frame (1.25 convention)");
    PASS(EQ(NSMinX(got) - NSMinX(visible), NSMaxX(visible) - NSMaxX(got)),
      "centered horizontally (1.25 convention)");
    PASS(EQ(NSMinY(got) - NSMinY(visible), NSMaxY(visible) - NSMaxY(got)),
      "centered vertically (1.25 convention)");
    PASS(NSContainsRect(visible, got),
      "the 80%% rect stays fully inside the visible frame (1.25 convention)");
  }

  [arp release];
  return 0;
}
