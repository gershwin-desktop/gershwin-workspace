/* GWSpatialIconsView.h
 *
 * The spatial icon view: a flipped, fixed-canvas icon container.  Icons keep
 * their absolute .DS_Store (top-left) positions and never reflow on resize —
 * the window is a viewport onto a content-sized canvas.  Because the view is
 * flipped, DS_Store iloc coordinates map 1:1 to icon frames (no reference-
 * height conversion), which is both simpler and faithful to the classic Mac
 * spatial Finder.  Contrast GWViewerIconsView (browser icon mode), which
 * reflows to fill the width.
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

#import "GWViewerIconsView.h"

@interface GWSpatialIconsView : GWViewerIconsView
@end
