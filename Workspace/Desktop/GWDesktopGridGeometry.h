/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-2.0-or-later
 */

/* GWDesktopGridGeometry.h - where the desktop icon grid goes, as pure
 * geometry shared by GWDesktopView.m and its headless test.  All rects are
 * in the desktop view's own coordinates (points, origin bottom-left). */

#ifndef GW_DESKTOP_GRID_GEOMETRY_H
#define GW_DESKTOP_GRID_GEOMETRY_H

#import <Foundation/Foundation.h>
#import "DockPosition.h"

/* The primary monitor in the desktop view's coordinates.  primaryFrame is
 * in GNUstep screen coordinates (device pixels, as -[NSScreen frame]);
 * viewOrigin is where the view starts, in points; the view's coordinates
 * are the screen's divided by GSScaleFactor. */
static inline NSRect GWDesktopPrimaryViewRect(NSRect primaryFrame,
                                              NSPoint viewOrigin,
                                              CGFloat scale)
{
  if (scale <= 0)
    scale = 1.0;
  return NSMakeRect(primaryFrame.origin.x / scale - viewOrigin.x,
                    primaryFrame.origin.y / scale - viewOrigin.y,
                    primaryFrame.size.width / scale,
                    primaryFrame.size.height / scale);
}

/* The area icons may use: the primary monitor (primaryRect) minus the menu
 * bar strip at its top, the margins, and the side the Dock takes.  The
 * desktop view spans every monitor for the background, but the icons stay
 * on the primary with the menu bar and the Dock. */
static inline NSRect GWDesktopIconGridRect(NSRect primaryRect,
                                           CGFloat menuHeight,
                                           DockPosition dockPosition,
                                           NSSize dockSize,
                                           CGFloat topMargin,
                                           CGFloat bottomMargin)
{
  NSRect gridrect = primaryRect;

  gridrect.size.height -= menuHeight;
  gridrect.origin.y += bottomMargin;
  gridrect.size.height -= (topMargin + bottomMargin);

  if (dockPosition == DockPositionLeft)
    {
      gridrect.size.width -= dockSize.width;
      gridrect.origin.x += dockSize.width;
    }
  else if (dockPosition == DockPositionRight)
    {
      gridrect.size.width -= dockSize.width;
    }
  else if (dockPosition == DockPositionBottom)
    {
      gridrect.origin.y += dockSize.height;
      gridrect.size.height -= dockSize.height;
    }

  return gridrect;
}

/* Left edge of the right-aligned grid: as many whole columns as fit in
 * gridrect, the rightmost keeping half a gap from its right edge, the
 * leftover space on the left. */
static inline CGFloat GWDesktopGridOriginX(NSRect gridrect, CGFloat cellW,
                                           CGFloat gapX)
{
  NSUInteger nCols = (NSUInteger)(gridrect.size.width / (cellW + gapX));
  CGFloat totalWidth;

  if (nCols < 1)
    nCols = 1;
  totalWidth = nCols * (cellW + gapX) - gapX;
  return NSMaxX(gridrect) - gapX / 2.0 - totalWidth;
}

#endif
