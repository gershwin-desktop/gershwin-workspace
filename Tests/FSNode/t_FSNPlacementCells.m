/* t_FSNPlacementCells.m — headless coverage for the wide-label-aware Clean Up
 * grid cells.
 *
 * layoutIcons widens a placed icon's frame up to 2x the cell width when its
 * label is long, so Clean Up must leave empty grid positions between such
 * icons.  FSNPlacementCellsForWidths / FSNSkipColumnsForFrames are the pure
 * Foundation-only geometry for that, shared by the row-major (FileViewer) and
 * column-major (desktop) placement directions.
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

#import <Foundation/Foundation.h>
#import "Testing.h"
#import "FSNIconPlacement.h"

int
main(void)
{
  NSAutoreleasePool *arp = [NSAutoreleasePool new];

  const CGFloat cellW = 96, gapX = 32;
  const CGFloat pitch = cellW + gapX;   /* 128 */

  /* --- FSNSkipColumnsForFrames --- */
  PASS(FSNSkipColumnsForFrames(96, 96, pitch) == 1,
       "two normal-width labels pack in adjacent columns");
  PASS(FSNSkipColumnsForFrames(192, 192, pitch) == 2,
       "two 2x-wide labels need one empty column between them");
  PASS(FSNSkipColumnsForFrames(192, 96, pitch) == 2,
       "2x-wide label next to a 96px one needs the 2x skip");
  PASS(FSNSkipColumnsForFrames(96, 192, pitch) == 2,
       "96px label next to a 2x-wide one needs the 2x skip");
  PASS(FSNSkipColumnsForFrames(1, 1, pitch) == 1,
       "skip never drops below one column");
  PASS(FSNSkipColumnsForFrames(192, 40, pitch) == 1,
       "a wide label next to a short one fits in adjacent columns");

  /* --- Row-major: dense packing unchanged for normal labels --- */
  {
    const NSUInteger n = 5;
    CGFloat fw[5] = { 96, 96, 96, 96, 96 };
    FSNGridCell *cells = FSNPlacementCellsForWidths(n, fw, 4, 2,
      FSNPlacementDirectionLeftToRightTopToBottom, pitch);
    PASS(FSNGridCellsEqual(cells[0], FSNGridCellMake(0, 0))
         && FSNGridCellsEqual(cells[1], FSNGridCellMake(1, 0))
         && FSNGridCellsEqual(cells[2], FSNGridCellMake(2, 0))
         && FSNGridCellsEqual(cells[3], FSNGridCellMake(3, 0))
         && FSNGridCellsEqual(cells[4], FSNGridCellMake(0, 1)),
         "row-major dense: consecutive cells, wrapping at nCols");
    free(cells);
  }

  /* --- Row-major: wide labels skip a column --- */
  {
    const NSUInteger n = 3;
    CGFloat fw[3] = { 192, 192, 96 };
    FSNGridCell *cells = FSNPlacementCellsForWidths(n, fw, 8, 2,
      FSNPlacementDirectionLeftToRightTopToBottom, pitch);
    PASS(FSNGridCellsEqual(cells[0], FSNGridCellMake(0, 0))
         && FSNGridCellsEqual(cells[1], FSNGridCellMake(2, 0))
         && FSNGridCellsEqual(cells[2], FSNGridCellMake(4, 0)),
         "row-major: 192-wide labels land 2 columns apart, leaving gaps");
    free(cells);
  }

  /* --- Row-major: a short neighbour needs no skip --- */
  {
    const NSUInteger n = 3;
    CGFloat fw[3] = { 192, 40, 192 };
    FSNGridCell *cells = FSNPlacementCellsForWidths(n, fw, 8, 2,
      FSNPlacementDirectionLeftToRightTopToBottom, pitch);
    /* (0,0), skip(192,40)=1 -> (1,0), skip(40,192)=1 -> (2,0). */
    PASS(FSNGridCellsEqual(cells[0], FSNGridCellMake(0, 0))
         && FSNGridCellsEqual(cells[1], FSNGridCellMake(1, 0))
         && FSNGridCellsEqual(cells[2], FSNGridCellMake(2, 0)),
         "row-major: a short label between two wide ones needs no skip");
    free(cells);
  }

  /* --- Row-major: a skip that wraps to the next row --- */
  {
    const NSUInteger n = 3;
    CGFloat fw[3] = { 192, 192, 96 };
    FSNGridCell *cells = FSNPlacementCellsForWidths(n, fw, 3, 2,
      FSNPlacementDirectionLeftToRightTopToBottom, pitch);
    /* (0,0), skip 2 -> (2,0); skip 2 -> wraps to (1,1). */
    PASS(FSNGridCellsEqual(cells[0], FSNGridCellMake(0, 0))
         && FSNGridCellsEqual(cells[1], FSNGridCellMake(2, 0))
         && FSNGridCellsEqual(cells[2], FSNGridCellMake(1, 1)),
         "row-major: wrap keeps the reading order");
    free(cells);
  }

  /* --- Column-major: dense packing rightmost-first --- */
  {
    const NSUInteger n = 4;
    CGFloat fw[4] = { 96, 96, 96, 96 };
    FSNGridCell *cells = FSNPlacementCellsForWidths(n, fw, 3, 2,
      FSNPlacementDirectionTopToBottomRightToLeft, pitch);
    PASS(FSNGridCellsEqual(cells[0], FSNGridCellMake(2, 0))
         && FSNGridCellsEqual(cells[1], FSNGridCellMake(2, 1))
         && FSNGridCellsEqual(cells[2], FSNGridCellMake(1, 0))
         && FSNGridCellsEqual(cells[3], FSNGridCellMake(1, 1)),
         "column-major dense: rightmost column filled top-to-bottom");
    free(cells);
  }

