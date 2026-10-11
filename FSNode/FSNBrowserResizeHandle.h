/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-2.0-or-later
 */

/* The grip under the scroller of a column-view column: dragging it resizes
 * that column, dragging it with Option held resizes every column (Finder's
 * column view). */

#ifndef FSN_BROWSER_RESIZE_HANDLE_H
#define FSN_BROWSER_RESIZE_HANDLE_H

#import <AppKit/NSView.h>

@class FSNBrowserColumn;

@interface FSNBrowserResizeHandle : NSView
{
  FSNBrowserColumn *column;   /* not retained: the column owns the handle */
}

- (id)initWithColumn:(FSNBrowserColumn *)col;

/* The width a drag that started at startWidth and moved by dx leaves the
 * column with. */
+ (CGFloat)widthForDragFromWidth:(CGFloat)startWidth by:(CGFloat)dx;

@end

#endif /* FSN_BROWSER_RESIZE_HANDLE_H */
