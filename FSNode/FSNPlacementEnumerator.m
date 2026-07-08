/* FSNPlacementEnumerator.m
 *
 * Implementation of grid cell enumeration for icon layout.
 * Supports both row-major (Clean Up By Name) and column-major
 * (Clean Up By Kind/Date/Size) ordering.
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

#import "FSNPlacementEnumerator.h"

@implementation FSNPlacementEnumerator

- (instancetype)initWithColumns:(NSUInteger)cols rows:(NSUInteger)rows
{
  self = [super init];
  if (self)
    {
      _cols = cols;
      _rows = rows;
      _totalCells = cols * rows;
      _index = 0;
      _exhausted = (_totalCells == 0);
    }
  return self;
}

- (BOOL)nextCell:(FSNGridCell *)cellOut
{
  /* Base implementation — subclasses override this. */
  [self doesNotRecognizeSelector: _cmd];
  return NO;
}

- (NSArray *)allCells
{
  NSMutableArray *cells = [NSMutableArray arrayWithCapacity: _totalCells];
  FSNGridCell cell;
  [self reset];
  while ([self nextCell: &cell])
    {
      [cells addObject: [NSValue valueWithPoint: NSMakePoint(cell.col, cell.row)]];
    }
  return cells;
}

- (void)reset
{
  _index = 0;
  _exhausted = (_totalCells == 0);
}

- (NSUInteger)totalCells
{
  return _totalCells;
}

@end


@implementation FSNLeftToRightTopToBottomEnumerator

- (instancetype)initWithColumns:(NSUInteger)cols rows:(NSUInteger)rows
{
  return [super initWithColumns: cols rows: rows];
}

- (BOOL)nextCell:(FSNGridCell *)cellOut
{
  if (_exhausted || cellOut == NULL)
    return NO;

  /* Row-major order: for each row, sweep columns left to right.
   * Index 0 → (0,0), Index 1 → (1,0), ..., Index (N-1) → (N-1,0)
   * Index N → (0,1), etc. */
  NSUInteger col = _index % _cols;
  NSUInteger row = _index / _cols;

  if (row >= _rows)
    {
      _exhausted = YES;
      return NO;
    }

  *cellOut = FSNGridCellMake(col, row);
  _index++;
  return YES;
}

@end


@implementation FSNTopToBottomRightToLeftEnumerator

- (instancetype)initWithColumns:(NSUInteger)cols rows:(NSUInteger)rows
{
  return [super initWithColumns: cols rows: rows];
}

- (BOOL)nextCell:(FSNGridCell *)cellOut
{
  if (_exhausted || cellOut == NULL)
    return NO;

  /* Column-major order, right-to-left: for each row within the column,
   * sweep rows top to bottom, then move to the next column to the left.
   *
   * Index 0 → (N-1, 0)   top-right
   * Index 1 → (N-1, 1)
   * ...
   * Index (rows-1) → (N-1, rows-1)
   * Index rows → (N-2, 0)
   * ... */

  NSUInteger itemsPerColumn = _rows;
  NSUInteger colIndex = _index / itemsPerColumn;
  NSUInteger rowInCol  = _index % itemsPerColumn;

  if (colIndex >= _cols)
    {
      _exhausted = YES;
      return NO;
    }

  /* Rightmost column first: col = _cols - 1 - colIndex */
  NSUInteger col = _cols - 1 - colIndex;
  *cellOut = FSNGridCellMake(col, rowInCol);
  _index++;
  return YES;
}

@end
