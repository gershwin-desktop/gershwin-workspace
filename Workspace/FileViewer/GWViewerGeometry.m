/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 */

#import "GWViewerGeometry.h"

const int GWViewerBrowserInitialColumns = 3;

NSSize
GWViewerResizeIncrements(GWViewType type, int legacyIncrement)
{
  /* The column view's columns are FSNColumnViewOptions' 205 points (or
   * what Option-drag made them), not the configured width; stepping the
   * window by that width only cut a column short [E33]. */
  if (type == GWViewTypeBrowser)
    return NSMakeSize(1, 1);
  return NSMakeSize(legacyIncrement, 1);
}

GWViewerBoxLayout
GWViewerBoxLayoutForSize(NSSize size, BOOL showsPathBar, CGFloat pathBarHeight,
                         BOOL showsInspector, CGFloat inspectorWidth)
{
  GWViewerBoxLayout l;
  CGFloat barH = showsPathBar ? pathBarHeight : 0;
  CGFloat inspW = showsInspector ? inspectorWidth : 0;
  CGFloat contentH = size.height - barH;

  if (contentH < 0)
    contentH = 0;
  if (inspW > size.width)
    inspW = size.width;

  l.pathBar = showsPathBar ? NSMakeRect(0, 0, size.width, barH) : NSZeroRect;
  l.content = NSMakeRect(0, barH, size.width - inspW, contentH);
  l.inspector = showsInspector
    ? NSMakeRect(size.width - inspW, barH, inspW, contentH) : NSZeroRect;
  return l;
}
