/* FSNListRowModel.m - the rows of a list view with folders expanded inline.
 *
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-2.0-or-later
 */

#import "FSNListRowModel.h"
#include <math.h>

/* Measured on the reference list view (16 point icons, 19 point rows). */
#define DISCLOSURE_COLUMN_WIDTH (26.0)
#define INDENT_PER_LEVEL (21.0)
#define DISCLOSURE_X (8.0)
#define DISCLOSURE_SIZE (9.0)

CGFloat FSNListIconXForDepth (NSUInteger depth)
{
  return DISCLOSURE_COLUMN_WIDTH + INDENT_PER_LEVEL * depth;
}

NSRect FSNListDisclosureRectForDepth (NSUInteger depth, CGFloat rowHeight)
{
  /* The reference puts the triangle a point above the row's middle, level
   * with the middle of the lower case letters rather than of the row. */
  CGFloat y = floor ((rowHeight - DISCLOSURE_SIZE) / 2.0) - 1.0;

  return NSMakeRect (DISCLOSURE_X + INDENT_PER_LEVEL * depth, y,
                     DISCLOSURE_SIZE, DISCLOSURE_SIZE);
}

NSRect FSNListDisclosureHitRectForDepth (NSUInteger depth, CGFloat rowHeight)
{
  /* The triangle alone is a small target; the whole space in front of the
   * icon belongs to it. */
  return NSMakeRect (INDENT_PER_LEVEL * depth, 0,
                     DISCLOSURE_COLUMN_WIDTH - 1.0, rowHeight);
}


@implementation FSNListRowModel

- (id)initWithKeyOfItem:(NSString *(^)(id item))block
{
  self = [super init];
  if (self)
    {
      keyOfItem = [block copy];
      children = [NSMutableDictionary new];
      parents = [NSMutableDictionary new];
      expanded = [NSMutableSet new];
      rows = [NSMutableArray new];
      depths = [NSMutableArray new];
      rowIndex = [NSMutableDictionary new];
    }
  return self;
}

- (void)dealloc
{
  [keyOfItem release];
  [rootKey release];
  [children release];
  [parents release];
  [expanded release];
  [rows release];
  [depths release];
  [rowIndex release];
  [super dealloc];
}

- (void)resetWithRootKey:(NSString *)key keepExpanded:(BOOL)keep
{
  if (keep == NO)
    {
      [expanded removeAllObjects];
    }
  [children removeAllObjects];
  [parents removeAllObjects];
  [rows removeAllObjects];
  [depths removeAllObjects];
  [rowIndex removeAllObjects];
  [rootKey release];
  rootKey = [key copy];
}

- (NSString *)rootKey
{
  return rootKey;
}

- (void)forgetChildrenOfKey:(NSString *)key
{
  NSArray *items = [children objectForKey: key];
  NSUInteger i;

  for (i = 0; i < [items count]; i++)
    {
      NSString *itemKey = keyOfItem ([items objectAtIndex: i]);

      [self forgetChildrenOfKey: itemKey];
      [parents removeObjectForKey: itemKey];
      [expanded removeObject: itemKey];
    }
  [children removeObjectForKey: key];
}

- (void)setChildren:(NSArray *)items ofKey:(NSString *)key
{
  NSArray *old = [children objectForKey: key];
  NSMutableSet *kept = [NSMutableSet set];
  NSUInteger i;

  for (i = 0; i < [items count]; i++)
    {
      NSString *itemKey = keyOfItem ([items objectAtIndex: i]);

      [kept addObject: itemKey];
      [parents setObject: key forKey: itemKey];
    }
  /* What is not listed any more takes its own items with it. */
  for (i = 0; i < [old count]; i++)
    {
      NSString *itemKey = keyOfItem ([old objectAtIndex: i]);

      if ([kept containsObject: itemKey] == NO)
        {
          [self forgetChildrenOfKey: itemKey];
          [parents removeObjectForKey: itemKey];
          [expanded removeObject: itemKey];
        }
    }
  [children setObject: [NSMutableArray arrayWithArray: items] forKey: key];
}

- (NSArray *)childrenOfKey:(NSString *)key
{
  return [children objectForKey: key];
}

- (NSUInteger)indexOfKey:(NSString *)key inItems:(NSArray *)items
{
  NSUInteger i;

  for (i = 0; i < [items count]; i++)
    {
      if ([keyOfItem ([items objectAtIndex: i]) isEqual: key])
        {
          return i;
        }
    }
  return NSNotFound;
}

