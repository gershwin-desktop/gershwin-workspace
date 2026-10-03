/* GWViewerScrollView.m
 *  
 * Copyright (C) 2004-2013 Free Software Foundation, Inc.
 *
 * Author: Enrico Sersale <enrico@imago.ro>
 * Date: December 2004
 *
 * This file is part of the GNUstep Workspace application
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 * 
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 * 
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 31 Milk Street #960789 Boston, MA 02196 USA.
 */

#import <AppKit/AppKit.h>

#import "FSNFunctions.h"
#import "GWViewerScrollView.h"
#import "GWViewer.h"

/* 1px line drawn along the top edge of the viewport (see the class
 * implementation at the bottom of this file). */
@interface GWScrollViewTopSeparator : NSView
@end

@interface GWViewerScrollView ()
- (void)layoutTopSeparator;
@end

@implementation GWViewerScrollView

- (id)initWithFrame:(NSRect)frameRect
           inViewer:(id)aviewer
{
  self = [super initWithFrame: frameRect];

  if (self) {
    viewer = aviewer;
  }
  
  return self;
}

- (void)setDocumentView:(NSView *)aView
{
  [super setDocumentView: aView];
  
  if (aView != nil) {
    nodeView = [viewer nodeView];
    
    if ([nodeView needsDndProxy]) {
      [self registerForDraggedTypes: [NSArray arrayWithObjects: 
                                              NSFilenamesPboardType, 
                                              @"GWLSFolderPboardType", 
                                              @"GWRemoteFilenamesPboardType", 
                                              nil]];    
    } else {
      [self unregisterDraggedTypes];
    }
  } else {
    nodeView = nil;
    [self unregisterDraggedTypes];
  }
}

- (void)setDrawsTopSeparator:(BOOL)flag
{
  /* Spatial-mode-only feature: the classic browsing viewer never draws the
   * top separator, whatever a caller asks for. */
  if (flag && viewer != nil
      && [viewer respondsToSelector: @selector(isSpatial)]
      && [viewer isSpatial] == NO)
    {
      flag = NO;
    }

  if (drawsTopSeparator != flag)
    {
      drawsTopSeparator = flag;

      if (flag)
        {
          if (topSeparator == nil)
            {
              topSeparator = [[GWScrollViewTopSeparator alloc]
                initWithFrame: NSZeroRect];
              /* Tracks the scroll view's width automatically; the vertical
               * position and 1px height are re-pinned in layoutTopSeparator
               * on every resize, so the line never moves. */
              [topSeparator setAutoresizingMask: NSViewWidthSizable];
              [self addSubview: topSeparator];
              /* Retiles: besides pinning the strip this takes the strip's
               * top row away from the clip view, see -tile below. */
              [self tile];
            }
        }
      else
        {
          [topSeparator removeFromSuperview];
          DESTROY (topSeparator);
          /* Retiling gives the freed row back to the clip view. */
          [self tile];
        }

      [self setNeedsDisplay: YES];
    }
}

/* Places the separator strip flush against the visual top edge of the scroll
 * view, whatever the superview's flippedness.  Explicitly re-pinned on every
 * resize (setFrameSize:) so the line never moves - not when the viewer
 * resizes and not during scrolling, since it sits outside the clip view. */
- (void)layoutTopSeparator
{
  NSRect bounds;
  CGFloat top;

  if (topSeparator == nil)
    {
      return;
    }

  bounds = [self bounds];
  top = [self isFlipped] ? NSMinY(bounds) : NSMaxY(bounds);
  [topSeparator setFrame: NSMakeRect(NSMinX(bounds),
                                     top - ([self isFlipped] ? 0 : 1),
                                     NSWidth(bounds), 1)];
}

- (void)setFrameSize:(NSSize)newSize
{
  [super setFrameSize: newSize];
  [self layoutTopSeparator];
}

/* Makes the separator's row untouchable by the document view.  NSScrollView's
 * tile() lays the clip view over the full top of the scroll view, and a
 * document-view repaint inside it would paint straight over the strip's
 * pixels: GNUstep redraws damaged views flat into the X window without
 * re-rendering the undamaged siblings stacked above, so the line vanished on
 * every scroll.  Shrinking the clip view along its visual top edge by the
 * strip's 1px makes that row the strip's own - the clip can no longer paint
 * there, and the line can neither move nor be covered. */
- (void)tile
{
  [super tile];

  if (drawsTopSeparator && topSeparator != nil)
    {
      NSClipView *clip = [self contentView];
      NSRect clipFrame = [clip frame];

      /* origin.y += 1 / height -= 1 moves the visual top edge down by 1px in
       * flipped and unflipped coordinate systems alike. */
      clipFrame.origin.y += 1;
      clipFrame.size.height -= 1;
      [clip setFrame: clipFrame];

      [self layoutTopSeparator];
    }
}

- (BOOL)drawsTopSeparator
{
  return drawsTopSeparator;
}

- (void)dealloc
{
  DESTROY (topSeparator);
  [super dealloc];
}

@end

/* 1px line drawn along the top edge of the viewport, separating it from the
 * path bar / top box above.  Added as the top-most subview because an
 * unbordered NSScrollView's clip view covers the full bounds, which would
 * hide a line drawn in drawRect.  hitTest returns nil so the strip never
 * intercepts clicks meant for the icons underneath. */
@implementation GWScrollViewTopSeparator

- (void)drawRect:(NSRect)rect
{
  [[NSColor controlShadowColor] set];
  NSRectFill(rect);
}

- (NSView *)hitTest:(NSPoint)aPoint
{
  return nil;
}

@end


@implementation GWViewerScrollView (DraggingDestination)

- (NSDragOperation)draggingEntered:(id <NSDraggingInfo>)sender
{
  if (nodeView && [nodeView needsDndProxy]) {
    return [nodeView draggingEntered: sender];
  }
  return NSDragOperationNone;
}

- (NSDragOperation)draggingUpdated:(id <NSDraggingInfo>)sender
{
  if (nodeView && [nodeView needsDndProxy]) {
    return [nodeView draggingUpdated: sender];
  }
  return NSDragOperationNone;
}

- (void)draggingExited:(id <NSDraggingInfo>)sender
{
  if (nodeView && [nodeView needsDndProxy]) {
    [nodeView draggingExited: sender];
  }
}

- (BOOL)prepareForDragOperation:(id <NSDraggingInfo>)sender
{
  if (nodeView && [nodeView needsDndProxy]) {
    return [nodeView prepareForDragOperation: sender];
  }
  return NO;
}

- (BOOL)performDragOperation:(id <NSDraggingInfo>)sender
{
  if (nodeView && [nodeView needsDndProxy]) {
    return [nodeView performDragOperation: sender];
  }
  return NO;
}

- (void)concludeDragOperation:(id <NSDraggingInfo>)sender
{
  if (nodeView && [nodeView needsDndProxy]) {
    [nodeView concludeDragOperation: sender];
  }
}

@end











