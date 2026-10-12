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
  /* The front face, from the screen edge up to the surface. */
  NSRect lip;
} DockShelf;

/* How deep the shelf looks and how thick its lip is, as parts of the
 * Dock's thickness: the icons are two thirds of a tile tall and centred, so
 * a shelf a third of a tile deep reaches over their lower edge and they
 * stand on it rather than float above it. */
#define DOCK_SHELF_DEPTH_SHARE  0.36
#define DOCK_SHELF_LIP_SHARE    0.08
#define DOCK_SHELF_MIN_LIP      4.0
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
  CGFloat lip = DockPixelAlign(MAX(DOCK_SHELF_MIN_LIP,
                                   thickness * DOCK_SHELF_LIP_SHARE), scale);
  CGFloat top = DockPixelAlign(NSMinY(bar)
                               + thickness * DOCK_SHELF_DEPTH_SHARE, scale);
  CGFloat front = NSMinY(bar) + lip;
  CGFloat inset = DockPixelAlign((top - front) * DOCK_SHELF_SLOPE, scale);
  CGFloat left = DockPixelAlign(NSMinX(bar), scale);
  CGFloat right = DockPixelAlign(NSMaxX(bar), scale);

  /* A bar shorter than both slopes (a Dock of next to nothing) would make
   * the back edge cross over itself. */
  if (2 * inset > right - left)
    inset = floor((right - left) / 2 * scale) / scale;

  s.lip = NSMakeRect(left, NSMinY(bar), right - left, lip);
  s.frontLeft = NSMakePoint(left, front);
  s.frontRight = NSMakePoint(right, front);
  s.backRight = NSMakePoint(right - inset, top);
  s.backLeft = NSMakePoint(left + inset, top);
  return s;
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
