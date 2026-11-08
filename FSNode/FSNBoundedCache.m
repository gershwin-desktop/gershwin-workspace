/*
 * FSNBoundedCache.m
 *
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 */

#import "FSNBoundedCache.h"

@implementation FSNBoundedCache

- (id)initWithCapacity:(NSUInteger)aCapacity
{
  self = [super init];
  if (self)
    {
      capacity = (aCapacity > 0) ? aCapacity : 1;
      objects = [[NSMutableDictionary alloc] initWithCapacity: capacity];
      lastUse = [[NSMutableDictionary alloc] initWithCapacity: capacity];
    }
  return self;
}

- (void)dealloc
{
  [objects release];
  [lastUse release];
  [super dealloc];
}

- (NSUInteger)capacity
{
  return capacity;
}

- (NSUInteger)count
{
  return [objects count];
}

- (void)touchKey:(id)key
{
  clock++;
  [lastUse setObject: [NSNumber numberWithUnsignedLongLong: clock] forKey: key];
}

- (id)objectForKey:(id)key
{
  id object = [objects objectForKey: key];

  if (object != nil)
    {
      [self touchKey: key];
    }
  return object;
}

/* Evicts a quarter at a time, so the sort runs once per many inserts
 * rather than on every one. */
- (void)evict
{
  NSArray *keys;
  NSUInteger target = capacity - capacity / 4;
  NSUInteger i;

  if ([objects count] <= capacity)
    {
      return;
    }
  keys = [lastUse keysSortedByValueUsingSelector: @selector(compare:)];
  for (i = 0; i < [keys count] && [objects count] > target; i++)
    {
      id key = [keys objectAtIndex: i];

      [objects removeObjectForKey: key];
      [lastUse removeObjectForKey: key];
    }
}

- (void)setObject:(id)object forKey:(id)key
{
  [objects setObject: object forKey: key];
  [self touchKey: key];
  [self evict];
}

- (void)removeObjectForKey:(id)key
{
  [objects removeObjectForKey: key];
  [lastUse removeObjectForKey: key];
}

- (void)removeAllObjects
{
  [objects removeAllObjects];
  [lastUse removeAllObjects];
}

@end
