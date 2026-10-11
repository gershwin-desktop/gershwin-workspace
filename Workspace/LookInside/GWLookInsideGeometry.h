/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

/* GWLookInsideGeometry.h - the Look Inside window's frame: 80% of a given
 * visible frame, centered in it.  Pulled out of GWLookInsidePanel as a
 * plain Foundation function so a headless red/green test can #include it
 * without pulling in the NSWindow subclass, the ContentViewers bundle
 * loader, or any AppKit linking.
 */

#import <Foundation/NSGeometry.h>

NSRect GWLookInsideFrameForVisibleFrame(NSRect visibleFrame);

/* The content rect to construct/resize the Look Inside window with, at a
 * given GSScaleFactor, so its real on-screen size ends up exactly
 * GWLookInsideFrameForVisibleFrame's whole-device-pixel rect - see
 * GWLookInsidePanel.m -initWithPaths:sourceWindow: for how this feeds into
 * -[NSWindow frameRectForContentRect:], which (per the
 * gnustep-scale-factor-pitfalls skill) multiplies the SIZE it is given by
 * GSScaleFactor but passes the ORIGIN through unconverted; only the size
 * is divided here for exactly that reason. */
NSRect GWLookInsideContentRectForVisibleFrame(NSRect visibleFrame, CGFloat scale);

/* The smallest frame the panel is restored at; below it the buttons of
 * its control strip would overlap. */
extern const NSSize GWLookInsideMinimumFrameSize;

/* The frame for a panel the user resized earlier: `savedSize` (screen
 * units, as remembered on close), cut to the visible frame and raised to
 * the minimum, centered in the visible frame.  An empty `savedSize` means
 * nothing was remembered and gives `defaultFrame`. */
NSRect GWLookInsideFrameForSavedSize(NSRect visibleFrame, NSSize savedSize, NSRect defaultFrame);

/* The overview of several items: square cells in a grid that is read left
 * to right, top row first, as large as fits `bounds` (but never larger than
 * GWLookInsideOverviewMaximumCellSide), centered. */
extern const CGFloat GWLookInsideOverviewMaximumCellSide;

NSRect GWLookInsideOverviewCellRect(NSRect bounds, NSUInteger count, NSUInteger index);

/* The item whose cell contains `point`, or -1 for the margins and gaps. */
NSInteger GWLookInsideOverviewIndexAtPoint(NSRect bounds, NSUInteger count, NSPoint point);

/* Icons come in at most this size; drawn larger they only turn blurry. */
extern const CGFloat GWLookInsideIconMaximumSide;
