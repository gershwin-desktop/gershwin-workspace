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
