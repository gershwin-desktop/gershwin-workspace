/* GWSpatialIconsView.m
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

#import <AppKit/AppKit.h>
#import "GWSpatialIconsView.h"
#import "FSNIcon.h"
#import "FSNIconPlacement.h"

/* Layout margins (top-left origin); match the base view's spacing. */
#define X_MARGIN     (26)
#define Y_MARGIN     (12)
#define COLUMN_GAP_X (32)

@implementation GWSpatialIconsView

/* Top-left origin: DS_Store iloc maps directly to icon frames. */
- (BOOL)isFlipped
{
  return YES;
}

/* Spatial honors saved positions (re-override GWViewerIconsView's NO). */
- (BOOL)honorsSavedPositions
{
  return YES;
}

/* Flipped-aware background.  The base draws the background image anchored to
 * the visual top using bottom-left math (bounds.height - imageHeight); in a
 * flipped view the top is y=0, so anchor there and respectFlipped: so the
 * image is not drawn upside-down.  Icons are FSNIcon subviews and draw in
 * their own space, so they are unaffected by the flip. */
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

/* The view's own coordinates are already top-left, so the iloc<->view-center
 * mapping is the identity (no reference-height flip). */
- (NSPoint)ilocCenterForViewCenter:(NSPoint)center { return center; }
- (NSPoint)viewCenterForIlocCenter:(NSPoint)iloc   { return iloc; }

/* Cell key for occupancy tracking. */
static NSString *cellKey(NSInteger col, NSInteger row)
{
  return [NSString stringWithFormat: @"%ld:%ld", (long)col, (long)row];
}

/* Fixed-canvas layout: every icon sits at its stored top-left position and
 * never reflows; unplaced (AUTO) icons are dropped into the next free grid
 * cell once and recorded.  Sets each icon's frame and fills _contentExtent. */
- (void)layoutIcons
{
  NSUInteger count = [icons count];
  NSUInteger i;

  CGFloat cellW = _cachedCellSize.width;
  CGFloat cellH = _cachedCellSize.height;
  CGFloat gapX  = _cachedGapX;
  if (cellW <= 0) cellW = gridSize.width;
  if (cellH <= 0) cellH = gridSize.height;
  if (gapX  <= 0) gapX  = (CGFloat)COLUMN_GAP_X;

  if (!customIconPositions)
    customIconPositions = [[NSMutableDictionary alloc] init];

  NSPoint gOrigin = NSMakePoint((CGFloat)X_MARGIN, (CGFloat)Y_MARGIN);
  CGFloat visibleWidth = [self windowContentWidthForLayout];
  CGFloat availableWidth = visibleWidth - gOrigin.x;
  if (availableWidth < cellW + gapX) availableWidth = visibleWidth;
  NSUInteger nCols = (NSUInteger)((availableWidth + gapX) / (cellW + gapX));
  if (nCols < 1) nCols = 1;

  float maxX = visibleWidth;
  float maxY = 0;

  /* Return the stored top-left CENTER for an icon, or NO if it is AUTO. */
  NSMutableSet *occupied = [[NSMutableSet alloc] init];

  /* Pass A: mark cells occupied by icons that already have a position. */
  for (i = 0; i < count; i++)
    {
      FSNIcon *icon = [icons objectAtIndex: i];
      NSString *name = [[icon node] name];
      FSNIconItemData *data = [icon placementData];
      NSPoint c = NSZeroPoint;
      BOOL has = NO;

      NSValue *v = [customIconPositions objectForKey: name];
      if (v) { c = [v pointValue]; has = YES; }
      else if (data.ilocPosition.x >= 0) { c = data.ilocPosition; has = YES; }
      else if (data.placementMode == FSNIconPlacementModeManual) { c = data.pixelPosition; has = YES; }

      if (has)
        {
          NSInteger col = (NSInteger)floor((c.x - gOrigin.x) / (cellW + gapX));
          NSInteger row = (NSInteger)floor((c.y - gOrigin.y) / cellH);
          if (col >= 0 && row >= 0)
            [occupied addObject: cellKey(col, row)];
        }
    }

  /* Pass B: place every icon. */
  NSUInteger nextAuto = 0;
  for (i = 0; i < count; i++)
    {
      FSNIcon *icon = [icons objectAtIndex: i];
      NSString *name = [[icon node] name];
      FSNIconItemData *data = [icon placementData];
      NSPoint center;

      NSValue *v = [customIconPositions objectForKey: name];
      if (v)
        center = [v pointValue];
      else if (data.ilocPosition.x >= 0)
        center = data.ilocPosition;
      else if (data.placementMode == FSNIconPlacementModeManual)
        center = data.pixelPosition;
      else
        {
          /* AUTO: next free row-major cell (top-left flow). */
          NSInteger col, row;
          NSString *key;
          do {
            col = (NSInteger)(nextAuto % nCols);
            row = (NSInteger)(nextAuto / nCols);
            nextAuto++;
            key = cellKey(col, row);
          } while ([occupied containsObject: key]);
          [occupied addObject: key];

          center = FSNGridCellCenter(FSNGridCellMake(col, row),
                                     gOrigin, cellW, cellH, gapX);
          data.ilocPosition = center;   /* record (flipped identity = iloc) */
          data.placementMode = FSNIconPlacementModeManual;
          [customIconPositions setObject: [NSValue valueWithPoint: center]
                                  forKey: name];
        }

      NSRect frame = NSMakeRect(center.x - cellW / 2.0, center.y - cellH / 2.0,
                                cellW, cellH);
      if (NSEqualRects(frame, [icon frame]) == NO)
        [icon setFrame: frame];

      if (frame.origin.x + cellW > maxX) maxX = frame.origin.x + cellW;
      if (frame.origin.y + cellH > maxY) maxY = frame.origin.y + cellH;
    }

  [occupied release];

  _contentExtent = NSMakeSize(maxX, maxY);
}

@end
