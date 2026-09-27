/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

#include <math.h>
#import "GWQuickLookGeometry.h"

/* Whatever unit convention the caller's visible frame already uses (plain
 * points at GSScaleFactor 1.0, or the larger device-pixel numbers a higher
 * factor already bakes into NSScreen's own frame - see the
 * gnustep-scale-factor-pitfalls skill), this is a flat fraction of it, so
 * it never needs to multiply by the scale factor itself: it just centers
 * an 80%-sized rect inside whatever rect it is given. */
NSRect
GWQuickLookFrameForVisibleFrame(NSRect visibleFrame)
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
GWQuickLookContentRectForVisibleFrame(NSRect visibleFrame, CGFloat scale)
{
  NSRect contentRect = GWQuickLookFrameForVisibleFrame(visibleFrame);

  contentRect.size.width /= scale;
  contentRect.size.height /= scale;

  return contentRect;
}