/* --- Column-major: a wide label only affects its own row --- */
  {
    const NSUInteger n = 4;
    CGFloat fw[4] = { 192, 96, 192, 96 };
    FSNGridCell *cells = FSNPlacementCellsForWidths(n, fw, 6, 2,
      FSNPlacementDirectionTopToBottomRightToLeft, pitch);
    /* Row 0 (icons 0,2) both 192 wide: skip 2 -> cells (5,0) and (3,0).
     * Row 1 (icons 1,3) both 96 wide: dense -> (5,1) and (4,1).  The wide
     * row must not push the short row's icon apart. */
    PASS(FSNGridCellsEqual(cells[0], FSNGridCellMake(5, 0))
         && FSNGridCellsEqual(cells[1], FSNGridCellMake(5, 1))
         && FSNGridCellsEqual(cells[2], FSNGridCellMake(3, 0))
         && FSNGridCellsEqual(cells[3], FSNGridCellMake(4, 1)),
         "column-major: a wide label only skips in its own row");
    free(cells);
  }

/* --- Column-major: skip clamped at the left edge --- */
  {
    const NSUInteger n = 4;
    CGFloat fw[4] = { 192, 96, 192, 96 };
    FSNGridCell *cells = FSNPlacementCellsForWidths(n, fw, 2, 2,
      FSNPlacementDirectionTopToBottomRightToLeft, pitch);
    /* Row 0 (icons 0,2): (1,0), skip 2 clamps to (0,0).
     * Row 1 (icons 1,3): dense (1,1), (0,1). */
    PASS(FSNGridCellsEqual(cells[0], FSNGridCellMake(1, 0))
         && FSNGridCellsEqual(cells[1], FSNGridCellMake(1, 1))
         && FSNGridCellsEqual(cells[2], FSNGridCellMake(0, 0))
         && FSNGridCellsEqual(cells[3], FSNGridCellMake(0, 1)),
         "column-major: skip clamped at the left grid edge");
    free(cells);
  }

  [arp release];
  return 0;
}