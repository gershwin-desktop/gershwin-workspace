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

#endif /* FSN_ICON_PLACEMENT_H */
