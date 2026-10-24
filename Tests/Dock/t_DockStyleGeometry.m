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
    /* Icons are 48 in a 64 tile. */
    {
      CGFloat stand = DockShelfStandLine(s, 1.0);

      PASS(s.frontLeft.y < stand && s.backLeft.y > stand,
           "the stand line lies on the surface: icons stand on the shelf");
      PASS(stand - s.frontLeft.y >= 6,
           "the icons stand far enough back to leave room for a reflection");
    }
    PASS(s.backLeft.y < 64 / 2,
         "the shelf stays below the middle of the icons");
  }

  /* --- where an icon's image goes --- */
  {
    CGFloat scales[] = { 1.0, 1.2, 1.25, 1.5, 2.0 };
    /* Magnified tiles, as the Dock lays them out: the tile grows to size,
     * the image to three quarters of it, and the bar keeps its thickness. */
    CGFloat sizes[] = { 64, 70.4, 80, 96.5, 112, 128 };
    /* Artwork that leaves an eighth of the image free on every side. */
    DockArtBox framed = { 0.125, 0.125, 0.875, 0.875 };
    unsigned i, j;

    for (i = 0; i < sizeof(scales) / sizeof(scales[0]); i++)
      {
        CGFloat sf = scales[i];
        NSRect bar = NSMakeRect(0, 0, 640, 64);
        DockShelf s = DockShelfMake(bar, sf);
        CGFloat depth = s.backLeft.y - s.frontLeft.y;
        CGFloat stand = DockShelfStandLine(s, sf);
        NSRect rest = DockIconImageRect(NSMakeRect(0, 0, 64, 64), 48,
                                        DockArtBoxFull(), &s, sf);
        NSRect restFramed = DockIconImageRect(NSMakeRect(0, 0, 64, 64), 48,
                                              framed, &s, sf);
        BOOL square = YES, centred = YES, aligned = YES, inside = YES;
        BOOL still = YES, footed = YES, grown = YES, stillFramed = YES;

        /* On the reference shelf the lower edge of every icon lies 28 of
         * the surface's 48 px behind its back edge. */
        PASS(fabs((s.backLeft.y - stand) / depth - DOCK_SHELF_STAND_SHARE)
             <= 0.5 / sf / depth,
             "icons stand %g of the way forward on the shelf at scale %g",
             DOCK_SHELF_STAND_SHARE, sf);
        PASS(CLOSE(NSMinY(rest), stand),
             "a resting image's lower edge is on the stand line at scale %g",
             sf);

        for (j = 0; j < sizeof(sizes) / sizeof(sizes[0]); j++)
          {
            CGFloat size = sizes[j];
            CGFloat side = 48 * size / 64;
            NSRect tile = NSMakeRect(100, 0, size, size);
            NSRect r = DockIconImageRect(tile, side, DockArtBoxFull(), &s, sf);
            NSRect f = DockIconImageRect(tile, side, framed, &s, sf);
            CGFloat k = DockArtZoom(framed);
            CGFloat artBottom = NSMinY(f) + framed.minY * NSHeight(f);
            CGFloat artMidX = NSMinX(f) + (framed.minX + framed.maxX) / 2
                              * NSWidth(f);

            square = square && CLOSE(NSWidth(r), side)
                     && CLOSE(NSHeight(r), side);
            centred = centred
                      && fabs(NSMidX(r) - NSMidX(tile)) <= 0.5 / sf + 0.001
                      && fabs(artMidX - NSMidX(tile)) <= 0.5 / sf + 0.001;
            aligned = aligned && onPixel(NSMinX(r), sf)
                      && onPixel(NSMinY(r), sf) && onPixel(artBottom, sf);
            inside = inside && NSMaxY(r) <= NSMaxY(tile) + 0.001
                     && NSMinY(f) + framed.maxY * NSHeight(f)
                        <= NSMaxY(tile) + 0.001;
            still = still && CLOSE(NSMinY(r), NSMinY(rest));
            stillFramed = stillFramed
                          && CLOSE(artBottom, NSMinY(restFramed) + framed.minY
                                              * NSHeight(restFramed));
            footed = footed && CLOSE(artBottom, stand);
            grown = grown && CLOSE(NSWidth(f), side * k)
                    && CLOSE(NSHeight(f), side * k);
          }
        PASS(square, "full-bleed artwork fills a square of the icon's side"
             " at scale %g", sf);
        PASS(centred, "the artwork is centred across its tile at scale %g",
             sf);
        PASS(aligned, "the image and the lower edge of its artwork lie on device pixels at scale %g", sf);
        PASS(inside, "the artwork stays inside its tile at scale %g", sf);
        PASS(still && stillFramed,
             "magnified, the lower edge stays where it rests: icons grow"
             " upwards and sideways only, at scale %g", sf);
        PASS(footed,
             "the artwork, not the transparent rows below it, stands on the"
             " line at scale %g", sf);
        PASS(grown, "artwork with margins is drawn larger, by its zoom, at"
             " scale %g", sf);
      }
  }

  /* --- how much artwork with margins is enlarged --- */
  {
    DockArtBox full = DockArtBoxFull();
    DockArtBox claude = { 5.0 / 58, 5.0 / 58, 53.0 / 58, 53.0 / 58 };
    DockArtBox glyph = { 0.35, 0.35, 0.65, 0.65 };
    DockArtBox wide = { 0.0, 0.25, 1.0, 0.75 };   /* a folder */
    DockArtBox tall = { 0.3, 0.02, 0.7, 0.92 };   /* a microphone */

    PASS(CLOSE(DockArtZoom(full), 1.0),
         "full-bleed artwork keeps its size");
    PASS(fabs(DockArtZoom(claude) * (48.0 / 58) - DOCK_ART_TARGET) < 0.001,
         "artwork with margins grows until its larger side fills the target");
    PASS(CLOSE(DockArtZoom(glyph), DOCK_ART_MAX_ZOOM),
         "a small glyph in a large image grows no more than the cap");
    PASS(CLOSE(DockArtZoom(wide), 1.0),
         "wide artwork that fills the width is limited by it, not enlarged");
    PASS(fabs(DockArtZoom(tall) * 0.9 - DOCK_ART_TARGET) < 0.001,
         "tall artwork is limited by its height");
    PASS(DockArtZoom((DockArtBox){ 0, 0, 1.2, 1.0 }) >= 1.0,
         "artwork is never made smaller");
  }

  {
    DockArtBox framed = { 0.125, 0.25, 0.875, 0.75 };
    NSRect flat = DockIconImageRect(NSMakeRect(0, 0, 64, 64), 48,
                                    DockArtBoxFull(), NULL, 1.0);
    NSRect flatFramed = DockIconImageRect(NSMakeRect(0, 0, 64, 64), 48,
                                          framed, NULL, 1.0);
    NSRect odd = DockIconImageRect(NSMakeRect(0, 0, 65, 65), 48,
                                   DockArtBoxFull(), NULL, 1.0);
    DockShelf s = DockShelfMake(NSMakeRect(0, 0, 640, 64), 1.0);
    /* A tile that is still growing in (a new icon) is smaller than the
     * image would stand: the artwork keeps inside it. */
    NSRect small = DockIconImageRect(NSMakeRect(0, 0, 32, 32), 24,
                                     DockArtBoxFull(), &s, 1.0);
    CGFloat midY = NSMinY(flatFramed) + (framed.minY + framed.maxY) / 2
                   * NSHeight(flatFramed);

    PASS(NSEqualRects(flat, NSMakeRect(8, 8, 48, 48)),
         "without a shelf full-bleed artwork is centred in its tile");
    PASS(fabs(midY - 32) <= 0.5,
         "without a shelf the artwork, not the image, is centred");
    PASS(onPixel(NSMinX(odd), 1.0) && onPixel(NSMinY(odd), 1.0)
         && CLOSE(NSWidth(odd), 48),
         "an odd tile still puts the image on whole pixels at its full size");
    PASS(NSMaxY(small) <= 32 && NSMinY(small) >= 0,
         "an image in a tile still growing in stays inside it");
  }

  /* --- a badge on the artwork (the link arrow) --- */
  {
    CGFloat scales[] = { 1.0, 1.2, 2.0 };
    /* A folder: full width, an eighth free above and below. */
    DockArtBox folder = { 0.0, 0.125, 1.0, 0.875 };
    unsigned i;

    for (i = 0; i < sizeof(scales) / sizeof(scales[0]); i++)
      {
        CGFloat sf = scales[i];
        DockShelf s = DockShelfMake(NSMakeRect(0, 0, 640, 64), sf);
        CGFloat sides[] = { 48, 72, 96 };
        unsigned j;
        BOOL corner = YES, sized = YES, aligned = YES;

        for (j = 0; j < 3; j++)
          {
            CGFloat side = sides[j];
            NSRect tile = NSMakeRect(0, 0, side * 4 / 3, side * 4 / 3);
            NSRect image = DockIconImageRect(tile, side, folder, &s, sf);
            NSRect b = DockBadgeRect(image, folder, NSMakeSize(16, 16), side,
                                     sf);

            corner = corner
                     && fabs(NSMinX(b) - (NSMinX(image) + folder.minX
                                          * NSWidth(image))) <= 0.5 / sf
                     && fabs(NSMinY(b) - (NSMinY(image) + folder.minY
                                          * NSHeight(image))) <= 0.5 / sf;
            sized = sized && fabs(NSWidth(b) - 16 * side / 48) <= 1.0 / sf
                    && fabs(NSHeight(b) - 16 * side / 48) <= 1.0 / sf;
            aligned = aligned && onPixel(NSMinX(b), sf) && onPixel(NSMinY(b), sf)
                      && onPixel(NSMaxX(b), sf) && onPixel(NSMaxY(b), sf);
          }
        PASS(corner, "the link arrow sits on the artwork's lower left corner,"
             " not the image's, at scale %g", sf);
        PASS(sized, "the arrow keeps its share of the icon, a third of a 48"
             " point icon, at scale %g", sf);
        PASS(aligned, "the arrow lies on device pixels at scale %g", sf);
      }
  }

  /* --- the visible artwork of a bitmap --- */
  {
    /* 10 x 10 RGBA, rows top first as in a bitmap: artwork in columns 2-7
     * of rows 1-6, a drop shadow (alpha 20) below and right of it, and a
     * pixel at exactly the threshold, which is not artwork either. */
    unsigned char px[10][10][4];
    unsigned char grey[10][10];
    DockArtBox b;
    int x, y;

    memset(px, 0, sizeof(px));
    memset(grey, 255, sizeof(grey));
    for (y = 1; y <= 6; y++)
      for (x = 2; x <= 7; x++)
        px[y][x][3] = 255;
    for (x = 3; x <= 8; x++)
      px[7][x][3] = 20;
    for (y = 2; y <= 7; y++)
      px[y][8][3] = 20;
    px[9][0][3] = DOCK_ART_ALPHA;

    b = DockArtBoxOfBitmap(&px[0][0][0], 10, 10, 40, 4, 3);
    PASS(CLOSE(b.minX, 0.2) && CLOSE(b.maxX, 0.8),
         "the artwork's columns, not its shadow's");
    PASS(CLOSE(b.minY, 0.3) && CLOSE(b.maxY, 0.9),
         "the artwork's rows, counted up from the bottom, not its shadow's");
    px[9][0][3] = DOCK_ART_ALPHA + 1;
    b = DockArtBoxOfBitmap(&px[0][0][0], 10, 10, 40, 4, 3);
    PASS(CLOSE(b.minX, 0.0) && CLOSE(b.minY, 0.0),
         "a pixel above the threshold counts");
    b = DockArtBoxOfBitmap(&grey[0][0], 10, 10, 10, 1, -1);
    PASS(CLOSE(b.minX, 0) && CLOSE(b.minY, 0) && CLOSE(b.maxX, 1)
         && CLOSE(b.maxY, 1),
         "an image without alpha is artwork all over");
    memset(px, 0, sizeof(px));
    b = DockArtBoxOfBitmap(&px[0][0][0], 10, 10, 40, 4, 3);
    PASS(CLOSE(b.minX, 0) && CLOSE(b.maxY, 1),
         "an image with nothing in it is left as it is");
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
