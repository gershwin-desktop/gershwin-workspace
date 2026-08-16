/* FSNIconPlacement.h
 *
 * Icon placement data model for DS_Store-compatible icon positioning.
 * Stores icon center points and placement mode (AUTO, MANUAL).
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

#ifndef FSN_ICON_PLACEMENT_H
#define FSN_ICON_PLACEMENT_H

#import <Foundation/Foundation.h>
#import <math.h>

/* -----------------------------------------------------------------------
 * Placement mode — who owns the icon's position.
 *
 *  AUTO    Layout engine chooses. May move during cleanup or grid recalc.
 *  MANUAL  User dragged it. Layout engine never reassigns automatically.
 * --------------------------------------------------------------------- */
typedef NS_ENUM(NSUInteger, FSNIconPlacementMode)
{
  FSNIconPlacementModeAuto   = 0,
  FSNIconPlacementModeManual = 1
};

/* -----------------------------------------------------------------------
 * Placement direction — how the placement enumerator traverses the grid.
 *
 *  LeftToRightTopToBottom   Finder icon view (reading order).
 *  TopToBottomRightToLeft   macOS Desktop (columns progress right → left).
 * --------------------------------------------------------------------- */
typedef NS_ENUM(NSUInteger, FSNPlacementDirection)
{
  FSNPlacementDirectionLeftToRightTopToBottom = 0,
  FSNPlacementDirectionTopToBottomRightToLeft = 1
};

/* -----------------------------------------------------------------------
 * FSNGridCell — logical (column, row) coordinate of an icon in the grid.
 * Used by the virtual grid enumerator during Clean Up.
 * --------------------------------------------------------------------- */
typedef struct {
  NSUInteger col;
  NSUInteger row;
} FSNGridCell;

/* Inline convenience constructors and comparisons. */

static inline FSNGridCell
FSNGridCellMake(NSUInteger col, NSUInteger row)
{
  FSNGridCell cell = { col, row };
  return cell;
}

static inline BOOL
FSNGridCellsEqual(FSNGridCell a, FSNGridCell b)
{
  return (a.col == b.col && a.row == b.row);
}

static inline NSUInteger
FSNGridCellHash(FSNGridCell cell)
{
  return (cell.col << 16) | (cell.row & 0xFFFF);
}

/* Placeholder sentinel for "no cell assigned". */
static const FSNGridCell FSNGridCellNone = { (NSUInteger)-1, (NSUInteger)-1 };

/* Center point of a grid cell in a top-left origin grid: columns are spaced
 * (cellW + gapX) apart, rows cellH apart, from `origin` (a cell's top-left
 * area corner).  Pure geometry — the single source used by the spatial icon
 * view's AUTO placement, and unit-tested headlessly. */
static inline NSPoint
FSNGridCellCenter(FSNGridCell cell, NSPoint origin,
                  CGFloat cellW, CGFloat cellH, CGFloat gapX)
{
  return NSMakePoint(origin.x + (CGFloat)cell.col * (cellW + gapX) + cellW / 2.0,
                     origin.y + (CGFloat)cell.row * cellH + cellH / 2.0);
}

/* Inverse of FSNGridCellCenter: the (col,row) whose cell area contains
 * `center` in the same top-left grid.  Returns FSNGridCellNone for points
 * left of / above the origin. */
static inline FSNGridCell
FSNGridCellForCenter(NSPoint center, NSPoint origin,
                     CGFloat cellW, CGFloat cellH, CGFloat gapX)
{
  CGFloat dx = center.x - origin.x;
  CGFloat dy = center.y - origin.y;
  if (dx < 0 || dy < 0 || cellW <= 0 || cellH <= 0)
    return FSNGridCellNone;
  return FSNGridCellMake((NSUInteger)(dx / (cellW + gapX)),
                         (NSUInteger)(dy / cellH));
}

static inline NSString *
NSStringFromFSNGridCell(FSNGridCell cell)
{
  return [NSString stringWithFormat: @"(%lu, %lu)",
                   (unsigned long)cell.col, (unsigned long)cell.row];
}

/* -----------------------------------------------------------------------
 * Wide-label-aware grid cells for Clean Up.
 *
 * Clean Up packs icons one per grid cell, but layoutIcons widens a placed
 * icon's frame up to 2x the cell width when its label is long, so two icons
 * in adjacent cells can end up with overlapping frames/labels.  These helpers
 * compute grid cells that leave empty positions between such icons.
 * --------------------------------------------------------------------- */

/* Grid columns needed between two icons whose laid-out frames are fw0 and
 * fw1 wide, at column pitch `pitch` (cellW + gapX).  Frames are centered on
 * the cell centers, so the centers must be at least (fw0 + fw1)/2 apart.
 * Minimum one column. */
static inline NSUInteger
FSNSkipColumnsForFrames(CGFloat fw0, CGFloat fw1, CGFloat pitch)
{
  CGFloat need = (fw0 + fw1) / 2.0;
  NSUInteger skip = (NSUInteger)ceil(need / pitch);
  return (skip < 1) ? 1 : skip;
}

