/* FSNGridLayoutManager.m
 *
 * Implementation of the imaginary grid layout manager.
 * Maps macOS DS_Store icon positions onto a configurable grid,
 * enables pixel-precise free positioning, and supports Clean Up
 * grid alignment.
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

#import "FSNGridLayoutManager.h"
#import "FSNPlacementEnumerator.h"
#import "FSNIcon.h"

@implementation FSNIconItemData

- (instancetype)init
{
  self = [super init];
  if (self)
    {
      /* Generate a unique ID using GNUstep's globally unique string */
      _itemID = [[[NSProcessInfo processInfo] globallyUniqueString] copy];

      _filename = nil;
      _placementMode = FSNIconPlacementModeAuto;
      _pixelPosition = NSZeroPoint;
      _ilocPosition = NSMakePoint(-1, -1);  /* -1 means "not set from DS_Store" */
      _gridCell = FSNGridCellNone;
      _zOrder = 0;
      _hasGridPosition = NO;
    }
  return self;
}

- (void)dealloc
{
  [_itemID release];
  [_filename release];
  [super dealloc];
}

- (id)copyWithZone:(NSZone *)zone
{
  FSNIconItemData *copy = [[FSNIconItemData allocWithZone: zone] init];
  [copy setItemID: _itemID];
  [copy setFilename: _filename];
  [copy setPlacementMode: _placementMode];
  [copy setPixelPosition: _pixelPosition];
  [copy setIlocPosition: _ilocPosition];
  [copy setGridCell: _gridCell];
  [copy setZOrder: _zOrder];
  [copy setHasGridPosition: _hasGridPosition];
  return copy;
}

- (NSString *)description
{
  return [NSString stringWithFormat:
    @"<FSNIconItemData %p: id=%@ file=%@ mode=%lu cell=(%lu,%lu) pix=(%.0f,%.0f) hasGrid=%d>",
    self, _itemID, _filename,
    (unsigned long)_placementMode,
    (unsigned long)_gridCell.col, (unsigned long)_gridCell.row,
    _pixelPosition.x, _pixelPosition.y,
    _hasGridPosition];
}

@end


@implementation FSNGridLayoutManager

- (instancetype)initWithContainer:(NSView *)container
{
  self = [super init];
  if (self)
    {
      _container = container;  /* weak reference */
      _occupancyMap = [[NSMutableDictionary alloc] init];
      _direction = FSNPlacementDirectionLeftToRightTopToBottom;
      _enumerator = nil;
      _cols = 1;
      _rows = 1;
      _cellSize = NSMakeSize(48 + 6, 48 + 6);  /* sensible default */
      _xMargin = 10.0;
      _yMargin = 0.0;
      _gridOrigin = NSZeroPoint;
      _needsRecalc = YES;

      /* Recalc tracking */
      _lastIconSize = -1.0;
      _lastLabelHeight = -1.0;
      _lastLabelMargin = -1;
      _lastInfoType = -1;
      _lastIconPosition = -1;
      _lastViewSize = NSZeroSize;
      _lastGridSpacing = -1.0;
    }
  return self;
}

- (void)dealloc
{
  [_occupancyMap release];
  [_enumerator release];
  [super dealloc];
}

#pragma mark - Geometry Recalculation

