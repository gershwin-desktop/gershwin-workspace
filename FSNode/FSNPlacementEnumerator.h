/* FSNPlacementEnumerator.h
 *
 * Abstract base class for enumerating grid cell positions.
 * Provides row-major and column-major traversal over a grid
 * with configurable spacing and offsets.
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

#ifndef FSN_PLACEMENT_ENUMERATOR_H
#define FSN_PLACEMENT_ENUMERATOR_H

#import <Foundation/Foundation.h>
#import "FSNIconPlacement.h"

/* -----------------------------------------------------------------------
 * FSNPlacementEnumerator — abstract base class for grid cell enumeration.
 *
 * Subclasses provide a direction-specific traversal order over a 2D grid.
 * Call -nextCell: repeatedly until it returns NO to iterate all cells.
 * Call -reset to rewind the enumerator.
 * --------------------------------------------------------------------- */
@interface FSNPlacementEnumerator : NSObject
{
  NSUInteger _cols;
  NSUInteger _rows;
  NSUInteger _totalCells;
  NSUInteger _index;
  BOOL _exhausted;
}

- (instancetype)initWithColumns:(NSUInteger)cols rows:(NSUInteger)rows;
- (BOOL)nextCell:(FSNGridCell *)cellOut;
- (NSArray *)allCells;
- (void)reset;
- (NSUInteger)totalCells;

@end

/* -----------------------------------------------------------------------
 * FSNLeftToRightTopToBottomEnumerator — Finder icon view order.
 *
 *  (0,0) (1,0) (2,0) ... (N-1,0)
 *  (0,1) (1,1) (2,1) ... (N-1,1)
 *  ...
 * --------------------------------------------------------------------- */
@interface FSNLeftToRightTopToBottomEnumerator : FSNPlacementEnumerator
@end

/* -----------------------------------------------------------------------
 * FSNTopToBottomRightToLeftEnumerator — macOS Desktop order.
 *
 *  (N-1,0) (N-2,0) ... (0,0)
 *  (N-1,1) (N-2,1) ... (0,1)
 *  ...
 *
 * New icons appear at the top-right and proceed downward.
 * Columns progress right to left.
 * --------------------------------------------------------------------- */
@interface FSNTopToBottomRightToLeftEnumerator : FSNPlacementEnumerator
@end

#endif /* FSN_PLACEMENT_ENUMERATOR_H */
