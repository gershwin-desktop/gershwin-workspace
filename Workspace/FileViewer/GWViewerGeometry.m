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
