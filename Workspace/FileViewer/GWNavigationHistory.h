/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

/* The folders one browsing window has shown, for its Back and Forward
 * buttons and the History panel.  Kept free of AppKit and of FSNode so the
 * rules can be tested headless: items are compared with -isEqual:, and an
 * item answering -isValid with NO (a folder deleted meanwhile) is dropped
 * before any step. */

#import <Foundation/Foundation.h>

@interface GWNavigationHistory : NSObject {
  NSMutableArray *_items;
  NSInteger _position;
}

/* The live array, shared with the History panel, which lists it. */
- (NSMutableArray *)items;

- (NSInteger)position;
- (void)setPosition:(NSInteger)position;

- (id)currentItem;

/* Records that the window now shows item.  At most maxCount items before
 * the current one are kept, so the history cannot grow without bound. */
- (void)addItem:(id)item maxCount:(NSUInteger)maxCount;

- (BOOL)canGoBack;
- (BOOL)canGoForward;

/* Drops vanished items and repetitions, then returns the position one
 * step (-1 back, +1 forward) away, or NSNotFound when there is none.  The
 * position itself only moves once the window really shows that item. */
- (NSInteger)positionAfterStep:(NSInteger)step;

/* Drops vanished items, direct repetitions and repeated pairs, keeping the
 * current item current. */
- (void)compact;

- (void)removeAllItems;

@end

/* How many folders a window remembers when the user has not chosen, and
 * the fewest the History preferences let the user choose. */
extern const NSInteger GWNavigationHistoryDefaultLimit;
extern const NSInteger GWNavigationHistoryMinimumLimit;

/* The limit for a stored "history_cache" value.  A value below the minimum
 * cannot come from the preferences and would leave Back and Forward with
 * nothing to step to, so it counts as not chosen. */
NSInteger GWNavigationHistoryLimitFromDefault(id storedValue);