- (void)recalcWithIconSize:(CGFloat)icSize
                labelHeight:(CGFloat)lblHeight
               labelMargin:(int)lblMargin
                  infoType:(FSNInfoType)infoType
             iconPosition:(NSCellImagePosition)icnPos
                 viewSize:(NSSize)vSize
               direction:(FSNPlacementDirection)dir
                 xMargin:(CGFloat)xm
                 yMargin:(CGFloat)ym
              gridSpacing:(CGFloat)spacing
{
  /* Skip if nothing changed */
  if (!_needsRecalc
      && icSize == _lastIconSize
      && lblHeight == _lastLabelHeight
      && lblMargin == _lastLabelMargin
      && infoType == _lastInfoType
      && icnPos == _lastIconPosition
      && NSEqualSizes(vSize, _lastViewSize)
      && dir == _direction
      && xm == _xMargin
      && spacing == _lastGridSpacing)
    {
      return;
    }

  _needsRecalc = NO;
  _lastIconSize = icSize;
  _lastLabelHeight = lblHeight;
  _lastLabelMargin = lblMargin;
  _lastInfoType = infoType;
  _lastIconPosition = icnPos;
  _lastViewSize = vSize;
  _lastGridSpacing = spacing;
  _direction = dir;
  _xMargin = xm;
  _yMargin = ym;

  /* ---- Compute cell size (same logic as FSNIconsView.calculateGridSize) ---- */
  CGFloat hlSize = ceil(icSize + 6.0);

  /* Two-line or one-line label area */
  CGFloat labelW = lblMargin * 2;   /* approximate; caller provides the metrics */
  CGFloat lbsh;
  if (infoType != FSNInfoNameType)
    {
      lbsh = (lblHeight * 2.0) - 2.0;
    }
  else
    {
      lbsh = lblHeight;
    }

  if (icnPos == NSImageAbove)
    {
      _cellSize.height = hlSize + lbsh;
      /* Width is max of highlight and label; labelW passed in as lMargin. */
      _cellSize.width = hlSize;
    }
  else if (icnPos == NSImageLeft)
    {
      CGFloat needed = hlSize + labelW + lblMargin;
      _cellSize.height = (lbsh > hlSize) ? lbsh : hlSize;
      _cellSize.width = needed;
    }
  else /* NSImageOnly */
    {
      _cellSize.width = hlSize;
      _cellSize.height = hlSize;
    }

  /* Extra padding at bottom to match FSNIcon's lblmargin/2 + 2 */
  _cellSize.height += (CGFloat)(lblMargin / 2) + 2.0;

  /* Apply grid spacing */
  if (spacing > 0)
    {
      _cellSize.width += spacing;
      _cellSize.height += spacing;
    }

  /* ---- Compute columns and rows ---- */
  CGFloat availW = vSize.width;
  CGFloat availH = vSize.height;

  if (availW <= 0.0) availW = 100.0;
  if (availH <= 0.0) availH = 100.0;

  _cols = (NSUInteger)((availW + _xMargin) / (_cellSize.width + _xMargin));
  if (_cols < 1) _cols = 1;

  _rows = (NSUInteger)((availH + _yMargin) / (_cellSize.height + _yMargin));
  if (_rows < 1) _rows = 1;

  /* ---- Create new enumerator ---- */
  [_enumerator release];
  switch (_direction)
    {
    case FSNPlacementDirectionLeftToRightTopToBottom:
      _enumerator = [[FSNLeftToRightTopToBottomEnumerator alloc]
                      initWithColumns: _cols rows: _rows];
      break;
    case FSNPlacementDirectionTopToBottomRightToLeft:
      _enumerator = [[FSNTopToBottomRightToLeftEnumerator alloc]
                      initWithColumns: _cols rows: _rows];
      break;
    default:
      _enumerator = [[FSNLeftToRightTopToBottomEnumerator alloc]
                      initWithColumns: _cols rows: _rows];
      break;
    }

  /* ---- Clear occupancy (caller must re-occupy with current items) ---- */
  [_occupancyMap removeAllObjects];
}

- (void)setGridOrigin:(NSPoint)origin
{
  _gridOrigin = origin;
}

- (NSPoint)gridOrigin
{
  return _gridOrigin;
}

#pragma mark - Occupancy

- (void)clearOccupancy
{
  [_occupancyMap removeAllObjects];
}

- (void)occupyCell:(FSNGridCell)cell withItemData:(FSNIconItemData *)item
{
  if (FSNGridCellsEqual(cell, FSNGridCellNone))
    return;

  NSUInteger flat = [self flatIndexForCell: cell];
  [_occupancyMap setObject: item forKey: [NSNumber numberWithUnsignedInteger: flat]];
}

