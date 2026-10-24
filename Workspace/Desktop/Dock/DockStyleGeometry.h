/* DockStyleGeometry.h
 *
 * The shapes the Dock is drawn with, and where its labels go.
 *
 * 3D at the bottom of the screen is a glass shelf seen in
 * perspective: a front lip along the screen edge and a surface whose back
 * edge is narrower than its front, so that the icons appear to stand on it.
 * 3D at a side, and Modern everywhere, is a flat panel against the
 * screen edge whose corners are rounded only on the sides facing the
 * screen, because the edge side touches the border of the screen.
 *
 * The label of an icon is a rounded box with a small arrow pointing at the
 * icon, put on the side of the icon that faces the middle of the screen and
 * kept on the screen.
 *
 * All of it is Foundation-only inline code, so that it can be tested
 * headless; the Dock draws what these functions describe.  Everything is in
 * points except where a scale is passed: that is the device pixels per
 * point, used to put edges on whole pixels so that thin lines stay sharp at
 * every GSScaleFactor.
 *
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

#ifndef DOCK_STYLE_GEOMETRY_H
#define DOCK_STYLE_GEOMETRY_H

#import <Foundation/Foundation.h>
#include <math.h>

/* The screen edge the Dock sits on.  Its own type rather than DockPosition,
 * whose header pulls in the desktop manager and FSNode. */
typedef enum
{
  DockEdgeLeft,
  DockEdgeRight,
  DockEdgeBottom
} DockEdge;

enum
{
  DockCornerMinXMinY = 1 << 0,
  DockCornerMaxXMinY = 1 << 1,
  DockCornerMaxXMaxY = 1 << 2,
  DockCornerMinXMaxY = 1 << 3
};

/* A coordinate on the nearest device pixel boundary. */
static inline CGFloat
DockPixelAlign(CGFloat v, CGFloat scale)
{
  if (scale <= 0.0)
    scale = 1.0;
  return round(v * scale) / scale;
}

static inline NSRect
DockPixelAlignRect(NSRect r, CGFloat scale)
{
  CGFloat x0 = DockPixelAlign(NSMinX(r), scale);
  CGFloat y0 = DockPixelAlign(NSMinY(r), scale);
  CGFloat x1 = DockPixelAlign(NSMaxX(r), scale);
  CGFloat y1 = DockPixelAlign(NSMaxY(r), scale);

  return NSMakeRect(x0, y0, x1 - x0, y1 - y0);
}

/* ---------------------------------------------------------------------- */
/* The shelf                                                              */
/* ---------------------------------------------------------------------- */

typedef struct
{
  /* The surface, a trapezoid: front corners on the line where the lip
   * ends, back corners further up and pulled in. */
  NSPoint frontLeft;
  NSPoint frontRight;
  NSPoint backRight;
  NSPoint backLeft;
  /* The front face, up to the surface. */
  NSRect lip;
  /* Below the lip, down to the screen edge: where the shelf casts its
   * shadow onto the desktop. */
  NSRect shadow;
} DockShelf;

/* How deep the shelf looks and how thick its lip is, as parts of the
 * Dock's thickness: the icons are two thirds of a tile tall and centred, so
 * a shelf a third of a tile deep reaches over their lower edge and they
 * stand on it rather than float above it. */
#define DOCK_SHELF_DEPTH_SHARE  0.36
#define DOCK_SHELF_LIP_SHARE    0.06
#define DOCK_SHELF_MIN_LIP      4.0
/* The shelf floats this far above the screen edge, the room its shadow
 * falls into.  Within the Dock's own thickness, so the window, its strut
 * and the work area stay what they were, and the bottom row of pixels
 * still belongs to the icons' tiles. */
#define DOCK_SHELF_SHADOW_SHARE 0.05
/* How far each back corner is pulled in for each point of depth: the
 * slope of the shelf's sides. */
#define DOCK_SHELF_SLOPE        0.9

/* The shelf for a bar at the bottom of the screen.  bar is the Dock's bar
 * in the view (its thickness is the tile size, its bottom the screen
 * edge); the shelf grows with it when the magnification spreads it. */
