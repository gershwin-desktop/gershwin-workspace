/* GWViewerListView.m
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
#import "GWViewerListView.h"
#import "GWViewerWindow.h"
#import "FSNode.h"
#import "GWViewer.h"
#import "GWViewersManager.h"
#import "Workspace.h"
#import "GWDesktopManager.h"

@implementation GWViewerListViewDataSource

- (id)initForListView:(FSNListView *)aview
{
  self = [super initForListView: aview];
  
  if (self) {
    manager = [GWViewersManager viewersManager];
  }
  
  return self;
}

- (void)setViewer:(id)vwr
{
  viewer = vwr;
}

- (FSNode *)infoNode
{
  if (viewer)
    {
      return [viewer baseNode];
    }
  
  return node;
}

- (BOOL)keepsColumnsInfo
{
  return (viewer != nil);
}

- (void)selectionDidChange
{
  NSArray *selection = [self selectedNodes];

  if ([selection count] == 0)
    selection = [NSArray arrayWithObject: node];

  if ((lastSelection == nil) || ([selection isEqual: lastSelection] == NO))
    {
      ASSIGN (lastSelection, selection);
      [viewer selectionChanged: selection];
    }
}

- (void)openSelectionInNewViewer:(BOOL)newv
{
  BOOL closesndr = ((mouseFlags == NSAlternateKeyMask) 
                              || (mouseFlags == NSControlKeyMask));
  [viewer openSelectionInNewViewer: (closesndr || newv)];
}

@end


@implementation GWViewerListView

- (id)initWithFrame:(NSRect)rect 
          forViewer:(id)vwr
{
  self = [super initWithFrame: rect 
              dataSourceClass: [GWViewerListViewDataSource class]];
  
  if (self) {
		viewer = vwr;
    manager = [GWViewersManager viewersManager];
    [dsource setViewer: viewer];
  }
  
  return self;
}

- (void)keyDown:(NSEvent *)theEvent
{
  unsigned flags = [theEvent modifierFlags];
  NSString *characters = [theEvent characters];
  unichar character = 0;

  if ([characters length] > 0)
    {
      character = [characters characterAtIndex: 0];
    }
  /* Shift with an arrow extends the selection (FSNListView), as in the
     reference; opening is Command's. */

  // Handle Command-Shift-Down = Open as Folder
  if (character == NSDownArrowFunctionKey && (flags & NSCommandKeyMask) && (flags & NSShiftKeyMask))
    {
      [viewer openSelectionAsFolder];
      return;
    }

  // Handle Command-Down = Open Selection
  if (character == NSDownArrowFunctionKey && (flags & NSCommandKeyMask) && !(flags & NSShiftKeyMask))
    {
      [viewer openSelectionInNewViewer: NO];
      return;
    }

  // Handle Command-Up = Open Enclosing Folder
  // Handle Command-Shift-Up = Open parent and close current viewer (spatial)
  if (character == NSUpArrowFunctionKey && (flags & NSCommandKeyMask))
    {
      [viewer openEnclosingFolderClosingViewer: (flags & NSShiftKeyMask) != 0];
      return;
    }

  // Shift-Return opens the selection as a folder
  if (character == '\r' && (flags & NSShiftKeyMask) && [[self selectedNodes] count] > 0)
    {
      [viewer openSelectionAsFolder];
      return;
    }

  // Pass other keys to parent
  [super keyDown: theEvent];
}

- (NSMenu *)menuForEvent:(NSEvent *)theEvent
{
  if ([theEvent type] == NSRightMouseDown) {
    NSPoint location = [theEvent locationInWindow];
    int row = [self rowAtPoint: [self convertPoint: location fromView: nil]];
    
    if (row != -1) {
      NSArray *selnodes;

      /* The menu of a row that is not selected is about that row alone,
         as in the reference, so it becomes the selection. */
      if ([self isRowSelected: row] == NO) {
        [self selectRowIndexes: [NSIndexSet indexSetWithIndex: row]
          byExtendingSelection: NO];
      }
      selnodes = [self selectedNodes];

      if (selnodes && [selnodes count]) {
        return [[Workspace gworkspace] contextMenuForNodes: selnodes
                                                openTarget: [viewer win]
                                             openWithTarget: [Workspace gworkspace]
                                                infoTarget: [Workspace gworkspace]
                                           duplicateTarget: [viewer win]
                                             aliasTarget: [viewer win]
                                             recycleTarget: [viewer win]
                                               ejectTarget: [viewer win]
                                                openAction: @selector(openSelection:)
                                           duplicateAction: @selector(duplicateFiles:)
                                            aliasAction: @selector(makeAliasFiles:)
                                             recycleAction: @selector(recycleFiles:)
                                               ejectAction: @selector(ejectVolumes:)
                                          includeOpenWith: YES];
      }
    } else {
      // Right-clicked on empty space
      return [[Workspace gworkspace] emptySpaceContextMenuForViewer: [viewer win]];
    }
  }
  
  return [super menuForEvent: theEvent];
}

@end




