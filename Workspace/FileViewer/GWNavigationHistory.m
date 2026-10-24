/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

#import "GWNavigationHistory.h"

const NSInteger GWNavigationHistoryDefaultLimit = 20;
const NSInteger GWNavigationHistoryMinimumLimit = 4;

NSInteger GWNavigationHistoryLimitFromDefault(id storedValue)
{
  if ([storedValue respondsToSelector:@selector(integerValue)]
      && [storedValue integerValue] >= GWNavigationHistoryMinimumLimit)
    return [storedValue integerValue];
  return GWNavigationHistoryDefaultLimit;
}

static BOOL itemIsValid(id item)
{
  if ([item respondsToSelector:@selector(isValid)])
    return [item isValid];
  return YES;
}

@implementation GWNavigationHistory

- (id)init
{
  self = [super init];
  if (self) {
    _items = [NSMutableArray new];
    _position = 0;
  }
  return self;
}

- (void)dealloc
{
  [_items release];
  [super dealloc];
}

- (NSMutableArray *)items
{
  return _items;
}

- (NSInteger)position
{
  return _position;
}

- (void)setPosition:(NSInteger)position
{
  _position = position;
}

- (id)currentItem
{
  if (_position >= 0 && (NSUInteger)_position < [_items count])
    return [_items objectAtIndex:_position];
  return nil;
}

- (void)addItem:(id)item maxCount:(NSUInteger)maxCount
{
  NSUInteger count;

  if (item == nil)
    return;

  while ([_items count] > maxCount) {
    [_items removeObjectAtIndex:0];
    if (_position > 0)
      _position--;
  }

  count = [_items count];

  if (count == 0) {
    [_items addObject:item];
    _position = 0;
  }
  else if ((NSUInteger)_position >= count - 1) {
    if ([[_items lastObject] isEqual:item] == NO)
      [_items addObject:item];
    _position = [_items count] - 1;
  }
  else if ([[_items objectAtIndex:_position] isEqual:item]) {
    /* Shown again (a reload, a selection in the same folder). */
  }
  else if ([[_items objectAtIndex:_position + 1] isEqual:item]) {
    /* Opening the folder Forward would show is the same as Forward, so
     * the folders beyond it stay reachable. */
    _position++;
  }
  else {
    /* A new way out of the middle replaces the forward branch, as in any
     * browser. */
    [_items removeObjectsInRange:NSMakeRange(_position + 1, count - _position - 1)];
    [_items addObject:item];
    _position = [_items count] - 1;
  }

  [self compact];
}

- (BOOL)canGoBack
{
  NSInteger i;

  for (i = _position - 1; i >= 0; i--) {
    if (itemIsValid([_items objectAtIndex:i]))
      return YES;
  }
  return NO;
}

- (BOOL)canGoForward
{
  NSInteger i;
  NSInteger count = [_items count];

  for (i = _position + 1; i < count; i++) {
    if (itemIsValid([_items objectAtIndex:i]))
      return YES;
  }
  return NO;
}

- (NSInteger)positionAfterStep:(NSInteger)step
{
  NSInteger target;

  [self compact];
  target = _position + step;
  if ([_items count] == 0 || target < 0 || target >= (NSInteger)[_items count])
    return NSNotFound;
  return target;
}

- (void)compact
{
  NSInteger i;

  /* Vanished folders: when the current one is among them, the item after
   * it becomes current, which the clamp below keeps in range. */
  for (i = (NSInteger)[_items count] - 1; i >= 0; i--) {
    if (itemIsValid([_items objectAtIndex:i]) == NO) {
      [_items removeObjectAtIndex:i];
      if (i < _position)
        _position--;
    }
  }

  /* Removing a vanished folder can leave the same folder twice in a row. */
  for (i = (NSInteger)[_items count] - 1; i > 0; i--) {
    if ([[_items objectAtIndex:i] isEqual:[_items objectAtIndex:i - 1]]) {
      [_items removeObjectAtIndex:i];
      if (i <= _position)
        _position--;
    }
  }

  /* Going back and forth between two folders: A B A B collapses to A B, so
   * Back does not walk through the same pair again and again.  A current
   * item in the removed pair maps onto the same folder in the kept one. */
  i = 0;
  while (i + 3 < (NSInteger)[_items count]) {
    if ([[_items objectAtIndex:i] isEqual:[_items objectAtIndex:i + 2]] &&
        [[_items objectAtIndex:i + 1] isEqual:[_items objectAtIndex:i + 3]]) {
      [_items removeObjectsInRange:NSMakeRange(i + 2, 2)];
      if (_position >= i + 2)
        _position -= 2;
    }
    else {
      i++;
    }
  }

  if (_position >= (NSInteger)[_items count])
    _position = (NSInteger)[_items count] - 1;
  if (_position < 0)
    _position = 0;
}

- (void)removeAllItems
{
  [_items removeAllObjects];
  _position = 0;
}

@end
