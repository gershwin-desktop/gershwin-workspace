/*
 * FSNSelectionModel.m - which items of a file view are selected, and how
 * clicks, bands and keys change that.
 *
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

#import "FSNSelectionModel.h"

const NSTimeInterval FSNTypeSelectTimeout = 1.0;

/* How a band combines with what was selected when it began. */
enum {
  FSNBandReplace = 0,
  FSNBandToggle,
  FSNBandUnion
};

@interface FSNSelectionModel (Private)
- (NSUInteger)indexOfItem:(id)item;
- (void)sortSelection;
- (void)setAnchor:(id)anchor;
- (void)setCursor:(id)cursor;
- (void)setShiftRange:(NSArray *)range;
- (NSArray *)itemsFrom:(id)a to:(id)b;
- (void)applyRangeTo:(id)item;
- (NSArray *)itemsInNameOrder;
- (id)itemFrom:(id)item inDirection:(FSNSelectionDirection)direction;
@end

@implementation FSNSelectionModel

- (void)dealloc
{
  RELEASE(_items);
  RELEASE(_selected);
  RELEASE(_anchor);
  RELEASE(_cursor);
  RELEASE(_shiftRange);
  RELEASE(_pendingReduce);
  RELEASE(_bandBase);
  RELEASE(_typeBuffer);
  [super dealloc];
}

- (id)initWithStyle:(FSNSelectionStyle)style
{
  self = [super init];
  if (self)
    {
      _style = style;
      _items = [NSArray new];
      _selected = [NSMutableArray new];
    }
  return self;
}

- (FSNSelectionStyle)style
{
  return _style;
}

- (void)setStyle:(FSNSelectionStyle)style
{
  _style = style;
  [self setShiftRange: nil];
}

- (void)setDelegate:(id<FSNSelectionModelDelegate>)delegate
{
  _delegate = delegate;
}

- (id<FSNSelectionModelDelegate>)delegate
{
  return _delegate;
}

- (void)setItems:(NSArray *)items
{
  NSUInteger i;

  ASSIGNCOPY(_items, (items != nil) ? items : [NSArray array]);

  for (i = [_selected count]; i > 0; i--)
    {
      if ([self indexOfItem: [_selected objectAtIndex: i - 1]] == NSNotFound)
        [_selected removeObjectAtIndex: i - 1];
    }
  [self sortSelection];

  if (_anchor && [self indexOfItem: _anchor] == NSNotFound)
    [self setAnchor: nil];
  if (_cursor && [self indexOfItem: _cursor] == NSNotFound)
    [self setCursor: nil];
  if (_pendingReduce && [self indexOfItem: _pendingReduce] == NSNotFound)
    DESTROY(_pendingReduce);
  /* A range computed over the old order means nothing in the new one. */
  [self setShiftRange: nil];
}

- (NSArray *)items
{
  return _items;
}

- (void)setSelectedItems:(NSArray *)items
{
  NSUInteger i;
  BOOL same = YES;

  /* Views hand their selection over before every event; when it is what
     the model already has, the Shift range must survive it. */
  for (i = 0; same && i < [items count]; i++)
    same = [self isItemSelected: [items objectAtIndex: i]];
  if (same && [items count] == [_selected count])
    return;

  [_selected removeAllObjects];
  for (i = 0; i < [items count]; i++)
    {
      id item = [items objectAtIndex: i];

      if ([self indexOfItem: item] != NSNotFound
          && [_selected indexOfObjectIdenticalTo: item] == NSNotFound)
        [_selected addObject: item];
    }
  [self sortSelection];
  /* A selection made elsewhere is not the result of the last Shift-click,
     so that range must not be taken out of it again. */
  [self setShiftRange: nil];
}

- (NSArray *)selectedItems
{
  return [NSArray arrayWithArray: _selected];
}

- (BOOL)isItemSelected:(id)item
{
  return ([_selected indexOfObjectIdenticalTo: item] != NSNotFound);
}

- (id)anchor
{
  return _anchor;
}

- (id)cursor
{
  return _cursor;
}

- (void)selectOnly:(id)item
{
  [_selected removeAllObjects];
  if (item != nil && [self indexOfItem: item] != NSNotFound)
    [_selected addObject: item];
  [self setAnchor: item];
  [self setCursor: item];
  [self setShiftRange: nil];
}

#pragma mark - Mouse