- (void)addChild:(id)item toKey:(NSString *)key
{
  NSMutableArray *items = [children objectForKey: key];
  NSString *itemKey = keyOfItem (item);
  NSUInteger index;

  if (items == nil)
    {
      items = [NSMutableArray array];
      [children setObject: items forKey: key];
    }
  index = [self indexOfKey: itemKey inItems: items];
  if (index != NSNotFound)
    {
      [items replaceObjectAtIndex: index withObject: item];
    }
  else
    {
      [items addObject: item];
    }
  [parents setObject: key forKey: itemKey];
}

- (id)removeItemWithKey:(NSString *)key
{
  NSString *parentKey = [parents objectForKey: key];
  NSMutableArray *items = parentKey ? [children objectForKey: parentKey] : nil;
  NSUInteger index = [self indexOfKey: key inItems: items];
  id item;

  if (index == NSNotFound)
    {
      return nil;
    }
  item = [[[items objectAtIndex: index] retain] autorelease];
  [items removeObjectAtIndex: index];
  [self forgetChildrenOfKey: key];
  [parents removeObjectForKey: key];
  [expanded removeObject: key];
  return item;
}

- (id)itemWithKey:(NSString *)key
{
  NSString *parentKey = [parents objectForKey: key];
  NSArray *items = parentKey ? [children objectForKey: parentKey] : nil;
  NSUInteger index = [self indexOfKey: key inItems: items];

  return (index == NSNotFound) ? nil : [items objectAtIndex: index];
}

- (NSString *)parentKeyOfKey:(NSString *)key
{
  return [parents objectForKey: key];
}

- (void)setExpanded:(BOOL)flag forKey:(NSString *)key
{
  if (flag)
    {
      [expanded addObject: key];
    }
  else
    {
      [expanded removeObject: key];
    }
}

- (BOOL)isExpanded:(NSString *)key
{
  return [expanded containsObject: key];
}

- (void)collectVisibleExpandedUnder:(NSString *)key into:(NSMutableArray *)result
{
  NSArray *items = [children objectForKey: key];
  NSUInteger i;

  for (i = 0; i < [items count]; i++)
    {
      NSString *itemKey = keyOfItem ([items objectAtIndex: i]);

      if ([expanded containsObject: itemKey])
        {
          [result addObject: itemKey];
          [self collectVisibleExpandedUnder: itemKey into: result];
        }
    }
}

- (NSArray *)visibleExpandedKeys
{
  NSMutableArray *result = [NSMutableArray array];

  if (rootKey != nil)
    {
      [self collectVisibleExpandedUnder: rootKey into: result];
    }
  return result;
}

- (void)sortUsingComparator:(NSComparator)cmp
{
  NSEnumerator *e = [children objectEnumerator];
  NSMutableArray *items;

  while ((items = [e nextObject]) != nil)
    {
      [items sortUsingComparator: cmp];
    }
}

- (void)appendRowsUnder:(NSString *)key depth:(NSUInteger)depth
{
  NSArray *items = [children objectForKey: key];
  NSNumber *depthNumber = [NSNumber numberWithUnsignedInteger: depth];
  NSUInteger i;

  for (i = 0; i < [items count]; i++)
    {
      id item = [items objectAtIndex: i];
      NSString *itemKey = keyOfItem (item);

      [rowIndex setObject: [NSNumber numberWithUnsignedInteger: [rows count]]
                   forKey: itemKey];
      [rows addObject: item];
      [depths addObject: depthNumber];
      if ([expanded containsObject: itemKey])
        {
          [self appendRowsUnder: itemKey depth: depth + 1];
        }
    }
}

- (void)rebuildRows
{
  [rows removeAllObjects];
  [depths removeAllObjects];
  [rowIndex removeAllObjects];
  if (rootKey != nil)
    {
      [self appendRowsUnder: rootKey depth: 0];
    }
}

- (NSArray *)rows
{
  return rows;
}

- (NSUInteger)depthOfRow:(NSUInteger)row
{
  return [[depths objectAtIndex: row] unsignedIntegerValue];
}

- (NSUInteger)rowOfKey:(NSString *)key
{
  NSNumber *row = [rowIndex objectForKey: key];

  return row ? [row unsignedIntegerValue] : NSNotFound;
}

@end
