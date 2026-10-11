/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

#include <math.h>
#import "GWLookInsideGeometry.h"

/* Whatever unit convention the caller's visible frame already uses (plain
 * points at GSScaleFactor 1.0, or the larger device-pixel numbers a higher
 * factor already bakes into NSScreen's own frame - see the
 * gnustep-scale-factor-pitfalls skill), this is a flat fraction of it, so
 * it never needs to multiply by the scale factor itself: it just centers
 * an 80%-sized rect inside whatever rect it is given. */
NSRect
GWLookInsideFrameForVisibleFrame(NSRect visibleFrame)
{
  CGFloat w = floor(visibleFrame.size.width * 0.8);
  CGFloat h = floor(visibleFrame.size.height * 0.8);
  CGFloat x = visibleFrame.origin.x + floor((visibleFrame.size.width - w) / 2.0);
  CGFloat y = visibleFrame.origin.y + floor((visibleFrame.size.height - h) / 2.0);

  return NSMakeRect(x, y, w, h);
}

/* Only the SIZE divides by the scale factor; the ORIGIN is left in screen
 * pixels.  This mirrors Workspace/GWFunctions.m's frameRectForScreenContentRect()
 * exactly (its own comment: "-frameRectForContentRect: takes the size in
 * points and multiplies it by GSScaleFactor" - a size already in pixels
 * would grow a second time; the origin is never touched by either
 * function).  frameRectForScreenContentRect() itself needs a live NSWindow
 * (to read -userSpaceScaleFactor and call -frameRectForContentRect:), so
 * is not headless-testable; this is the plain-arithmetic half of that
 * same contract, pulled out so it is. */
NSRect
GWLookInsideContentRectForVisibleFrame(NSRect visibleFrame, CGFloat scale)
{
  NSRect contentRect = GWLookInsideFrameForVisibleFrame(visibleFrame);

  contentRect.size.width /= scale;
  contentRect.size.height /= scale;

  return contentRect;
}

const NSSize GWLookInsideMinimumFrameSize = {420.0, 300.0};
const CGFloat GWLookInsideIconMaximumSide = 128.0;

/* Past this the overview of two or three items would just be the item
 * previews again, at full size, with nothing gained by the overview. */
const CGFloat GWLookInsideOverviewMaximumCellSide = 256.0;

/* Space around the grid and between its cells, the house margins of
 * AppearanceMetrics.h (METRICS_CONTENT_SIDE_MARGIN, METRICS_SPACE_12),
 * repeated as numbers so this file stays free of AppKit. */
static const CGFloat kOverviewMargin = 24.0;
static const CGFloat kOverviewGap = 12.0;

NSRect
GWLookInsideFrameForSavedSize(NSRect visibleFrame, NSSize savedSize, NSRect defaultFrame)
{
  CGFloat w, h;

  if (savedSize.width <= 0 || savedSize.height <= 0)
    {
      return defaultFrame;
    }

  w = MIN(MAX(floor(savedSize.width), GWLookInsideMinimumFrameSize.width),
          visibleFrame.size.width);
  h = MIN(MAX(floor(savedSize.height), GWLookInsideMinimumFrameSize.height),
          visibleFrame.size.height);

  return NSMakeRect(visibleFrame.origin.x + floor((visibleFrame.size.width - w) / 2.0),
                    visibleFrame.origin.y + floor((visibleFrame.size.height - h) / 2.0),
                    w, h);
}

/* Tries every column count and keeps the one giving the largest square
 * cells; for the handful to few hundred items a selection holds this is
 * cheap and needs no aspect-ratio heuristics. */
static void
OverviewGrid(NSRect bounds, NSUInteger count,
             NSUInteger *columnsOut, NSUInteger *rowsOut, CGFloat *sideOut)
{
  CGFloat availW = bounds.size.width - 2 * kOverviewMargin;
  CGFloat availH = bounds.size.height - 2 * kOverviewMargin;
  NSUInteger bestColumns = 1;
  CGFloat bestSide = 0;
  NSUInteger columns;

  for (columns = 1; columns <= count; columns++)
    {
      NSUInteger rows = (count + columns - 1) / columns;
      CGFloat side = MIN((availW - (columns - 1) * kOverviewGap) / columns,
                         (availH - (rows - 1) * kOverviewGap) / rows);

      if (side > bestSide)
        {
          bestSide = side;
          bestColumns = columns;
        }
    }

  *columnsOut = bestColumns;
  *rowsOut = (count + bestColumns - 1) / bestColumns;
  *sideOut = floor(MIN(MAX(bestSide, 0), GWLookInsideOverviewMaximumCellSide));
}

NSRect
GWLookInsideOverviewCellRect(NSRect bounds, NSUInteger count, NSUInteger index)
{
  NSUInteger columns, rows, row, column;
  CGFloat side, gridW, gridH, left, top;

  if (count == 0 || index >= count)
    {
      return NSZeroRect;
    }

  OverviewGrid(bounds, count, &columns, &rows, &side);
  if (side <= 0)
    {
      return NSZeroRect;
    }

  gridW = columns * side + (columns - 1) * kOverviewGap;
  gridH = rows * side + (rows - 1) * kOverviewGap;
  left = NSMinX(bounds) + floor((bounds.size.width - gridW) / 2.0);
  top = NSMinY(bounds) + floor((bounds.size.height - gridH) / 2.0) + gridH;
  row = index / columns;
  column = index % columns;

  return NSMakeRect(left + column * (side + kOverviewGap),
                    top - (row + 1) * side - row * kOverviewGap,
                    side, side);
}

NSInteger
GWLookInsideOverviewIndexAtPoint(NSRect bounds, NSUInteger count, NSPoint point)
{
  NSUInteger i;

  for (i = 0; i < count; i++)
    {
      if (NSPointInRect(point, GWLookInsideOverviewCellRect(bounds, count, i)))
        {
          return (NSInteger)i;
        }
    }
  return -1;
}