static inline DockShelf
DockShelfMake(NSRect bar, CGFloat scale)
{
  DockShelf s;
  CGFloat thickness = NSHeight(bar);
  CGFloat room = DockPixelAlign(thickness * DOCK_SHELF_SHADOW_SHARE, scale);
  CGFloat bottom = NSMinY(bar) + room;
  CGFloat lip = DockPixelAlign(MAX(DOCK_SHELF_MIN_LIP,
                                   thickness * DOCK_SHELF_LIP_SHARE), scale);
  CGFloat top = DockPixelAlign(bottom
                               + thickness * DOCK_SHELF_DEPTH_SHARE, scale);
  CGFloat front = bottom + lip;
  CGFloat inset = DockPixelAlign((top - front) * DOCK_SHELF_SLOPE, scale);
  CGFloat left = DockPixelAlign(NSMinX(bar), scale);
  CGFloat right = DockPixelAlign(NSMaxX(bar), scale);

  /* A bar shorter than both slopes (a Dock of next to nothing) would make
   * the back edge cross over itself. */
  if (2 * inset > right - left)
    inset = floor((right - left) / 2 * scale) / scale;

  s.shadow = NSMakeRect(left, NSMinY(bar), right - left, room);
  s.lip = NSMakeRect(left, bottom, right - left, lip);
  s.frontLeft = NSMakePoint(left, front);
  s.frontRight = NSMakePoint(right, front);
  s.backRight = NSMakePoint(right - inset, top);
  s.backLeft = NSMakePoint(left + inset, top);
  return s;
}

/* How far forward on the shelf's surface the icons stand: the lower edge
 * of every icon's artwork lies this share of the way from the back edge to
 * the front, as on the reference shelf (28 of its 48 px), which leaves room
 * in front of the icons for their reflections. */
#define DOCK_SHELF_STAND_SHARE 0.58

/* The line the icons stand on, in the shelf's coordinates. */
static inline CGFloat
DockShelfStandLine(DockShelf s, CGFloat scale)
{
  CGFloat depth = s.backLeft.y - s.frontLeft.y;

  return DockPixelAlign(s.backLeft.y - depth * DOCK_SHELF_STAND_SHARE, scale);
}

/* The visible artwork of an icon's image: the box around its pixels that
 * are opaque enough to count (DOCK_ART_ALPHA), as shares of the image, y
 * counted up from the bottom as everywhere in the view. */
typedef struct
{
  CGFloat minX;
  CGFloat minY;
  CGFloat maxX;
  CGFloat maxY;
} DockArtBox;

static inline DockArtBox
DockArtBoxFull(void)
{
  DockArtBox b = { 0.0, 0.0, 1.0, 1.0 };
  return b;
}

/* Alpha at or below this (of 255, 10%) is not artwork.  Icon drop shadows
 * and glows fade out from about a fifth of full alpha into nothing, and
 * their outer half, the part a plain bounding box would add to the
 * artwork, lies below a tenth; measured on the Dock's icons (Trash, home
 * folder, Workspace, Claude), 10% leaves the shadows out and still keeps
 * the anti-aliased edges of the artwork itself (which are lost from 20%
 * up, by a pixel per side). */
#define DOCK_ART_ALPHA 26

/* The visible artwork of an 8-bit bitmap.  rows run top first, as in a
 * bitmap's data; alpha is the index of the alpha sample in a pixel, or -1
 * when there is none.  An image without alpha, or with no artwork at all,
 * is taken as it is. */
static inline DockArtBox
DockArtBoxOfBitmap(const unsigned char *data, NSInteger width,
                   NSInteger height, NSInteger bytesPerRow,
                   NSInteger samplesPerPixel, NSInteger alpha)
{
  NSInteger x, y, x0 = width, x1 = -1, y0 = height, y1 = -1;
  DockArtBox b;

  if (data == NULL || alpha < 0 || width <= 0 || height <= 0)
    return DockArtBoxFull();
  for (y = 0; y < height; y++)
    {
      const unsigned char *row = data + y * bytesPerRow;

      for (x = 0; x < width; x++)
        if (row[x * samplesPerPixel + alpha] > DOCK_ART_ALPHA)
          {
            if (x < x0) x0 = x;
            if (x > x1) x1 = x;
            if (y < y0) y0 = y;
            y1 = y;
          }
    }
  if (x1 < 0)
    return DockArtBoxFull();
  b.minX = (CGFloat)x0 / width;
  b.maxX = (CGFloat)(x1 + 1) / width;
  b.minY = (CGFloat)(height - 1 - y1) / height;
  b.maxY = (CGFloat)(height - y0) / height;
  return b;
}

/* How large the larger side of every icon's artwork is drawn, as a share
 * of the icon's side: that of the full-bleed icons (Books, Brave,
 * AppGarden), which therefore keep their size, so that artwork drawn with
 * margins comes out as large as they are. */
#define DOCK_ART_TARGET 1.0
/* At most this much larger: a small glyph in a large image would come out
 * blurred and out of proportion. */
#define DOCK_ART_MAX_ZOOM 1.35

/* How much larger than the icon's side an image is drawn, so that its
 * artwork's larger side fills DOCK_ART_TARGET of it: wide artwork is
 * limited by its width, tall artwork by its height.  The plain bounding
 * box is enough for tilted artwork too: its corners reach the box, so it
 * reads as full-bleed and keeps its size.  Never smaller. */