- (void)vacateCell:(FSNGridCell)cell
{
  if (FSNGridCellsEqual(cell, FSNGridCellNone))
    return;

  NSUInteger flat = [self flatIndexForCell: cell];
  [_occupancyMap removeObjectForKey: [NSNumber numberWithUnsignedInteger: flat]];
}

- (BOOL)isCellOccupied:(FSNGridCell)cell
{
  if (FSNGridCellsEqual(cell, FSNGridCellNone))
    return NO;

  NSUInteger flat = [self flatIndexForCell: cell];
  return ([_occupancyMap objectForKey: [NSNumber numberWithUnsignedInteger: flat]] != nil);
}

- (FSNIconItemData *)itemDataAtCell:(FSNGridCell)cell
{
  if (FSNGridCellsEqual(cell, FSNGridCellNone))
    return nil;

  NSUInteger flat = [self flatIndexForCell: cell];
  return [_occupancyMap objectForKey: [NSNumber numberWithUnsignedInteger: flat]];
}

#pragma mark - First Free Cell

- (BOOL)firstFreeCell:(FSNGridCell *)cellOut
{
  if (cellOut == NULL) return NO;

  FSNPlacementEnumerator *e = _enumerator;
  [e reset];
  FSNGridCell cell;
  while ([e nextCell: &cell])
    {
      if (![self isCellOccupied: cell])
        {
          *cellOut = cell;
          return YES;
        }
    }

  *cellOut = FSNGridCellNone;
  return NO;
}

#pragma mark - Coordinate Conversion

- (NSPoint)originForCell:(FSNGridCell)cell
{
  /* x = left edge + col offset
   * In GNUstep coords (y=0 at bottom):
   *   row 0 = topmost row (highest y)
   *   row N-1 = bottommost row (lowest y)
   */
  CGFloat x = _gridOrigin.x + (CGFloat)cell.col * (_cellSize.width + _xMargin);
  CGFloat y = _gridOrigin.y
              - (CGFloat)(cell.row + 1) * _cellSize.height
              - (CGFloat)cell.row * _yMargin;

  return NSMakePoint(x, y);
}

- (NSUInteger)flatIndexForCell:(FSNGridCell)cell
{
  return cell.row * _cols + cell.col;
}

- (FSNGridCell)cellForFlatIndex:(NSUInteger)index
{
  if (_cols == 0) return FSNGridCellNone;
  return FSNGridCellMake(index % _cols, index / _cols);
}

- (FSNGridCell)cellForPoint:(NSPoint)point
{
  /* Snap a pixel point to the nearest grid cell.
   * Works with the same origin scheme as originForCell: */
  if (_cellSize.width <= 0 || _cellSize.height <= 0)
    return FSNGridCellNone;

  CGFloat relX = point.x - _gridOrigin.x;
  CGFloat relY = _gridOrigin.y - point.y;  /* distance down from top */

  NSInteger col = (NSInteger)floor(relX / (_cellSize.width + _xMargin));
  NSInteger row = (NSInteger)floor(relY / (_cellSize.height + _yMargin));

  if (col < 0) col = 0;
  if (row < 0) row = 0;
  if ((NSUInteger)col >= _cols) col = (NSInteger)(_cols - 1);
  if ((NSUInteger)row >= _rows) row = (NSInteger)(_rows - 1);

  return FSNGridCellMake((NSUInteger)col, (NSUInteger)row);
}

#pragma mark - Cleanup

