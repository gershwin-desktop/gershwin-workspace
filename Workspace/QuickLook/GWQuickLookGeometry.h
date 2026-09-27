/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

/* GWQuickLookGeometry.h - the Quick Look window's frame: 80% of a given
 * visible frame, centered in it.  Pulled out of GWQuickLookPanel as a
 * plain Foundation function so a headless red/green test can #include it
 * without pulling in the NSWindow subclass, the ContentViewers bundle
 * loader, or any AppKit linking.
 */

#import <Foundation/NSGeometry.h>

NSRect GWQuickLookFrameForVisibleFrame(NSRect visibleFrame);

/* The content rect to construct/resize the Quick Look window with, at a
 * given GSScaleFactor, so its real on-screen size ends up exactly
 * GWQuickLookFrameForVisibleFrame's whole-device-pixel rect - see
 * GWQuickLookPanel.m -initWithPaths:sourceWindow: for how this feeds into
 * -[NSWindow frameRectForContentRect:], which (per the
 * gnustep-scale-factor-pitfalls skill) multiplies the SIZE it is given by
 * GSScaleFactor but passes the ORIGIN through unconverted; only the size
 * is divided here for exactly that reason. */
NSRect GWQuickLookContentRectForVisibleFrame(NSRect visibleFrame, CGFloat scale);
