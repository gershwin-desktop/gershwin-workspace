/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

/* GWLookInsideOverviewView.h - all items Look Inside was opened for, side
 * by side, as pictures with their names; the highlighted one is the item
 * the panel shows when the overview goes away.  A click picks an item and
 * sends the action. */

#import <AppKit/AppKit.h>

@interface GWLookInsideOverviewView : NSView
{
  NSArray *_paths;
  NSUInteger _highlightedIndex;
  NSMutableDictionary *_pictures;   /* index -> NSImage, made on first draw */
  id _target;
  SEL _action;
}

- (void)setPaths:(NSArray *)paths;
- (void)setHighlightedIndex:(NSUInteger)index;
- (NSUInteger)highlightedIndex;
- (void)setTarget:(id)target;
- (void)setAction:(SEL)action;

@end