static inline CGFloat
DockArtZoom(DockArtBox art)
{
  CGFloat big = MAX(art.maxX - art.minX, art.maxY - art.minY);

  if (big <= 0.0)
    return 1.0;
  return MIN(DOCK_ART_MAX_ZOOM, MAX(1.0, DOCK_ART_TARGET / big));
}

/* Where an icon's image is drawn in its tile: a square of side, enlarged
 * by DockArtZoom so that every icon's artwork has the same size, with the
 * artwork centred across the tile.  On the shelf the artwork's lower edge
 * stands on the stand line, which is the shelf's and not the tile's, so a
 * magnified icon grows upwards and sideways from where it stands; without
 * a shelf (shelf NULL, the flat styles) the artwork is centred in the
 * tile.  It depends on the tile and the artwork only, never on the size
 * the image comes in. */
static inline NSRect
DockIconImageRect(NSRect tile, CGFloat side, DockArtBox art,
                  const DockShelf *shelf, CGFloat scale)
{
  CGFloat size = side * DockArtZoom(art);
  CGFloat x = DockPixelAlign(NSMidX(tile) - (art.minX + art.maxX) / 2 * size,
                             scale);
  CGFloat y;

  if (shelf == NULL)
    return NSMakeRect(x, DockPixelAlign(NSMidY(tile)
                                        - (art.minY + art.maxY) / 2 * size,
                                        scale),
                      size, size);

  y = DockPixelAlign(DockShelfStandLine(*shelf, scale) - art.minY * size,
                     scale);
  /* A tile still growing in is lower than the artwork would stand; the
   * artwork keeps inside it rather than being cut off. */
  if (y + art.maxY * size > NSMaxY(tile))
    y = floor((NSMaxY(tile) - art.maxY * size) * scale) / scale;
  if (y + art.minY * size < NSMinY(tile))
    y = ceil((NSMinY(tile) - art.minY * size) * scale) / scale;
  /* Origin aligned and the size kept, rather than both edges aligned, so
   * that no icon comes out a pixel smaller than its neighbours. */
  return NSMakeRect(x, y, size, size);
}

/* How much of an icon its reflection shows, as a part of the icon's
 * height, before it has faded out. */
#define DOCK_REFLECTION_SHARE 0.35
/* How much of the icon those rows show: more than they are long, since a
 * surface seen at a slant foreshortens what it mirrors. */
#define DOCK_REFLECTION_SOURCE_SHARE 0.5

/* Where an icon's reflection goes: mirrored below the line the icon stands
 * on, as far as the shelf's front edge (front) or the reflection's own
 * length, whichever comes first.  image is where the image is drawn and
 * bounce how far it is lifted off its place (a bouncing icon); a lifted
 * icon's reflection sinks by as much, as in a real mirror. */
static inline NSRect
DockReflectionRect(NSRect image, CGFloat bounce, CGFloat front)
{
  CGFloat axis = NSMinY(image) - bounce;
  CGFloat top = axis - bounce;
  CGFloat length = MIN(NSHeight(image) * DOCK_REFLECTION_SHARE, top - front);

  if (length <= 0.0)
    return NSZeroRect;
  return NSMakeRect(NSMinX(image), top - length, NSWidth(image), length);
}

/* The light of a running application on the shelf's front lip: a small
 * bright core and the glow around it, centred under the icon (x) and on
 * the lip, both on whole device pixels. */
typedef struct
{
  NSRect core;
  NSRect glow;
} DockLipLight;

static inline DockLipLight
DockLipLightMake(NSRect lip, CGFloat x, CGFloat scale)
{
  DockLipLight l;
  CGFloat mid = NSMidY(lip);
  CGFloat coreW = MAX(4.0, NSHeight(lip) * 1.5);
  CGFloat coreH = MAX(1.0 / scale, NSHeight(lip) * 0.35);
  CGFloat glowW = coreW * 3.0;
  CGFloat glowH = NSHeight(lip) * 1.6;

  l.core = DockPixelAlignRect(NSMakeRect(x - coreW / 2, mid - coreH / 2,
                                         coreW, coreH), scale);
  l.glow = DockPixelAlignRect(NSMakeRect(x - glowW / 2, mid - glowH / 2,
                                         glowW, glowH), scale);
  return l;
}

/* The left end of the surface at height y, so that a divider drawn across
 * the shelf can follow its perspective. */
static inline CGFloat
DockShelfInsetAtHeight(DockShelf s, CGFloat y)
{
  CGFloat depth = s.backLeft.y - s.frontLeft.y;

  if (depth <= 0.0)
    return 0.0;
  y = MAX(s.frontLeft.y, MIN(y, s.backLeft.y));
  return (s.backLeft.x - s.frontLeft.x) * (y - s.frontLeft.y) / depth;
}

