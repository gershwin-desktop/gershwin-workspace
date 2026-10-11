/* GWSpatialIconsView.m
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

#import <AppKit/AppKit.h>
#import "GWSpatialIconsView.h"

/* The spatial policy is fully expressed by two small overrides; all layout,
 * Clean Up, occupancy and persistence mechanics live in FSNIconsView and are
 * flip-aware, so no layout code is duplicated here:
 *
 *  - isFlipped            -> top-left coordinates; the window is a viewport
 *                            onto a content-sized canvas and icons never
 *                            reflow on resize.  Because the view is flipped,
 *                            the base iloc<->view transform (FSNFunctions) is
 *                            the identity here -- no mapping override needed.
 *  - honorsSavedPositions -> saved .DS_Store/fdLocation positions are
 *                            honored and persisted (re-overrides the browser
 *                            view's NO).
 */
@implementation GWSpatialIconsView

- (BOOL)isFlipped
{
  return YES;
}

- (BOOL)honorsSavedPositions
{
  return YES;
}

@end
