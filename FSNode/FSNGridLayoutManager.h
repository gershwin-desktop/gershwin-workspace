/* FSNGridLayoutManager.h
 *
 * Imaginary grid system for icon layout positioning.
 * Computes best-fit grid cells from raw DS_Store icon coordinate data
 * using configurable spacing, margins, and alignment thresholds.
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

#ifndef FSN_GRID_LAYOUT_MANAGER_H
#define FSN_GRID_LAYOUT_MANAGER_H

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import "FSNIconPlacement.h"
#import "FSNodeRep.h"

@class FSNPlacementEnumerator;
@class FSNIcon;

/* -----------------------------------------------------------------------
 * FSNIconItemData — per-icon persistent placement state.
 *
 * Each FSNIcon owns one of these.  The grid layout manager reads/writes
 * the grid cell and placement mode to decide where to put the icon.
 * --------------------------------------------------------------------- */
@interface FSNIconItemData : NSObject <NSCopying>
{
  NSString *_itemID;
  NSString *_filename;
  FSNIconPlacementMode _placementMode;
  NSPoint _pixelPosition;
  NSPoint _ilocPosition;      /* raw DS_Store coords (top-left origin), for tile-time conversion */
  FSNGridCell _gridCell;
  NSUInteger _zOrder;
  BOOL _hasGridPosition;
}

@property (nonatomic, retain) NSString *itemID;
@property (nonatomic, retain) NSString *filename;
@property (nonatomic) FSNIconPlacementMode placementMode;
@property (nonatomic) NSPoint pixelPosition;
@property (nonatomic) NSPoint ilocPosition;
@property (nonatomic) FSNGridCell gridCell;
@property (nonatomic) NSUInteger zOrder;
@property (nonatomic) BOOL hasGridPosition;

@end

/* -----------------------------------------------------------------------
 * FSNGridLayoutManager — central icon grid layout engine.
 *
 * Owns:
 *   • Grid geometry (columns, rows, cell size, origin)
 *   • Occupancy map (cell → FSNIconItemData, O(1) dictionary lookup)
 *   • Placement enumerator (direction-aware cell iteration)
 *
 * Does NOT own the icon views; it reads/writes their FSNIconItemData.
 * --------------------------------------------------------------------- */
@interface FSNGridLayoutManager : NSObject
{
  /* Grid geometry */
  NSSize _cellSize;
  NSUInteger _cols;
  NSUInteger _rows;
  CGFloat _xMargin;
  CGFloat _yMargin;
  NSPoint _gridOrigin;        /* top-left of grid in view coords */

  /* Occupancy map: key = NSNumber(flatCellIndex), value = FSNIconItemData */
  NSMutableDictionary *_occupancyMap;

  /* Placement direction */
  FSNPlacementDirection _direction;
  FSNPlacementEnumerator *_enumerator;

  /* Container reference (for coordinate conversion context) */
  NSView *_container;

  /* Recalc state tracking */
  CGFloat _lastIconSize;
  CGFloat _lastLabelHeight;
  int _lastLabelMargin;
  FSNInfoType _lastInfoType;
  NSCellImagePosition _lastIconPosition;
  NSSize _lastViewSize;
  CGFloat _lastGridSpacing;
  BOOL _needsRecalc;
}

/* Designated initializer */
- (instancetype)initWithContainer:(NSView *)container;

/* -------------------------------------------------------------------
 * Geometry recalculation.
 * Must be called whenever icon size, label font, view size, or
 * placement direction changes.
 * ----------------------------------------------------------------- */
- (void)recalcWithIconSize:(CGFloat)icSize
                labelHeight:(CGFloat)lblHeight
               labelMargin:(int)lblMargin
                  infoType:(FSNInfoType)infoType
             iconPosition:(NSCellImagePosition)icnPos
                 viewSize:(NSSize)vSize
               direction:(FSNPlacementDirection)dir
                 xMargin:(CGFloat)xm
                 yMargin:(CGFloat)ym
              gridSpacing:(CGFloat)spacing;

/* Override grid origin (used by desktop for dock/screen adjustments) */
- (void)setGridOrigin:(NSPoint)origin;
- (NSPoint)gridOrigin;

/* -------------------------------------------------------------------
 * Occupancy.
 * ----------------------------------------------------------------- */
- (void)clearOccupancy;
- (void)occupyCell:(FSNGridCell)cell withItemData:(FSNIconItemData *)item;
- (void)vacateCell:(FSNGridCell)cell;
- (BOOL)isCellOccupied:(FSNGridCell)cell;
- (FSNIconItemData *)itemDataAtCell:(FSNGridCell)cell;

/* -------------------------------------------------------------------
 * First free cell — scans the grid using the placement enumerator and
 * returns the first unoccupied cell.  Returns NO if grid is full.
 * ----------------------------------------------------------------- */
- (BOOL)firstFreeCell:(FSNGridCell *)cellOut;

/* -------------------------------------------------------------------
 * Coordinate conversion.
 * ----------------------------------------------------------------- */
- (NSPoint)originForCell:(FSNGridCell)cell;       /* cell → pixel origin */
- (NSUInteger)flatIndexForCell:(FSNGridCell)cell; /* (col,row) → flat 0..N-1 */
- (FSNGridCell)cellForFlatIndex:(NSUInteger)index;/* flat → (col,row) */
- (FSNGridCell)cellForPoint:(NSPoint)point;       /* snap point → nearest cell */

/* -------------------------------------------------------------------
 * Cleanup — sort AUTO items by placement order, repack into
 * consecutive cells (0, 1, 2, ...).  MANUAL and LOCKED items are
 * left in place.  Returns the ordered list of AUTO items for the
 * caller to update icon frames.
 * ----------------------------------------------------------------- */
- (NSArray *)cleanupAutoItems:(NSArray *)icons;

/* -------------------------------------------------------------------
 * Collision resolution — after grid resize, some cells may have
 * multiple icons claimed.  Keep the first (by zOrder), relocate
 * the rest using first-free-cell search.
 * ----------------------------------------------------------------- */
- (void)resolveCollisionsForItems:(NSArray *)icons;

/* -------------------------------------------------------------------
 * Query.
 * ----------------------------------------------------------------- */
- (NSUInteger)colCount;
- (NSUInteger)rowCount;
- (NSUInteger)totalCells;
- (NSSize)cellSize;
- (FSNPlacementDirection)direction;
- (FSNPlacementEnumerator *)enumerator;

@end

#endif /* FSN_GRID_LAYOUT_MANAGER_H */
