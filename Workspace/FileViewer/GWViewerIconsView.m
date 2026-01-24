/* GWViewerIconsView.m
 *  
 * Copyright (C) 2004-2022 Free Software Foundation, Inc.
 *
 * Authora: Enrico Sersale <enrico@imago.ro>
 *          Riccardo Mottola <rm@gnu.org>
 * Date: June 2004
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
#import "GWViewerIconsView.h"
#import "GWViewerWindow.h"
#import "FSNIcon.h"
#import "FSNode.h"
#import "GWViewer.h"
#import "GWViewersManager.h"
#import "Workspace.h"

@implementation GWViewerIconsView

- (void)dealloc
{
  [super dealloc];
}

- (id)initForViewer:(id)vwr
{
  self = [super init];
  
  if (self)
    {
      viewer = vwr;
      manager = [GWViewersManager viewersManager];
    }
  
  return self;
}

- (void)selectionDidChange
{
  if (!(selectionMask & FSNCreatingSelectionMask))
    {
      NSArray *selection = [self selectedNodes];
		
      if ([selection count] == 0)
        selection = [NSArray arrayWithObject: node];

      if ((lastSelection == nil) || ([selection isEqual: lastSelection] == NO))
        {
          ASSIGN (lastSelection, selection);
          [viewer selectionChanged: selection];
        }
    
      [self updateNameEditor];
    }
}

- (void)openSelectionInNewViewer:(BOOL)newv
{
  [viewer openSelectionInNewViewer: newv];
}

- (void)mouseDown:(NSEvent *)theEvent
{
  if ([theEvent modifierFlags] != NSShiftKeyMask)
    {
      selectionMask = NSSingleSelectionMask;
      selectionMask |= FSNCreatingSelectionMask;
      [self unselectOtherReps: nil];
      selectionMask = NSSingleSelectionMask;
    
      DESTROY (lastSelection);
      [self selectionDidChange];
      [self stopRepNameEditing];
   
    }
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

  NSLog(@"GWViewerIconsView.keyDown: character=0x%x, flags=0x%x", character, flags);

  // Handle Shift-Down = Open Selection
  if (character == NSDownArrowFunctionKey && (flags & NSShiftKeyMask) && !(flags & NSCommandKeyMask))
    {
      NSLog(@"GWViewerIconsView: Shift-Down detected");
      [viewer openSelectionInNewViewer: NO];
      return;
    }

  // Handle Shift-Up = Open parent folder in new viewer
  if (character == NSUpArrowFunctionKey && (flags & NSShiftKeyMask) && !(flags & NSCommandKeyMask))
    {
      id delegate = viewer;
      if ([delegate respondsToSelector: @selector(baseNode)])
        {
          FSNode *baseNode = [delegate baseNode];
          if (baseNode)
            {
              NSString *parentPath = [[baseNode path] stringByDeletingLastPathComponent];
              if (parentPath && ![parentPath isEqual: [baseNode path]])
                {
                  FSNode *parentNode = [FSNode nodeWithPath: parentPath];
                  if (parentNode)
                    {
                      GWViewersManager *mgr = [GWViewersManager viewersManager];
                      if (mgr)
                        {
                          [mgr viewerForNode: parentNode
                               showType: 0
                          showSelection: NO
                               forceNew: NO
                               withKey: nil];
                        }
                    }
                }
            }
        }
      return;
    }

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

  // Handle Command-Up = Open Parent Folder
  if (character == NSUpArrowFunctionKey && (flags & NSCommandKeyMask) && !(flags & NSShiftKeyMask))
    {
      NSLog(@"GWViewerIconsView: Command-Up - opening parent folder in viewer");
      [[viewer win] openParentFolder];
      return;
    }

  // Handle Shift-Enter and Tab to select first item if nothing selected
  if ((character == '\r' && (flags & NSShiftKeyMask)) || character == '\t')
    {
      NSArray *selection = [self selectedNodes];
      if (selection == nil || [selection count] == 0)
        {
          NSLog(@"GWViewerIconsView: No selection, selecting first item");
          // Let parent handle selection of first item
          [super keyDown: theEvent];
          return;
        }

      if (character == '\r' && (flags & NSShiftKeyMask))
        {
          NSLog(@"GWViewerIconsView: Shift-Enter - opening as folder");
          [viewer openSelectionAsFolder];
          return;
        }
    }

  // Pass other keys to parent
  [super keyDown: theEvent];
}

- (NSMenu *)menuForEvent:(NSEvent *)theEvent
{
  if ([theEvent type] == NSRightMouseDown) {
    NSArray *selnodes = [self selectedNodes];
    
    if (selnodes && [selnodes count]) {
      return [[Workspace gworkspace] contextMenuForNodes: selnodes
                                              openTarget: [viewer win]
                                           openWithTarget: [Workspace gworkspace]
                                              infoTarget: [Workspace gworkspace]
                                         duplicateTarget: [viewer win]
                                           recycleTarget: [viewer win]
                                             ejectTarget: [viewer win]
                                              openAction: @selector(openSelection:)
                                         duplicateAction: @selector(duplicateFiles:)
                                           recycleAction: @selector(recycleFiles:)
                                             ejectAction: @selector(ejectVolumes:)
                                        includeOpenWith: YES];
    } else {
      // Right-clicked on empty space
      return [[Workspace gworkspace] emptySpaceContextMenuForViewer: [viewer win]];
    }
  }
  
  return [super menuForEvent: theEvent];
}

@end




