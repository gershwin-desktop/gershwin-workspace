/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-2.0-or-later
 *
 * Coverage for GWDesktopGridGeometry.h: the desktop icon grid sits on the
 * primary monitor, right-aligned to the primary's right edge, not to the
 * right edge of all monitors together (issue #135).  Headless.
 */
#import <Foundation/Foundation.h>
#import "Testing.h"
#import "../../Workspace/Desktop/GWDesktopGridGeometry.h"

static NSString * const kSuiteName = @"Desktop icon grid on the primary";

int main(void)
{
  NSAutoreleasePool *arp = [NSAutoreleasePool new];
  NSLog(@"%@", kSuiteName);

  /* View coordinates (points, bottom-left) of a 3200x1080 X screen at scale
   * 1: laptop 1280x800 at X 0,0 (GNUstep y 280), external 1920x1080 right
   * of it at X 1280,0 (GNUstep y 0).  Menu strip 25, Dock 74 at the bottom,
   * margins as in GWDesktopView.m (top -8, bottom 8). */
  NSRect laptop = NSMakeRect(0, 280, 1280, 800);
  NSRect external = NSMakeRect(1280, 0, 1920, 1080);
  NSSize dock = NSMakeSize(1280, 74);

  {
    NSRect g = GWDesktopIconGridRect(laptop, 25, DockPositionBottom, dock, -8, 8);
    PASS(NSMinX(g) == 0 && NSMaxX(g) == 1280,
         "grid spans the primary's width only, not the whole X screen");
    PASS(NSMinY(g) == 280 + 8 + 74 && NSMaxY(g) == 1080 - 25 + 8,
         "grid starts above the Dock and ends under the menu bar of the primary");

    CGFloat x = GWDesktopGridOriginX(g, 90, 10);
    /* 12 columns of 100 fit in 1280: 12 * 100 - 10 = 1190 wide, its right
     * edge half a gap left of the primary's right edge. */
    PASS(x == 1280 - 5 - 1190, "grid is right-aligned to the primary's right edge");
    PASS(x + 1190 < NSMinX(external),
         "no column of the grid lands on the monitor right of the primary");
  }

  {
    /* The external monitor made primary: the grid moves with it. */
    NSRect g = GWDesktopIconGridRect(external, 25, DockPositionBottom,
                                     NSMakeSize(1920, 74), -8, 8);
    CGFloat x = GWDesktopGridOriginX(g, 90, 10);
    PASS(NSMinX(g) == 1280 && NSMaxX(g) == 3200,
         "grid follows a primary on the right monitor");
    PASS(x == 3200 - 5 - (19 * 100 - 10),
         "grid is right-aligned to the new primary's right edge");
  }

  {
    /* Dock on the left of the primary takes its width off the left side. */
    NSRect g = GWDesktopIconGridRect(external, 25, DockPositionLeft,
                                     NSMakeSize(74, 1080), -8, 8);
    PASS(NSMinX(g) == 1280 + 74 && NSMaxX(g) == 3200
         && NSMinY(g) == 8,
         "a left Dock narrows the grid from the primary's left edge");
  }

  {
    /* GSScaleFactor 2: the laptop at X 0,0 1280x800 on a 3200x1080 screen
     * is at GNUstep 0,280 in device pixels; the view is in points. */
    NSRect v = GWDesktopPrimaryViewRect(NSMakeRect(0, 280, 1280, 800),
                                        NSZeroPoint, 2.0);
    PASS(NSEqualRects(v, NSMakeRect(0, 140, 640, 400)),
         "primary monitor converts to view points at scale 2");
    v = GWDesktopPrimaryViewRect(NSMakeRect(1280, 0, 1920, 1080),
                                 NSZeroPoint, 2.0);
    PASS(NSEqualRects(v, NSMakeRect(640, 0, 960, 540)),
         "a primary on the right monitor starts at its own x in the view");
  }

  [arp release];
  return 0;
}