/* ---------------------------------------------------------------------- */
/* The flat panel                                                         */
/* ---------------------------------------------------------------------- */

typedef struct
{
  NSRect rect;
  /* The border, half a device pixel inside rect so that a line one pixel
   * wide covers exactly one row of pixels. */
  NSRect borderRect;
  unsigned corners;
  CGFloat radius;
} DockPanel;

/* The corners facing the screen: the top ones at the bottom of the screen,
 * the inner ones at a side. */
static inline unsigned
DockPanelCornersForEdge(DockEdge edge)
{
  switch (edge)
    {
      case DockEdgeLeft:
        return DockCornerMaxXMinY | DockCornerMaxXMaxY;
      case DockEdgeRight:
        return DockCornerMinXMinY | DockCornerMinXMaxY;
      case DockEdgeBottom:
      default:
        return DockCornerMinXMaxY | DockCornerMaxXMaxY;
    }
}

static inline DockPanel
DockPanelMake(NSRect bar, DockEdge edge, CGFloat radius, CGFloat scale)
{
  DockPanel p;
  CGFloat half = (scale > 0.0) ? 0.5 / scale : 0.5;

  p.rect = DockPixelAlignRect(bar, scale);
  p.borderRect = NSInsetRect(p.rect, half, half);
  p.corners = DockPanelCornersForEdge(edge);
  /* Never more than half the shorter side, or the two rounded corners of
   * one side would overlap. */
  p.radius = MAX(0.0, MIN(radius, MIN(NSWidth(p.borderRect),
                                      NSHeight(p.borderRect)) / 2));
  return p;
}

/* ---------------------------------------------------------------------- */
/* The label                                                              */
/* ---------------------------------------------------------------------- */

typedef struct
{
  /* The label's window, in the units of the screen passed in. */
  NSRect frame;
  /* The rounded box, inside frame (frame's origin is its zero). */
  NSRect body;
  /* The point of the arrow, on the side of frame facing the icon, and the
   * middle of its base on the body's edge. */
  NSPoint tip;
  NSPoint base;
} DockLabelLayout;

/* textSize is the size of the box (text plus padding), gap the room
 * between the icon and the tip of the arrow, arrow the arrow's length,
 * margin the distance kept from the screen edges.  The box is kept on
 * screen; the arrow keeps pointing at the icon as far as the box's rounded
 * corners (radius) allow. */
static inline DockLabelLayout
DockLabelPlace(NSRect icon, NSSize textSize, DockEdge edge, NSRect screen,
               CGFloat gap, CGFloat arrow, CGFloat radius, CGFloat margin)
{
  DockLabelLayout l;
  CGFloat w = MIN(textSize.width, NSWidth(screen) - 2 * margin);
  CGFloat h = textSize.height;
  CGFloat halfBase = arrow;
  CGFloat x, y, lo, hi;

  if (edge == DockEdgeBottom)
    {
      x = NSMidX(icon) - w / 2;
      x = MAX(NSMinX(screen) + margin, MIN(x, NSMaxX(screen) - margin - w));
      y = NSMaxY(icon) + gap;
      l.frame = NSMakeRect(x, y, w, h + arrow);
      l.body = NSMakeRect(0, arrow, w, h);
      lo = radius + halfBase;
      hi = w - radius - halfBase;
      l.tip.x = MAX(lo, MIN(NSMidX(icon) - x, hi));
      l.tip.y = 0;
      l.base = NSMakePoint(l.tip.x, arrow);
    }
  else
    {
      y = NSMidY(icon) - h / 2;
      y = MAX(NSMinY(screen) + margin, MIN(y, NSMaxY(screen) - margin - h));
      w = MIN(w, NSWidth(screen) - 2 * margin - NSWidth(icon) - gap - arrow);
      if (edge == DockEdgeLeft)
        {
          x = NSMaxX(icon) + gap;
          l.frame = NSMakeRect(x, y, w + arrow, h);
          l.body = NSMakeRect(arrow, 0, w, h);
          l.tip.x = 0;
          l.base.x = arrow;
        }
      else
        {
          x = NSMinX(icon) - gap - arrow - w;
          l.frame = NSMakeRect(x, y, w + arrow, h);
          l.body = NSMakeRect(0, 0, w, h);
          l.tip.x = w + arrow;
          l.base.x = w;
        }
      lo = radius + halfBase;
      hi = h - radius - halfBase;
      l.tip.y = MAX(lo, MIN(NSMidY(icon) - y, hi));
      l.base.y = l.tip.y;
    }

  return l;
}

#endif /* DOCK_STYLE_GEOMETRY_H */
