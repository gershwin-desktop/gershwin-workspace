/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

/* t_GWLookInsideGeometry.m - Look Inside's window covers 80% of the screen's
 * visible frame, centered in it, regardless of the scale-factor convention
 * the visible frame itself already carries (see the
 * gnustep-scale-factor-pitfalls skill: NSScreen frames are device pixels
 * even at GSScaleFactor != 1, so the formula never multiplies by a scale
 * itself - it just takes 80% of whatever rect it is given).  Headless: no
 * display needed for plain NSRect arithmetic. */

#include <math.h>
#import <Foundation/Foundation.h>
#import "Testing.h"
#include "../../Workspace/LookInside/GWLookInsideGeometry.m"

int main(void)
{
  NSAutoreleasePool *arp = [NSAutoreleasePool new];

  /* A 1.0-scale-like convention: a plain 1920x1080 screen with a menu
   * strip already excluded from the visible frame's height. */
  {
    NSRect visible = NSMakeRect(0, 0, 1920, 1058);
    NSRect got = GWLookInsideFrameForVisibleFrame(visible);

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
    NSRect got = GWLookInsideFrameForVisibleFrame(visible);

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

  /* The window is CONSTRUCTED with a content rect in points (screen-pixel
   * origin, point-sized - see GWLookInsidePanel.m -initWithPaths:
   * sourceWindow: on why only the size divides by the scale factor, not
   * the origin): at GSScaleFactor 1.25 a 1920x1080 visible frame's 80%
   * pixel rect (1536x864, centered at 192,108) must become a 1228.8x691.2
   * pt content rect, so the backend's own re-multiplication by 1.25 lands
   * back on exactly 1536x864 device pixels - not something smaller (the
   * bug: passing the pixel rect directly as points, which the backend
   * then multiplies AGAIN, growing the window past 80%). */
  {
    NSRect visible = NSMakeRect(0, 0, 1920, 1080);
    NSRect content = GWLookInsideContentRectForVisibleFrame(visible, 1.25);

    PASS(EQ(content.origin.x, 192) && EQ(content.origin.y, 108),
      "content rect origin stays in screen pixels (1.25 scale)");
    PASS(EQ(content.size.width, 1228.8),
      "content width is 1536px / 1.25 = 1228.8pt (1.25 scale)");
    PASS(EQ(content.size.height, 691.2),
      "content height is 864px / 1.25 = 691.2pt (1.25 scale)");
    PASS(EQ(content.size.width * 1.25, 1536) && EQ(content.size.height * 1.25, 864),
      "multiplying back by the scale reproduces whole device pixels (1.25 scale)");
  }

  /* At scale 1.0 the content rect must be unchanged (dividing by 1 is a
   * no-op), matching the live desktop's unaffected behavior. */
  {
    NSRect visible = NSMakeRect(0, 0, 1920, 1058);
    NSRect pixelRect = GWLookInsideFrameForVisibleFrame(visible);
    NSRect content = GWLookInsideContentRectForVisibleFrame(visible, 1.0);

    PASS(NSEqualRects(content, pixelRect),
      "content rect equals the pixel rect at scale 1.0");
  }

  /* Scale 1.5, a second non-trivial factor. */
  {
    NSRect visible = NSMakeRect(0, 0, 1920, 1080);
    NSRect content = GWLookInsideContentRectForVisibleFrame(visible, 1.5);

    PASS(EQ(content.size.width, 1024) && EQ(content.size.height, 576),
      "content size is the 1536x864px rect halved-plus-a-third at 1.5 scale");
    PASS(EQ(content.size.width * 1.5, 1536) && EQ(content.size.height * 1.5, 864),
      "multiplying back by 1.5 reproduces whole device pixels");
  }

  /* MI-LI-9: the panel comes back at the size it had when it closed,
   * centered, never larger than the visible frame. */
  {
    NSRect visible = NSMakeRect(0, 40, 1600, 1000);
    NSRect fallback = NSMakeRect(160, 140, 1280, 800);
    NSRect got = GWLookInsideFrameForSavedSize(visible, NSMakeSize(700, 500), fallback);

    PASS(EQ(got.size.width, 700) && EQ(got.size.height, 500),
      "MI-LI-9 a remembered size is used as it is");
    PASS(EQ(NSMinX(got) - NSMinX(visible), NSMaxX(visible) - NSMaxX(got))
         && EQ(NSMinY(got) - NSMinY(visible), NSMaxY(visible) - NSMaxY(got)),
      "MI-LI-9 the remembered size is centered in the visible frame");

    got = GWLookInsideFrameForSavedSize(visible, NSZeroSize, fallback);
    PASS(NSEqualRects(got, fallback), "MI-LI-9 nothing remembered gives the default frame");

    got = GWLookInsideFrameForSavedSize(visible, NSMakeSize(3000, 2000), fallback);
    PASS(NSContainsRect(visible, got) && EQ(got.size.width, 1600) && EQ(got.size.height, 1000),
      "MI-LI-9 a remembered size larger than this screen is cut to it");

    got = GWLookInsideFrameForSavedSize(visible, NSMakeSize(20, 10), fallback);
    PASS(got.size.width >= GWLookInsideMinimumFrameSize.width
         && got.size.height >= GWLookInsideMinimumFrameSize.height,
      "MI-LI-9 a remembered size below the minimum is raised to it");
  }

  /* MI-LI-10: the overview lays out every item in a grid that fits. */
  {
    NSRect bounds = NSMakeRect(0, 0, 1000, 500);
    NSUInteger count = 7, i, j;
    BOOL inside = YES, disjoint = YES, hits = YES;

    for (i = 0; i < count; i++)
      {
        NSRect a = GWLookInsideOverviewCellRect(bounds, count, i);

        if (!NSContainsRect(bounds, a) || NSIsEmptyRect(a))
          {
            inside = NO;
          }
        for (j = i + 1; j < count; j++)
          {
            if (NSIntersectsRect(a, GWLookInsideOverviewCellRect(bounds, count, j)))
              {
                disjoint = NO;
              }
          }
        if (GWLookInsideOverviewIndexAtPoint(bounds, count,
                                             NSMakePoint(NSMidX(a), NSMidY(a))) != (NSInteger)i)
          {
            hits = NO;
          }
      }
    PASS(inside, "MI-LI-10 every overview cell lies inside the view");
    PASS(disjoint, "MI-LI-10 no two overview cells overlap");
    PASS(hits, "MI-LI-10 a click in the middle of a cell picks that item");
    PASS(GWLookInsideOverviewIndexAtPoint(bounds, count, NSMakePoint(1, 1)) == -1,
      "MI-LI-10 a click in the margin picks nothing");

    {
      NSRect first = GWLookInsideOverviewCellRect(bounds, count, 0);
      NSRect second = GWLookInsideOverviewCellRect(bounds, count, 1);

      PASS(EQ(NSMinY(first), NSMinY(second)) && NSMinX(second) > NSMinX(first),
        "MI-LI-10 the grid is read left to right");
      PASS(NSMaxY(first) > NSMaxY(GWLookInsideOverviewCellRect(bounds, count, count - 1)),
        "MI-LI-10 the first row is at the top");
    }

    {
      NSRect one = GWLookInsideOverviewCellRect(NSMakeRect(0, 0, 3000, 3000), 1, 0);

      PASS(one.size.width <= GWLookInsideOverviewMaximumCellSide,
        "MI-LI-10 a lone item does not blow up to the whole screen");
    }
  }

  [arp release];
  return 0;
}
