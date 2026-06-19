/* FSNIconPlacement.h
 *
 * Icon placement data model for DS_Store-compatible icon positioning.
 * Stores icon center points, grid indices, and placement mode
 * (AUTO, MANUAL, LOCKED).
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
 *  LOCKED  Absolutely fixed (GNUstep extension). Never relocated.
 * --------------------------------------------------------------------- */
typedef NS_ENUM(NSUInteger, FSNIconPlacementMode)
{
  FSNIconPlacementModeAuto   = 0,
  FSNIconPlacementModeManual = 1,
  FSNIconPlacementModeLocked = 2
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

static inline NSString *
NSStringFromFSNGridCell(FSNGridCell cell)
{
  return [NSString stringWithFormat: @"(%lu, %lu)",
                   (unsigned long)cell.col, (unsigned long)cell.row];
}

#endif /* FSN_ICON_PLACEMENT_H */
