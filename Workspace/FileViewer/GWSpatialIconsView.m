/* GWSpatialIconsView.m
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

#import <AppKit/AppKit.h>
#import "GWSpatialIconsView.h"

/* The spatial policy is fully expressed by four small overrides; all layout,
 * Clean Up, occupancy and persistence mechanics live in FSNIconsView and are
 * flip-aware, so no layout code is duplicated here:
 *
 *  - isFlipped            -> top-left coordinates; the window is a viewport
 *                            onto a content-sized canvas and icons never
 *                            reflow on resize.
 *  - honorsSavedPositions -> saved .DS_Store/fdLocation positions are
 *                            honored and persisted (re-overrides the browser
 *                            view's NO).
 *  - iloc mapping         -> identity: the view's own coordinates ARE
 *                            DS_Store top-left iloc coordinates.
 *  - drawRect             -> flip-aware background drawing.
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

- (NSPoint)ilocCenterForViewCenter:(NSPoint)center { return center; }
- (NSPoint)viewCenterForIlocCenter:(NSPoint)iloc   { return iloc; }

/* Flipped-aware background.  The base anchors the background image to the
 * visual top using bottom-left math; in a flipped view the top is y=0, so
 * anchor there and respectFlipped: so the image is not drawn upside-down.
 * Icons are FSNIcon subviews and draw in their own space, so they are
 * unaffected by the flip. */
- (void)drawRect:(NSRect)rect
{
  if (backgroundImage)
    {
      NSRect bounds = [self bounds];
      NSSize imageSize = [backgroundImage size];
      NSRect imageRect;
      imageRect.origin = NSMakePoint(bounds.origin.x, 0);   /* top in flipped */
      imageRect.size = imageSize;
      [backgroundImage drawInRect: imageRect
                         fromRect: NSZeroRect
                        operation: NSCompositeSourceOver
                         fraction: 1.0
                   respectFlipped: YES
                            hints: nil];
    }
  else
    {
      [backColor set];
      NSRectFill(rect);
    }
}

@end
