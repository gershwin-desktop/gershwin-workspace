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