- (NSArray *)cleanupAutoItems:(NSArray *)icons
{
  /* Separate AUTO items from MANUAL/LOCKED items.
   * Collect which cells are occupied by non-AUTO items. */

  NSMutableArray *autoIcons = [NSMutableArray array];
  NSMutableDictionary *fixedOccupancy = [NSMutableDictionary dictionary];
  NSUInteger i;

  for (i = 0; i < [icons count]; i++)
    {
      FSNIcon *icon = [icons objectAtIndex: i];
      FSNIconItemData *data = [icon placementData];

      if (data.placementMode == FSNIconPlacementModeManual
          || data.placementMode == FSNIconPlacementModeLocked)
        {
          if (data.hasGridPosition
              && !FSNGridCellsEqual(data.gridCell, FSNGridCellNone))
            {
              NSUInteger flat = [self flatIndexForCell: data.gridCell];
              [fixedOccupancy setObject: data
                                 forKey: [NSNumber numberWithUnsignedInteger: flat]];
            }
        }
      else
        {
          [autoIcons addObject: icon];
        }
    }

  /* Reset occupancy to just the MANUAL/LOCKED items */
  [_occupancyMap removeAllObjects];
  [_occupancyMap addEntriesFromDictionary: fixedOccupancy];

  /* Repack AUTO items in placement order */
  FSNPlacementEnumerator *e = _enumerator;
  [e reset];
  FSNGridCell cell;
  NSUInteger ai = 0;

  while (ai < [autoIcons count] && [e nextCell: &cell])
    {
      if (![self isCellOccupied: cell])
        {
          FSNIcon *icon = [autoIcons objectAtIndex: ai];
          FSNIconItemData *data = [icon placementData];
          data.gridCell = cell;
          data.hasGridPosition = YES;
          data.placementMode = FSNIconPlacementModeAuto;
          [self occupyCell: cell withItemData: data];
          ai++;
        }
    }

  /* Any remaining AUTO icons that don't fit on the grid stay in place
   * but lose their grid position until the user resizes. */
  while (ai < [autoIcons count])
    {
      FSNIcon *icon = [autoIcons objectAtIndex: ai];
      FSNIconItemData *data = [icon placementData];
      data.hasGridPosition = NO;
      data.gridCell = FSNGridCellNone;
      ai++;
    }

  return autoIcons;
}

#pragma mark - Collision Resolution

- (void)resolveCollisionsForItems:(NSArray *)icons
{
  /* Collect all items that claim a grid cell, detect duplicates. */
  NSMutableDictionary *cellOwners = [NSMutableDictionary dictionary];
  NSMutableArray *colliders = [NSMutableArray array];
  NSUInteger i;

  for (i = 0; i < [icons count]; i++)
    {
      FSNIcon *icon = [icons objectAtIndex: i];
      FSNIconItemData *data = [icon placementData];

      if (!data.hasGridPosition || FSNGridCellsEqual(data.gridCell, FSNGridCellNone))
        continue;

      NSUInteger flat = [self flatIndexForCell: data.gridCell];
      NSNumber *key = [NSNumber numberWithUnsignedInteger: flat];
      FSNIconItemData *existing = [cellOwners objectForKey: key];

      if (existing == nil)
        {
          [cellOwners setObject: data forKey: key];
        }
      else
        {
          /* Collision! Keep the one with higher zOrder (or first-seen),
           * relocate the other. */
          if (data.zOrder > existing.zOrder)
            {
              /* New item wins, relocate the old one */
              [cellOwners setObject: data forKey: key];
              existing.hasGridPosition = NO;
              existing.gridCell = FSNGridCellNone;
              [colliders addObject: existing];
            }
          else
            {
              /* Old item stays, relocate the new one */
              data.hasGridPosition = NO;
              data.gridCell = FSNGridCellNone;
              [colliders addObject: data];
            }
        }
    }

  /* Rebuild occupancy from the resolved cellOwners */
  [_occupancyMap removeAllObjects];
  [_occupancyMap addEntriesFromDictionary: cellOwners];

  /* Relocate colliders to first free cells */
  for (i = 0; i < [colliders count]; i++)
    {
      FSNIconItemData *data = [colliders objectAtIndex: i];
      FSNGridCell freeCell;
      if ([self firstFreeCell: &freeCell])
        {
          data.gridCell = freeCell;
          data.hasGridPosition = YES;
          [self occupyCell: freeCell withItemData: data];
        }
    }
}

#pragma mark - Query

- (NSUInteger)colCount  { return _cols; }
- (NSUInteger)rowCount  { return _rows; }
- (NSUInteger)totalCells { return _cols * _rows; }
- (NSSize)cellSize       { return _cellSize; }
- (FSNPlacementDirection)direction { return _direction; }
- (FSNPlacementEnumerator *)enumerator { return _enumerator; }

@end
