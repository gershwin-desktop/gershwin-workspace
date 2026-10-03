/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

#import "GWTrashFlightPath.h"
#include <math.h>

/* Chosen so the arc reads as deliberate on screen without ever looking like
 * it overshoots off toward the icon it passes near; 0.75 of this fraction is
 * exactly how far the cubic's own midpoint sits off the straight line (see
 * the derivation in the class comment below), which is the number a test
 * can check against without re-deriving the Bezier algebra. */
const CGFloat GWTrashFlightBowFraction = 0.30;

CGFloat
GWTrashFlightEaseInOut(CGFloat t)
{
  /* Smoothstep: t^2*(3-2t).  Symmetric about (0.5, 0.5) by construction -
   * ease(1-t) = (1-t)^2*(3-2*(1-t)) = (1-t)^2*(1+2t), and expanding both
   * sides shows this equals 1 - ease(t) for every t, so an ease-in and the
   * matching ease-out take visually identical shapes. */
  if (t <= 0.0)
    return 0.0;
  if (t >= 1.0)
    return 1.0;

  return t * t * (3.0 - 2.0 * t);
}

NSRect
GWTrashFlightRectAtTime(NSRect startRect, NSRect endRect, CGFloat t)
{
  CGFloat et;
  NSPoint p0, p3, pos;
  NSSize size;
  NSRect result;
  CGFloat dx, dy, len;

  if (t <= 0.0)
    return startRect;
  if (t >= 1.0)
    return endRect;

  et = GWTrashFlightEaseInOut(t);

  p0 = NSMakePoint(NSMidX(startRect), NSMidY(startRect));
  p3 = NSMakePoint(NSMidX(endRect), NSMidY(endRect));

  dx = p3.x - p0.x;
  dy = p3.y - p0.y;
  len = sqrt(dx * dx + dy * dy);

  if (len < 1.0e-6)
    {
      /* Start and end coincide: there is no line to bow away from, so the
       * icon just shrinks in place rather than travelling anywhere. */
      pos = p0;
    }
  else
    {
      /* Unit direction along the straight line, and its perpendicular -
       * rotated 90 degrees rather than picked by the path's own slope, so
       * one formula covers every path angle without a case split (see the
       * header comment for why this reads as "upward, sideways for a
       * near-vertical path" on its own). */
      NSPoint d = NSMakePoint(dx / len, dy / len);
      NSPoint n = NSMakePoint(-d.y, d.x);
      CGFloat bow = GWTrashFlightBowFraction * len;
      NSPoint c1, c2;
      CGFloat mt, b0, b1, b2, b3;

      if (n.y < 0.0)
        {
          n.x = -n.x;
          n.y = -n.y;
        }

      /* Two control points at the thirds of the line, both pushed out by
       * the same bow offset: the classic construction for a cubic that
       * bulges away from its chord without changing where it starts or
       * ends. */
      c1 = NSMakePoint(p0.x + d.x * (len / 3.0) + n.x * bow,
                        p0.y + d.y * (len / 3.0) + n.y * bow);
      c2 = NSMakePoint(p0.x + d.x * (len * 2.0 / 3.0) + n.x * bow,
                        p0.y + d.y * (len * 2.0 / 3.0) + n.y * bow);

      mt = 1.0 - et;
      b0 = mt * mt * mt;
      b1 = 3.0 * mt * mt * et;
      b2 = 3.0 * mt * et * et;
      b3 = et * et * et;

      pos.x = b0 * p0.x + b1 * c1.x + b2 * c2.x + b3 * p3.x;
      pos.y = b0 * p0.y + b1 * c1.y + b2 * c2.y + b3 * p3.y;
    }

  size.width = startRect.size.width
    + (endRect.size.width - startRect.size.width) * et;
  size.height = startRect.size.height
    + (endRect.size.height - startRect.size.height) * et;

  result.origin.x = pos.x - size.width / 2.0;
  result.origin.y = pos.y - size.height / 2.0;
  result.size = size;

  return result;
}
