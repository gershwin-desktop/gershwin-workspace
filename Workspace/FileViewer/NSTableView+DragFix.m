/* NSTableView+DragFix.m
 *
 * Swizzles NSTableView's -mouseDown: to eliminate the drag-initiation delay
 * that prevents immediate drags from starting on the first mouse drag event.
 *
 * Copyright (C) 2026 Free Software Foundation, Inc.
 *
 * Author: Gershwin Build
 *
 * This file is part of the GNUstep Workspace application.
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 */

#import <AppKit/AppKit.h>
#import <objc/runtime.h>
#include <stdio.h>

/* Original NSTableView -mouseDown: implementation, saved before swizzling */
static IMP _orig_mouseDown = NULL;

@interface NSTableView (DragFix)
@end

@implementation NSTableView (DragFix)

/*
 * Our replacement for NSTableView's -mouseDown:.
 *
 * Before calling the original implementation, we:
 *  1. Ensure the clicked row is selected (so drags work from *any* row,
 *     not just rows that were already selected — the stock NSTableView
 *     disables drags for rows that aren't in _selectedRows on the first
 *     mouseDown pass).
 *  2. Enable vertical-motion-can-begin-drag so the user doesn't have to
 *     drag perfectly horizontally.
 *
 * This eliminates the perceived ~2 s delay where the user had to first
 * click to select a row, wait, and then drag — now they can click and
 * immediately drag in any direction.
 */
- (void)_gw_mouseDown:(NSEvent *)theEvent
{
  /* ── Step 1: ensure the clicked row is selected ── */
  NSPoint location = [self convertPoint: [theEvent locationInWindow]
                               fromView: nil];
  NSInteger row = [self rowAtPoint: location];
  if (row >= 0 && [self isRowSelected: row] == NO)
    {
      NSUInteger modFlags = [theEvent modifierFlags];
      if (modFlags & NSShiftKeyMask)
        {
          /* Extend selection (range-select) */
          [self selectRowIndexes: [NSIndexSet indexSetWithIndex: row]
           byExtendingSelection: YES];
        }
      else if (modFlags & NSCommandKeyMask)
        {
          /* Toggle this row (command-click) */
          [self selectRowIndexes: [NSIndexSet indexSetWithIndex: row]
           byExtendingSelection: YES];
        }
      else
        {
          /* Simple click — replace selection with just this row */
          [self selectRowIndexes: [NSIndexSet indexSetWithIndex: row]
           byExtendingSelection: NO];
        }
    }

  /* ── Step 2: allow drags to begin from vertical motion ── */
  [self setVerticalMotionCanBeginDrag: YES];

  /* ── Step 3: call the original -mouseDown: via saved IMP ── */
  ((void (*)(id, SEL, NSEvent *))_orig_mouseDown)(self, @selector(mouseDown:), theEvent);
}

/*
 * Load: called once when the category is loaded.
 * Swizzles NSTableView's -mouseDown: with our replacement.
 */
+ (void)load
{
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    /* Use C runtime functions only — no ObjC message sends — to avoid
       triggering +initialize chains (NSUserDefaults → NSProcessInfo)
       before main() has had a chance to call _gnu_process_args().  */
    Class tableViewClass = objc_getClass("NSTableView");
    Method original = class_getInstanceMethod(tableViewClass,
                                              @selector(mouseDown:));
    Method swizzled = class_getInstanceMethod(self,
                                              @selector(_gw_mouseDown:));
    if (original && swizzled)
      {
        /* Save the original IMP before swapping */
        _orig_mouseDown = method_getImplementation(original);
        method_exchangeImplementations(original, swizzled);
        fprintf(stderr, "NSTableView+DragFix: swizzled -mouseDown: for instant drags\n");
      }
    else
      {
        fprintf(stderr, "NSTableView+DragFix: failed to swizzle -mouseDown: (orig=%p, swizzled=%p)\n",
              (void *)original, (void *)swizzled);
      }
  });
}

@end
