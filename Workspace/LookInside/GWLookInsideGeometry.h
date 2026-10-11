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
