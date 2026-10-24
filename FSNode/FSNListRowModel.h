/* FSNListRowModel.h - the rows of a list view with folders expanded inline.
 *
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-2.0-or-later
 */

#ifndef FSN_LIST_ROW_MODEL_H
#define FSN_LIST_ROW_MODEL_H

#import <Foundation/Foundation.h>

/* A tree of items, each listed under the key of the folder it is in, and
 * the flat row order a table shows of it: a folder's items follow it, one
 * level deeper, while the folder and every folder above it are expanded.
 * Items are opaque; the block hands out the key (a path) of each.  Nothing
 * here touches the file system, so the list view decides what to load. */
@interface FSNListRowModel : NSObject
{
  NSString *(^keyOfItem)(id item);
  NSString *rootKey;
  NSMutableDictionary *children;   /* folder key -> NSMutableArray of items */
  NSMutableDictionary *parents;    /* item key -> folder key */
  NSMutableSet *expanded;
  NSMutableArray *rows;
  NSMutableArray *depths;
  NSMutableDictionary *rowIndex;   /* item key -> NSNumber row */
}

- (id)initWithKeyOfItem:(NSString *(^)(id item))block;

/* Drops every item.  A reload of the same folder keeps what was expanded,
 * as the reference list view does; another folder starts collapsed. */
- (void)resetWithRootKey:(NSString *)key keepExpanded:(BOOL)keep;
- (NSString *)rootKey;

- (void)setChildren:(NSArray *)items ofKey:(NSString *)key;
- (NSArray *)childrenOfKey:(NSString *)key;
/* Replaces an item with the same key, so a watcher event twice is harmless. */
- (void)addChild:(id)item toKey:(NSString *)key;
/* Removes the item and everything listed below it; nil if unknown. */
- (id)removeItemWithKey:(NSString *)key;
- (id)itemWithKey:(NSString *)key;
- (NSString *)parentKeyOfKey:(NSString *)key;

/* Collapsing keeps the expanded state of folders inside, so expanding the
 * outer one again brings them back as they were. */
- (void)setExpanded:(BOOL)flag forKey:(NSString *)key;
- (BOOL)isExpanded:(NSString *)key;
/* Expanded folders whose rows are shown, outer before inner: the ones that
 * need their items loaded and their changes watched. */
- (NSArray *)visibleExpandedKeys;

/* Orders the items of every folder on their own. */
- (void)sortUsingComparator:(NSComparator)cmp;

- (void)rebuildRows;
- (NSArray *)rows;
- (NSUInteger)depthOfRow:(NSUInteger)row;
- (NSUInteger)rowOfKey:(NSString *)key;

@end

/* Horizontal geometry of the name column, in points from its left edge:
 * a disclosure column of 26 points, 21 more per level. */
CGFloat FSNListIconXForDepth (NSUInteger depth);
NSRect FSNListDisclosureRectForDepth (NSUInteger depth, CGFloat rowHeight);
NSRect FSNListDisclosureHitRectForDepth (NSUInteger depth, CGFloat rowHeight);

#endif
