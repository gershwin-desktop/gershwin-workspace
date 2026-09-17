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
  if (drawsTopSeparator != flag)
    {
      drawsTopSeparator = flag;

      if (flag)
        {
          if (topSeparator == nil)
            {
              /* NSScrollView is flipped (y grows downward), so the visual
               * top edge is NSMinY(bounds).  Anchor against isFlipped to be
               * safe rather than assuming an orientation. */
              NSRect bounds = [self bounds];
              CGFloat top = [self isFlipped] ? NSMinY(bounds) : NSMaxY(bounds);
              topSeparator = [[GWScrollViewTopSeparator alloc]
                initWithFrame: NSMakeRect(NSMinX(bounds), top - ([self isFlipped] ? 0 : 1),
                                          NSWidth(bounds), 1)];
              [topSeparator setAutoresizingMask:
                NSViewWidthSizable | NSViewMinYMargin];
              [self addSubview: topSeparator];
            }
        }
      else
        {
          [topSeparator removeFromSuperview];
          DESTROY (topSeparator);
        }

      [self setNeedsDisplay: YES];
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











