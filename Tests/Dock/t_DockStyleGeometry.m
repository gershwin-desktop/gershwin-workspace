/* t_DockStyleGeometry.m - headless coverage for the shapes of the Dock's
 * styles: the 3D glass shelf at the bottom of the screen and the flat
 * panel used at the sides and by Modern.
 *
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

#import <Foundation/Foundation.h>
#import "Testing.h"
#import "DockStyleGeometry.h"

#define CLOSE(a, b) (fabs((a) - (b)) < 0.001)

/* Whether v lies on the device pixel grid of the scale. */
static BOOL
onPixel(CGFloat v, CGFloat scale)
{
  CGFloat px = v * scale;
  return fabs(px - round(px)) < 0.001;
}

int
main(void)
{
  NSAutoreleasePool *arp = [NSAutoreleasePool new];

  /* --- the shelf --- */
  {
    NSRect bar = NSMakeRect(0, 0, 640, 64);
    DockShelf s = DockShelfMake(bar, 1.0);

    PASS(CLOSE(s.lip.origin.y, 0) && CLOSE(NSMinX(s.lip), 0)
         && CLOSE(NSWidth(s.lip), 640),
         "the lip runs along the screen edge across the whole bar");
    PASS(CLOSE(s.frontLeft.y, NSMaxY(s.lip))
         && CLOSE(s.frontRight.y, NSMaxY(s.lip)),
         "the surface starts where the lip ends");
    PASS(s.backLeft.y > s.frontLeft.y + 10,
         "the surface goes back from the lip");
    PASS(s.backLeft.x > s.frontLeft.x && s.backRight.x < s.frontRight.x,
         "the back edge is narrower than the front: the shelf is in perspective");
    PASS(CLOSE(s.backLeft.x - s.frontLeft.x, s.frontRight.x - s.backRight.x),
         "both sides slope alike");
    /* Icons are 48 in a 64 tile and centred, so their lower edge is at 8. */
    PASS(s.frontLeft.y < 8 && s.backLeft.y > 8,
         "the lower edge of a centred icon lies on the surface: icons stand on the shelf");
    PASS(s.backLeft.y < 64 / 2,
         "the shelf stays below the middle of the icons");
  }

  {
    /* Armed, the bar starts further in and is longer; the shelf follows it. */
    NSRect bar = NSMakeRect(120, 0, 900, 64);
    DockShelf s = DockShelfMake(bar, 1.0);

    PASS(CLOSE(s.frontLeft.x, 120) && CLOSE(s.frontRight.x, 1020),
         "the shelf spans a bar that the magnification moved and spread");
  }

  {
    /* A scale factor that puts fractional points on whole pixels. */
    CGFloat sf = 1.5;
    NSRect bar = NSMakeRect(10.3, 0, 400.2, 64);
    DockShelf s = DockShelfMake(bar, sf);

    PASS(onPixel(s.frontLeft.x, sf) && onPixel(s.frontRight.x, sf)
         && onPixel(s.backLeft.x, sf) && onPixel(s.backRight.x, sf)
         && onPixel(s.frontLeft.y, sf) && onPixel(s.backLeft.y, sf),
         "at GSScaleFactor 1.5 every shelf corner lies on a device pixel");
  }

  {
    /* A bar shorter than the two slopes. */
    NSRect bar = NSMakeRect(0, 0, 20, 64);
    DockShelf s = DockShelfMake(bar, 1.0);

    PASS(s.backLeft.x <= s.backRight.x,
         "a very short bar never makes the back edge cross over itself");
  }

  {
    DockShelf s = DockShelfMake(NSMakeRect(0, 0, 640, 64), 1.0);
    CGFloat full = s.backLeft.x - s.frontLeft.x;

    PASS(CLOSE(DockShelfInsetAtHeight(s, s.frontLeft.y), 0)
         && CLOSE(DockShelfInsetAtHeight(s, s.backLeft.y), full)
         && CLOSE(DockShelfInsetAtHeight(s, (s.frontLeft.y + s.backLeft.y) / 2),
                  full / 2),
         "the side of the shelf is a straight line from front to back");
  }

  /* --- the panel --- */
  {
    PASS(DockPanelCornersForEdge(DockEdgeBottom)
         == (DockCornerMinXMaxY | DockCornerMaxXMaxY),
         "at the bottom only the top corners are rounded");
    PASS(DockPanelCornersForEdge(DockEdgeLeft)
         == (DockCornerMaxXMinY | DockCornerMaxXMaxY),
         "at the left only the inner, right corners are rounded");
    PASS(DockPanelCornersForEdge(DockEdgeRight)
         == (DockCornerMinXMinY | DockCornerMinXMaxY),
         "at the right only the inner, left corners are rounded");
  }

  {
    DockPanel p = DockPanelMake(NSMakeRect(0, 0, 640, 64), DockEdgeBottom,
                                6.0, 1.0);

    PASS(NSEqualRects(p.rect, NSMakeRect(0, 0, 640, 64)),
         "the panel covers the bar");
    PASS(CLOSE(NSMinX(p.borderRect), 0.5) && CLOSE(NSMaxY(p.borderRect), 63.5),
         "the border runs half a pixel inside, so a one pixel line stays sharp");
    PASS(CLOSE(p.radius, 6.0), "the radius asked for is kept");
  }

  {
    DockPanel p = DockPanelMake(NSMakeRect(0, 0, 640, 64), DockEdgeBottom,
                                6.0, 2.0);

    PASS(CLOSE(NSMinX(p.borderRect), 0.25),
         "at scale 2 the border is half a device pixel, a quarter point, inside");
  }

  {
    DockPanel p = DockPanelMake(NSMakeRect(0, 0, 8, 64), DockEdgeLeft,
                                6.0, 1.0);

    PASS(p.radius <= NSWidth(p.borderRect) / 2,
         "a narrow panel never gets corners wider than half of it");
  }

  {
    CGFloat sf = 1.5;
    DockPanel p = DockPanelMake(NSMakeRect(0, 100.2, 64, 300.3), DockEdgeRight,
                                6.0, sf);

    PASS(onPixel(NSMinY(p.rect), sf) && onPixel(NSMaxY(p.rect), sf),
         "at GSScaleFactor 1.5 the panel's edges lie on device pixels");
  }

  [arp release];
  return 0;
}
