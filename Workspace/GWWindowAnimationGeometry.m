/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

#import "GWWindowAnimationGeometry.h"

NSRect GWX11RootRectForScreenRect(NSRect screenRect, CGFloat rootHeight)
{
  /* Round each edge, not origin and size apart: at a fractional scale the
     icon starts and ends between pixels, and truncating both would shift
     the rect by up to a pixel and shrink it by another. */
  CGFloat minX = round (NSMinX (screenRect));
  CGFloat maxX = round (NSMaxX (screenRect));
  CGFloat minY = round (rootHeight - NSMaxY (screenRect));
  CGFloat maxY = round (rootHeight - NSMinY (screenRect));

  return NSMakeRect (minX, minY, maxX - minX, maxY - minY);
}