- (void)mouseDownOnItem:(id)item modifiers:(unsigned)modifiers
{
  DESTROY(_pendingReduce);

  if (item == nil || [self indexOfItem: item] == NSNotFound)
    return;

  if (modifiers & FSNSelectionModifierControl)
    return;

  if (modifiers & FSNSelectionModifierCommand)
    {
      if ([self isItemSelected: item])
        [_selected removeObjectIdenticalTo: item];
      else
        [_selected addObject: item];
      [self sortSelection];
      /* Even a Command-click that deselects moves the anchor there: the
         reference's next Shift range starts from it. */
      [self setAnchor: item];
      [self setCursor: item];
      [self setShiftRange: nil];
      return;
    }

  if (modifiers & FSNSelectionModifierShift)
    {
      if (_style == FSNSelectionStyleIcon)
        {
          if ([self isItemSelected: item])
            [_selected removeObjectIdenticalTo: item];
          else
            [_selected addObject: item];
          [self sortSelection];
          [self setAnchor: item];
          [self setCursor: item];
        }
      else
        {
          [self applyRangeTo: item];
        }
      return;
    }

  /* Option-click is a plain click. */
  if ([self isItemSelected: item] && [_selected count] > 1)
    {
      /* Keep the whole selection so it can be dragged; a list gives it up
         when the button comes up without a drag. */
      if (_style == FSNSelectionStyleList)
        ASSIGN(_pendingReduce, item);
      [self setAnchor: item];
      [self setCursor: item];
      [self setShiftRange: nil];
      return;
    }

  [self selectOnly: item];
}

- (void)mouseUpOnItem:(id)item dragged:(BOOL)dragged
{
  if (_pendingReduce != nil && _pendingReduce == item && dragged == NO)
    [self selectOnly: item];
  DESTROY(_pendingReduce);
}

- (void)mouseDownOnEmptySpaceWithModifiers:(unsigned)modifiers
{
  DESTROY(_pendingReduce);
  if (modifiers & (FSNSelectionModifierShift | FSNSelectionModifierCommand))
    return;
  [self deselectAllItems];
}

- (void)beginBandWithModifiers:(unsigned)modifiers
{
  ASSIGN(_bandBase, [NSArray arrayWithArray: _selected]);

  if ((modifiers & (FSNSelectionModifierShift | FSNSelectionModifierCommand)) == 0)
    _bandMode = FSNBandReplace;
  else if (_style == FSNSelectionStyleIcon)
    _bandMode = FSNBandToggle;
  else
    _bandMode = FSNBandUnion;
  [self setShiftRange: nil];
}

- (void)updateBandWithItems:(NSArray *)items
{
  NSMutableArray *sel;
  NSUInteger i;

  if (_bandBase == nil)
    return;

  sel = [NSMutableArray array];
  if (_bandMode != FSNBandReplace)
    [sel addObjectsFromArray: _bandBase];

  for (i = 0; i < [items count]; i++)
    {
      id item = [items objectAtIndex: i];
      NSUInteger at = [sel indexOfObjectIdenticalTo: item];

      if ([self indexOfItem: item] == NSNotFound)
        continue;
      if (at == NSNotFound)
        [sel addObject: item];
      else if (_bandMode == FSNBandToggle && [_bandBase indexOfObjectIdenticalTo: item] != NSNotFound)
        [sel removeObjectAtIndex: at];
    }

  [_selected setArray: sel];
  [self sortSelection];
}

- (void)endBand
{
  DESTROY(_bandBase);
  /* The next arrow key starts from what the band left selected. */
  if ([_selected count] > 0)
    {
      [self setCursor: [_selected lastObject]];
      if (_anchor == nil || [self isItemSelected: _anchor] == NO)
        [self setAnchor: [_selected objectAtIndex: 0]];
    }
}

#pragma mark - Keys

- (BOOL)moveInDirection:(FSNSelectionDirection)direction extend:(BOOL)extend
{
  id from = _cursor;
  id target;

  if ([_items count] == 0)
    return NO;

  if (from == nil && [_selected count] > 0)
    {
      from = (direction == FSNSelectionDirectionUp || direction == FSNSelectionDirectionLeft)
        ? [_selected objectAtIndex: 0] : [_selected lastObject];
    }

  if (from == nil)
    {
      /* The reference selects the first item with Down and the last one
         with every other arrow. */
      target = (direction == FSNSelectionDirectionDown)
        ? [_items objectAtIndex: 0] : [_items lastObject];
      [self selectOnly: target];
      return YES;
    }

  target = [self itemFrom: from inDirection: direction];

  if (target == nil)
    {
      /* At an edge a plain arrow still collapses a multiple selection
         onto the item it would move from. */
      if (extend == NO && ([_selected count] != 1 || [self isItemSelected: from] == NO))
        {
          [self selectOnly: from];
          return YES;
        }
      return NO;
    }

  if (extend == NO)
    {
      [self selectOnly: target];
      return YES;
    }

  if (_style == FSNSelectionStyleIcon)
    {
      /* An icon view only ever adds the item moved to. */
      if ([self isItemSelected: target] == NO)
        {
          [_selected addObject: target];
          [self sortSelection];
        }
      [self setCursor: target];
      return YES;
    }

  if (_anchor == nil)
    [self setAnchor: from];
  if (_shiftRange == nil && [self isItemSelected: from])
    {
      /* The range we are about to replace starts as what the anchor
         already covers, so moving back gives the rows up again. */
      [self setShiftRange: [self itemsFrom: _anchor to: from]];
    }
  [self applyRangeTo: target];
  return YES;
}

