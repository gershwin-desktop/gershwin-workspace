/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 */

/* Window sizing rules the browsing and the spatial viewer share. */

#import <Foundation/Foundation.h>
#import "GWViewerBase.h"

/* The empty columns a new column view starts with.  The browser lays out
 * as many columns as fit by itself; this is only where it starts. */
extern const int GWViewerBrowserInitialColumns;

/* The window's resize increments for a view type.  @p legacyIncrement is
 * the configured column width the icon and list views step by. */
NSSize GWViewerResizeIncrements(GWViewType type, int legacyIncrement);

/* Where the browsing window's content box puts its parts.  The content
 * (with its own scrollers) sits directly above the path bar, so the
 * content's horizontal scroller is the row right above the path bar and
 * nothing scrolls below it.  Frames are in the box's own (not flipped)
 * coordinates, origin at the bottom left. */
typedef struct {
  NSRect pathBar;
  NSRect content;
  NSRect inspector;
} GWViewerBoxLayout;

/* @p pathBarHeight is the path bar's full frame height, used only when
 * @p showsPathBar; @p inspectorWidth only when @p showsInspector.  A part
 * that is not shown gets a zero rect.  The inspector spans the content's
 * height; the path bar spans the whole width under both. */
GWViewerBoxLayout GWViewerBoxLayoutForSize(NSSize size,
                                           BOOL showsPathBar,
                                           CGFloat pathBarHeight,
                                           BOOL showsInspector,
                                           CGFloat inspectorWidth);
