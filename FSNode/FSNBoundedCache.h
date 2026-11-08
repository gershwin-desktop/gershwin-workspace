/*
 * FSNBoundedCache.h
 *
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 */

#ifndef FSN_BOUNDED_CACHE_H
#define FSN_BOUNDED_CACHE_H

#import <Foundation/Foundation.h>

/* A dictionary that keeps at most a given number of entries and forgets
 * the ones used longest ago.  The icon caches use it: every image they
 * keep holds a hidden X window once it has been drawn, so an unbounded
 * cache grows the X server's window tree with every folder shown. */
@interface FSNBoundedCache : NSObject
{
  NSMutableDictionary *objects;
  NSMutableDictionary *lastUse;
  NSUInteger capacity;
  unsigned long long clock;
}

- (id)initWithCapacity:(NSUInteger)aCapacity;
- (NSUInteger)capacity;
- (NSUInteger)count;

/* Counts as a use, so the entry is kept longer. */
- (id)objectForKey:(id)key;
- (void)setObject:(id)object forKey:(id)key;
- (void)removeObjectForKey:(id)key;
- (void)removeAllObjects;

@end

#endif
