/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-2.0-or-later
 */

#import <AppKit/AppKit.h>
#import "FSNBrowserResizeHandle.h"
#import "FSNBrowserColumn.h"
#import "FSNBrowser.h"
#import "FSNBrowserLayout.h"
#import "FSNColumnViewOptions.h"

@implementation FSNBrowserResizeHandle

+ (CGFloat)widthForDragFromWidth:(CGFloat)startWidth by:(CGFloat)dx
{
  return FSNBrowserClampedColumnWidth (startWidth + dx);
}

- (id)initWithColumn:(FSNBrowserColumn *)col
{
  self = [super initWithFrame: NSZeroRect];
  if (self)
    {
      column = col;
    }
  return self;
}

- (BOOL)acceptsFirstMouse:(NSEvent *)event
{
  return YES;
}

- (void)resetCursorRects
{
  [self addCursorRect: [self bounds] cursor: [NSCursor resizeLeftRightCursor]];
}

- (void)mouseDown:(NSEvent *)event
{
  FSNBrowser *browser = [column browser];
  NSInteger index = [column index];
  NSWindow *window = [self window];
  /* Window coordinates are device pixels at a scale factor other than 1;
   * the column widths are in the browser's points. */
  CGFloat startX = [browser convertPoint: [event locationInWindow] fromView: nil].x;
  CGFloat startWidth = [browser widthOfColumnAtIndex: index];
  CGFloat width = startWidth;
  BOOL all = NO;

  if (browser == nil || window == nil)
    {
      return;
    }

  while (1)
    {
      NSEvent *e = [window nextEventMatchingMask: NSLeftMouseDraggedMask | NSLeftMouseUpMask];

      /* Option may be pressed or let go during the drag; what counts is
       * the state when the column was let go, as in Finder. */
      all = ([e modifierFlags] & NSAlternateKeyMask) != 0;
      width = [FSNBrowserResizeHandle widthForDragFromWidth: startWidth
                                                         by: [browser convertPoint: [e locationInWindow] fromView: nil].x - startX];
      if (all)
        {
          [browser setDefaultColumnWidth: width];
        }
      else
        {
          [browser setWidth: width forColumnAtIndex: index];
        }

      if ([e type] == NSLeftMouseUp)
        {
          break;
        }
    }

  /* Only the width of all columns is kept, for every column view; one
   * column's width lasts as long as this window (E32). */
  if (all)
    {
      [[FSNColumnViewOptions sharedOptions] setColumnWidth: width];
    }
}

- (void)drawRect:(NSRect)rect
{
  NSRect b = [self bounds];
  CGFloat cx = floor (NSMidX (b));
  CGFloat top = NSMaxY (b) - 3;
  CGFloat bottom = NSMinY (b) + 3;

  [[NSColor controlColor] set];
  NSRectFill (rect);

  /* The two grip lines Finder draws on its handle. */
  [[NSColor controlShadowColor] set];
  NSRectFill (NSMakeRect (cx - 2, bottom, 1, top - bottom));
  NSRectFill (NSMakeRect (cx + 1, bottom, 1, top - bottom));
}

@end