- (BOOL)selectFirstItem
{
  if ([_items count] == 0)
    return NO;
  [self selectOnly: [_items objectAtIndex: 0]];
  return YES;
}

- (BOOL)selectLastItem
{
  if ([_items count] == 0)
    return NO;
  [self selectOnly: [_items lastObject]];
  return YES;
}

- (BOOL)typeSelect:(NSString *)characters atTime:(NSTimeInterval)time
{
  NSArray *ordered;
  NSString *prefix;
  NSUInteger i;
  id found = nil;

  if ([characters length] == 0 || [_items count] == 0)
    return NO;

  if (_typeBuffer != nil && (time - _lastTypeTime) < FSNTypeSelectTimeout)
    prefix = [_typeBuffer stringByAppendingString: characters];
  else
    prefix = characters;
  ASSIGN(_typeBuffer, prefix);
  _lastTypeTime = time;

  ordered = [self itemsInNameOrder];

  for (i = 0; i < [ordered count]; i++)
    {
      id item = [ordered objectAtIndex: i];
      NSString *name = [_delegate selectionModel: self nameOfItem: item];

      if ([name rangeOfString: prefix
                      options: (NSCaseInsensitiveSearch | NSAnchoredSearch)].location == 0)
        {
          found = item;
          break;
        }
      /* Without a match the reference lands on the name that would follow
         the typed text. */
      if ([name caseInsensitiveCompare: prefix] == NSOrderedDescending)
        {
          found = item;
          break;
        }
    }

  if (found == nil)
    found = [ordered lastObject];

  [self selectOnly: found];
  return YES;
}

- (void)resetTypeSelect
{
  DESTROY(_typeBuffer);
  _lastTypeTime = 0;
}

- (BOOL)selectNextInNameOrder:(BOOL)forward
{
  NSArray *ordered = [self itemsInNameOrder];
  NSUInteger count = [ordered count];
  id from = _cursor;
  NSUInteger at;

  if (count == 0)
    return NO;

  if (from == nil && [_selected count] > 0)
    from = [_selected lastObject];

  if (from == nil)
    {
      [self selectOnly: forward ? [ordered objectAtIndex: 0] : [ordered lastObject]];
      return YES;
    }

  at = [ordered indexOfObjectIdenticalTo: from];
  if (forward && at + 1 < count)
    at++;
  else if (forward == NO && at > 0)
    at--;
  [self selectOnly: [ordered objectAtIndex: at]];
  return YES;
}

- (BOOL)selectAllItems
{
  if ([_selected count] == [_items count])
    return NO;
  [_selected setArray: _items];
  [self setShiftRange: nil];
  return YES;
}

- (BOOL)deselectAllItems
{
  BOOL changed = ([_selected count] > 0);

  [_selected removeAllObjects];
  [self setAnchor: nil];
  [self setCursor: nil];
  [self setShiftRange: nil];
  return changed;
}

#pragma mark - Geometry

+ (NSUInteger)indexOfNeighborOfRect:(NSUInteger)index
                            inRects:(const NSRect *)rects
                              count:(NSUInteger)count
                          direction:(FSNSelectionDirection)direction
                            flipped:(BOOL)flipped
{
  NSRect from;
  NSUInteger best = NSNotFound;
  CGFloat bestDistance = 0;
  NSUInteger i;
  BOOL horizontal = (direction == FSNSelectionDirectionLeft
                     || direction == FSNSelectionDirectionRight);
  /* +1 when the neighbor must lie toward larger coordinates. */
  int sign;

  if (index >= count)
    return NSNotFound;

  if (horizontal)
    sign = (direction == FSNSelectionDirectionRight) ? 1 : -1;
  else
    sign = ((direction == FSNSelectionDirectionDown) == flipped) ? 1 : -1;

  from = rects[index];

  for (i = 0; i < count; i++)
    {
      NSRect r = rects[i];
      CGFloat delta;
      BOOL inLine;

      if (i == index)
        continue;

      if (horizontal)
        {
          inLine = (NSMaxY(r) > NSMinY(from) && NSMinY(r) < NSMaxY(from));
          delta = NSMidX(r) - NSMidX(from);
        }
      else
        {
          inLine = (NSMaxX(r) > NSMinX(from) && NSMinX(r) < NSMaxX(from));
          delta = NSMidY(r) - NSMidY(from);
        }

      if (inLine == NO || delta * sign <= 0)
        continue;

      if (best == NSNotFound || delta * sign < bestDistance)
        {
          best = i;
          bestDistance = delta * sign;
        }
    }

  return best;
}

