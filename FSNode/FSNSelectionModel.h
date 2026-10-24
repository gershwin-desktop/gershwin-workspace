/*
 * FSNSelectionModel.h - which items of a file view are selected, and how
 * clicks, bands and keys change that.
 *
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

#ifndef FSN_SELECTION_MODEL_H
#define FSN_SELECTION_MODEL_H

#import <Foundation/Foundation.h>

/* Icon views and the desktop toggle single items with Shift; list and
 * column views select ranges with it. Everything else is shared. */
typedef enum {
  FSNSelectionStyleIcon = 0,
  FSNSelectionStyleList = 1
} FSNSelectionStyle;

/* Kept free of AppKit so the model can be tested headless; views map their
 * event modifier flags onto these (FSNSelectionModifiersFromEventFlags in
 * FSNFunctions does that for NSEvent flags). */
enum {
  FSNSelectionModifierNone = 0,
  FSNSelectionModifierShift = 1 << 0,
  FSNSelectionModifierCommand = 1 << 1,
  FSNSelectionModifierOption = 1 << 2,
  FSNSelectionModifierControl = 1 << 3
};

typedef enum {
  FSNSelectionDirectionUp = 0,
  FSNSelectionDirectionDown,
  FSNSelectionDirectionLeft,
  FSNSelectionDirectionRight
} FSNSelectionDirection;

/* Keystrokes closer together than this extend the type-select prefix. */
extern const NSTimeInterval FSNTypeSelectTimeout;

@class FSNSelectionModel;

@protocol FSNSelectionModelDelegate <NSObject>
/* The name type-select and Tab compare against. */
- (NSString *)selectionModel:(FSNSelectionModel *)model nameOfItem:(id)item;
@optional
/* The item an arrow key moves to from "item", nil at an edge. Without this
 * the model walks its item order: Up and Left go back, Down and Right go
 * forward. */
- (id)selectionModel:(FSNSelectionModel *)model
            itemFrom:(id)item
         inDirection:(FSNSelectionDirection)direction;
@end

@interface FSNSelectionModel : NSObject
{
  FSNSelectionStyle _style;
  id<FSNSelectionModelDelegate> _delegate;
  NSArray *_items;
  NSMutableArray *_selected;
  id _anchor;
  id _cursor;
  NSArray *_shiftRange;
  id _pendingReduce;
  NSArray *_bandBase;
  int _bandMode;
  NSString *_typeBuffer;
  NSTimeInterval _lastTypeTime;
}

- (id)initWithStyle:(FSNSelectionStyle)style;

- (FSNSelectionStyle)style;
- (void)setStyle:(FSNSelectionStyle)style;

/* Not retained: the view that owns the model is its delegate. */
- (void)setDelegate:(id<FSNSelectionModelDelegate>)delegate;
- (id<FSNSelectionModelDelegate>)delegate;

/* The items in the order the view shows them. Items are compared by
 * identity. Selected items, the anchor and the cursor that are no longer
 * among them are dropped. */
- (void)setItems:(NSArray *)items;
- (NSArray *)items;

/* Takes over a selection the view made itself (restored after Back, picked
 * by a menu command, ...). The anchor and the cursor survive as long as
 * they are still items. */
- (void)setSelectedItems:(NSArray *)items;

/* In item order. */
- (NSArray *)selectedItems;
- (BOOL)isItemSelected:(id)item;

/* Where a Shift range starts from, and where arrow keys move from. */
- (id)anchor;
- (id)cursor;

/* The mouse goes down on an item. With Control nothing changes: the
 * context menu acts on the item or the selection without touching it. */
- (void)mouseDownOnItem:(id)item modifiers:(unsigned)modifiers;

/* The press ends; "dragged" when it became a drag. A plain click on an
 * item of a multiple selection reduces a list selection to that item only
 * now, so the whole selection can still be dragged. */
- (void)mouseUpOnItem:(id)item dragged:(BOOL)dragged;

/* The mouse goes down where there is no item. Without Shift or Command
 * that clears the selection; with them a band will follow. */
- (void)mouseDownOnEmptySpaceWithModifiers:(unsigned)modifiers;

/* A rubber band. Every update gives all the items it touches now, and the
 * selection follows at once. */
- (void)beginBandWithModifiers:(unsigned)modifiers;
- (void)updateBandWithItems:(NSArray *)items;
- (void)endBand;

/* Arrow keys. "extend" is Shift. Returns NO when nothing changed. */
- (BOOL)moveInDirection:(FSNSelectionDirection)direction extend:(BOOL)extend;

/* Option-Up and Option-Down in a list. */
- (BOOL)selectFirstItem;
- (BOOL)selectLastItem;

/* Typed characters select the first item whose name starts with all the
 * characters typed less than FSNTypeSelectTimeout apart, ignoring case;
 * without such an item the one that follows them in name order. */
- (BOOL)typeSelect:(NSString *)characters atTime:(NSTimeInterval)time;
- (void)resetTypeSelect;

/* Tab and Shift-Tab: the next or previous item in name order. */
- (BOOL)selectNextInNameOrder:(BOOL)forward;

- (BOOL)selectAll;
- (BOOL)deselectAll;

/* Makes "item" the only selected item, the anchor and the cursor. */
- (void)selectOnly:(id)item;

/* The neighbor of rects[index] in "direction" among "count" item rects,
 * or NSNotFound. Only items in the same row (Left, Right) or the same
 * column (Up, Down) count, so moving never wraps; rows and columns are
 * matched by overlapping rects. "flipped" is the view's -isFlipped. */
+ (NSUInteger)indexOfNeighborOfRect:(NSUInteger)index
                            inRects:(const NSRect *)rects
                              count:(NSUInteger)count
                          direction:(FSNSelectionDirection)direction
                            flipped:(BOOL)flipped;

@end

#endif