/* Grid cells for `count` icons with laid-out frame widths `fw`, placed in
 * `direction` order.  Row-major places icons left-to-right and wraps at
 * `nCols`, growing rows downward, advancing `FSNSkipColumnsForFrames` cells
 * between consecutive icons.  Column-major fills the rightmost column top to
 * bottom first, then the next column to the left, but lays out each ROW
 * independently (starting at the right grid edge), so a wide label only
 * pushes apart the horizontally-adjacent icon in its own row, clamped at the
 * left edge.  Returns a malloc'd array of `count` cells (caller frees). */
static inline FSNGridCell *
FSNPlacementCellsForWidths(NSUInteger count, const CGFloat *fw,
                           NSUInteger nCols, NSUInteger nRows,
                           FSNPlacementDirection direction, CGFloat pitch)
{
  FSNGridCell *cells = calloc(count ? count : 1, sizeof(FSNGridCell));
  if (count == 0)
    return cells;

  if (direction == FSNPlacementDirectionTopToBottomRightToLeft)
    {
      /* Column-major reading order: the rightmost column fills top to bottom
       * first, then the next column to the left.  Each ROW is laid out
       * independently, starting at the right grid edge and advancing left by
       * the skip of each horizontally-adjacent pair, clamped at the left
       * edge.  A wide label therefore pushes only its own row's neighbour
       * apart, never every row of the column. */
      NSUInteger perCol = (nRows > 0) ? nRows : 1;
      NSUInteger r, idx;
      for (r = 0; r < perCol; r++)
        {
          NSUInteger col = (nCols > 0) ? nCols - 1 : 0;
          BOOL first = YES;
          for (idx = r; idx < count; idx += perCol)
            {
              if (!first)
                {
                  NSUInteger skip = FSNSkipColumnsForFrames(fw[idx - perCol],
                                                            fw[idx], pitch);
                  col = (col >= skip) ? (col - skip) : 0;
                }
              cells[idx] = FSNGridCellMake(col, r);
              first = NO;
            }
        }
      return cells;
    }

  /* Row-major: left-to-right, wrapping at nCols. */
  {
    NSUInteger col = 0, row = 0;
    NSUInteger i;
    for (i = 0; i < count; i++)
      {
        cells[i] = FSNGridCellMake(col, row);
        if (i + 1 < count)
          {
            NSUInteger skip = FSNSkipColumnsForFrames(fw[i], fw[i + 1], pitch);
            col += skip;
            while (nCols > 0 && col >= nCols)
              {
                col -= nCols;
                row++;
              }
          }
      }
  }
  return cells;
}

/* -----------------------------------------------------------------------
 * FSNIconItemData — per-icon persistent placement state.
 *
 * Each FSNIcon owns one of these.  The position is stored in exactly one
 * representation: ilocPosition, the DS_Store top-left CENTER coordinate
 * ((-1,-1) = no stored position).  View-local coordinates exist only
 * transiently and cross the boundary through FSNIconsView's overridable
 * ilocCenterForViewCenter:/viewCenterForIlocCenter: mapping, so the stored
 * value never depends on which view (flipped or bottom-left) wrote it.
 * --------------------------------------------------------------------- */
@interface FSNIconItemData : NSObject <NSCopying>
{
  NSString *_itemID;
  NSString *_filename;
  FSNIconPlacementMode _placementMode;
  NSPoint _ilocPosition;        /* DS_Store top-left CENTER; (-1,-1) = none */
}

@property (nonatomic, retain) NSString *itemID;
@property (nonatomic, retain) NSString *filename;
@property (nonatomic) FSNIconPlacementMode placementMode;
@property (nonatomic) NSPoint ilocPosition;

@end

/* -----------------------------------------------------------------------
 * Canonical iloc <-> view-center transform — defined in exactly one place.
 *
 * An iloc is an icon CENTER with x from the left and y from the TOP of the
 * view's content area (the DS_Store Iloc / FinderInfo fdLocation convention).
 * A view-center is the same point in the view's own coordinate space:
 *
 *   flipped view (top-left origin, e.g. GWSpatialIconsView): identity.
 *   non-flipped view (bottom-left origin, e.g. the desktop):  (x, refHeight - y)
 *
 * refHeight is the view's own content height ([self bounds].size.height).
 * The transform is its own inverse, so both directions share one formula.
 * --------------------------------------------------------------------- */
static inline NSPoint
FSNViewCenterFromIloc(NSPoint iloc, CGFloat refHeight, BOOL flipped)
{
  if (flipped)
    return iloc;
  return NSMakePoint(iloc.x, refHeight - iloc.y);
}

static inline NSPoint
FSNIlocFromViewCenter(NSPoint center, CGFloat refHeight, BOOL flipped)
{
  if (flipped)
    return center;
  return NSMakePoint(center.x, refHeight - center.y);
}

#endif /* FSN_ICON_PLACEMENT_H */