@end

@implementation FSNSelectionModel (Private)

- (NSUInteger)indexOfItem:(id)item
{
  return [_items indexOfObjectIdenticalTo: item];
}

- (void)sortSelection
{
  NSMutableArray *sorted = [NSMutableArray arrayWithCapacity: [_selected count]];
  NSUInteger i;

  if ([_selected count] < 2)
    return;
  for (i = 0; i < [_items count]; i++)
    {
      id item = [_items objectAtIndex: i];

      if ([_selected indexOfObjectIdenticalTo: item] != NSNotFound)
        [sorted addObject: item];
    }
  [_selected setArray: sorted];
}

- (void)setAnchor:(id)anchor
{
  ASSIGN(_anchor, anchor);
}

- (void)setCursor:(id)cursor
{
  ASSIGN(_cursor, cursor);
}

- (void)setShiftRange:(NSArray *)range
{
  ASSIGN(_shiftRange, range);
}

- (NSArray *)itemsFrom:(id)a to:(id)b
{
  NSUInteger ia = [self indexOfItem: a];
  NSUInteger ib = [self indexOfItem: b];
  NSUInteger lo, hi;

  if (ia == NSNotFound || ib == NSNotFound)
    return [NSArray array];
  lo = MIN(ia, ib);
  hi = MAX(ia, ib);
  return [_items subarrayWithRange: NSMakeRange(lo, hi - lo + 1)];
}

/* Shift in a list: the range from the anchor to "item" replaces the range
   the previous Shift step added; everything else stays selected. */
- (void)applyRangeTo:(id)item
{
  NSArray *range;
  NSUInteger i;

  if (_anchor == nil || [self indexOfItem: _anchor] == NSNotFound)
    [self setAnchor: [_items objectAtIndex: 0]];

  range = [self itemsFrom: _anchor to: item];

  for (i = 0; i < [_shiftRange count]; i++)
    [_selected removeObjectIdenticalTo: [_shiftRange objectAtIndex: i]];
  for (i = 0; i < [range count]; i++)
    {
      id r = [range objectAtIndex: i];

      if ([_selected indexOfObjectIdenticalTo: r] == NSNotFound)
        [_selected addObject: r];
    }
  [self sortSelection];
  [self setShiftRange: range];
  [self setCursor: item];
}

- (NSArray *)itemsInNameOrder
{
  NSMutableArray *pairs = [NSMutableArray arrayWithCapacity: [_items count]];
  NSMutableArray *ordered = [NSMutableArray arrayWithCapacity: [_items count]];
  NSUInteger i;

  for (i = 0; i < [_items count]; i++)
    {
      id item = [_items objectAtIndex: i];
      NSString *name = [_delegate selectionModel: self nameOfItem: item];

      [pairs addObject: [NSArray arrayWithObjects: (name ? name : @""), item, nil]];
    }
  [pairs sortUsingComparator: ^NSComparisonResult(id a, id b) {
    return [[a objectAtIndex: 0] caseInsensitiveCompare: [b objectAtIndex: 0]];
  }];
  for (i = 0; i < [pairs count]; i++)
    [ordered addObject: [[pairs objectAtIndex: i] objectAtIndex: 1]];
  return ordered;
}

- (id)itemFrom:(id)item inDirection:(FSNSelectionDirection)direction
{
  NSUInteger at;

  if ([_delegate respondsToSelector: @selector(selectionModel:itemFrom:inDirection:)])
    return [_delegate selectionModel: self itemFrom: item inDirection: direction];

  at = [self indexOfItem: item];
  if (at == NSNotFound)
    return nil;
  if (direction == FSNSelectionDirectionUp || direction == FSNSelectionDirectionLeft)
    return (at > 0) ? [_items objectAtIndex: at - 1] : nil;
  return (at + 1 < [_items count]) ? [_items objectAtIndex: at + 1] : nil;
}

@end
