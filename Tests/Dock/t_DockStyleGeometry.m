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

    PASS(CLOSE(NSMinY(s.shadow), 0) && NSHeight(s.shadow) >= 2
         && CLOSE(NSMinY(s.lip), NSMaxY(s.shadow)),
         "the shelf floats just above the screen edge, its shadow below the lip");
    PASS(CLOSE(NSMinX(s.lip), 0) && CLOSE(NSWidth(s.lip), 640)
         && CLOSE(NSWidth(s.shadow), 640),
         "lip and shadow run across the whole bar");
    PASS(NSMaxY(s.shadow) + NSHeight(s.lip) < 64 / 4,
         "shadow and lip stay low, within the Dock's own thickness");
    PASS(CLOSE(s.frontLeft.y, NSMaxY(s.lip))
         && CLOSE(s.frontRight.y, NSMaxY(s.lip)),
         "the surface starts where the lip ends");
    PASS(s.backLeft.y > s.frontLeft.y + 10,
         "the surface goes back from the lip");
    PASS(s.backLeft.x > s.frontLeft.x && s.backRight.x < s.frontRight.x,
         "the back edge is narrower than the front: the shelf is in perspective");
    PASS(CLOSE(s.backLeft.x - s.frontLeft.x, s.frontRight.x - s.backRight.x),
         "both sides slope alike");
    /* Icons are 48 in a 64 tile, centred and then lifted. */
    {
      CGFloat foot = 8 + DockShelfIconLift(64, 1.0);

      PASS(s.frontLeft.y < foot && s.backLeft.y > foot,
           "the lower edge of a lifted icon lies on the surface: icons stand on the shelf");
      PASS(foot - s.frontLeft.y >= 6,
           "the icons stand far enough back to leave room for a reflection");
      PASS(8 + 48 + DockShelfIconLift(64, 1.0) <= 64
           && 16 + 96 + DockShelfIconLift(128, 1.0) <= 128,
           "a lifted image stays inside its tile, at rest and magnified");
    }
    PASS(s.backLeft.y < 64 / 2,
         "the shelf stays below the middle of the icons");
  }

  /* --- where an icon's image goes --- */
  {
    CGFloat scales[] = { 1.0, 1.5, 2.0 };
    unsigned i;

    for (i = 0; i < sizeof(scales) / sizeof(scales[0]); i++)
      {
        CGFloat sf = scales[i];
        NSRect tile = NSMakeRect(0, 0, 64, 64);
        NSRect bar = NSMakeRect(0, 0, 640, 64);
        DockShelf s = DockShelfMake(bar, sf);
        CGFloat lift = DockShelfIconLift(64, sf);
        NSRect r = DockIconImageRect(tile, 48, lift, sf);
        CGFloat depth = s.backLeft.y - s.frontLeft.y;
        CGFloat behind = (s.backLeft.y - NSMinY(r)) / depth;

        PASS(CLOSE(NSWidth(r), 48) && CLOSE(NSHeight(r), 48),
             "the image fills a square of the icon size at scale %g", sf);
        PASS(CLOSE(NSMidX(r), NSMidX(tile)),
             "the image is centred across its tile at scale %g", sf);
        PASS(onPixel(NSMinX(r), sf) && onPixel(NSMinY(r), sf)
             && onPixel(NSMaxX(r), sf) && onPixel(NSMaxY(r), sf),
             "the image lies on device pixels at scale %g", sf);
        /* On the reference shelf the lower edge of every icon's box lies a
         * little more than half way back on the surface (28 of 48 px). */
        PASS(behind > 0.4 && behind < 0.7,
             "the lower edge of the image stands half way back on the shelf"
             " at scale %g", sf);
        PASS(NSMaxY(r) <= NSMaxY(tile),
             "the lifted image stays inside its tile at scale %g", sf);
      }
  }

  {
    /* Magnified, the tile and the image grow and the lower edge stays on
     * the surface; without a shelf (lift 0) the image is centred. */
    NSRect big = DockIconImageRect(NSMakeRect(10, 0, 128, 128), 96,
                                   DockShelfIconLift(128, 1.0), 1.0);
    NSRect flat = DockIconImageRect(NSMakeRect(0, 0, 64, 64), 48, 0, 1.0);
    NSRect odd = DockIconImageRect(NSMakeRect(0, 0, 65, 65), 48, 0, 1.0);

    PASS(CLOSE(NSMidX(big), 74) && CLOSE(NSMinY(big), 16 + 15),
         "a magnified image is centred in its tile and lifted as far again");
    PASS(NSEqualRects(flat, NSMakeRect(8, 8, 48, 48)),
         "without a shelf the image is centred in its tile");
    PASS(onPixel(NSMinX(odd), 1.0) && onPixel(NSMinY(odd), 1.0)
         && CLOSE(NSWidth(odd), 48),
         "an odd tile still puts the image on whole pixels at its full size");
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

  /* --- reflections --- */
  {
    NSRect image = NSMakeRect(8, 16, 48, 48);
    NSRect r = DockReflectionRect(image, 0, 7);

    PASS(CLOSE(NSMaxY(r), 16) && CLOSE(NSMinX(r), 8) && CLOSE(NSWidth(r), 48),
         "a reflection hangs right below its icon, as wide as it");
    PASS(CLOSE(NSMinY(r), 7),
         "and is cut off at the shelf's front edge");
  }

  {
    /* A magnified icon high above a deep enough surface. */
    NSRect image = NSMakeRect(0, 40, 96, 96);
    NSRect r = DockReflectionRect(image, 0, 0);

    PASS(CLOSE(NSHeight(r), 96 * DOCK_REFLECTION_SHARE),
         "a reflection fades out after a part of its icon's height");
  }

  {
    /* Bouncing 4 points up: the image is drawn at 20 instead of 16. */
    NSRect image = NSMakeRect(8, 20, 48, 48);
    NSRect r = DockReflectionRect(image, 4, 7);

    PASS(CLOSE(NSMaxY(r), 12),
         "a bouncing icon's reflection sinks as far as the icon rises");
  }

  {
    NSRect image = NSMakeRect(8, 6, 48, 48);

    PASS(NSIsEmptyRect(DockReflectionRect(image, 0, 7)),
         "an icon standing in front of the shelf has no reflection on it");
  }

  /* --- running lights --- */
  {
    NSRect lip = NSMakeRect(0, 3, 640, 4);
    DockLipLight l = DockLipLightMake(lip, 100, 1.0);

    PASS(CLOSE(NSMidX(l.core), 100) && CLOSE(NSMidX(l.glow), 100),
         "the light sits under the middle of its icon");
    PASS(NSMinY(l.core) >= NSMinY(lip) && NSMaxY(l.core) <= NSMaxY(lip),
         "its core lies on the lip");
    PASS(NSContainsRect(l.glow, l.core) && NSWidth(l.glow) > NSWidth(l.core),
         "and glows beyond it");
  }

  {
    CGFloat sf = 1.5;
    DockLipLight l = DockLipLightMake(NSMakeRect(0, 3.333, 640, 4), 100.2, sf);

    PASS(onPixel(NSMinX(l.core), sf) && onPixel(NSMaxY(l.core), sf)
         && onPixel(NSMinX(l.glow), sf) && onPixel(NSMinY(l.glow), sf),
         "at GSScaleFactor 1.5 the light lies on device pixels and stays crisp");
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
