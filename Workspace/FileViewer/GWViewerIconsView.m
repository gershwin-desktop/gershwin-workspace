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
#import "GWDesktopManager.h"
#import "X11AppSupport.h"

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

      /* Finder icon view fills left→right, top→bottom */
      [self setPlacementDirection: FSNPlacementDirectionLeftToRightTopToBottom];
    }

  return self;
}

/* The browser icon view auto-grids and reflows to the window width; it does
 * not honor or persist saved .DS_Store positions (those are for the spatial
 * view and the desktop). */
/* Another application's window can cover this one, and AppKit does not see
   it; the window server does. */
- (BOOL)foreignWindowIsUnderPointer
{
  return GWForeignWindowIsUnderPointer();
}

- (BOOL)honorsSavedPositions
{
  return NO;
}

/* Laid out from the top, where the icons are read from.  Laid out from the
   bottom, the top of the document is reached by scrolling, and NSClipView
   rounds each scroll origin to whole window units while the height of the
   visible area is fractional at a scale factor such as 1.2: every step of a
   live resize then left the icons a different fraction below the top, and
   they jumped up and down by a pixel or two all the time. */
- (BOOL)isFlipped
{
  return YES;
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

- (void)keyDown:(NSEvent *)theEvent
{
  unsigned flags = [theEvent modifierFlags];
  NSString *characters = [theEvent characters];
  unichar character = 0;

  if ([characters length] > 0)
    {
      character = [characters characterAtIndex: 0];
    }


  /* Shift with an arrow extends the selection (FSNIconsView), as in the
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
    NSArray *selnodes;

    /* A right click on the background first does what a left click there
       does, so the menu is the empty-space one and not the menu of icons
       the user has clicked away from. */
    if ([self iconWithNodeAtWindowPoint: [theEvent locationInWindow]] == nil)
      [self selectNothingForBackgroundEvent: theEvent];

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
    } else {
      // Right-clicked on empty space
      return [[Workspace gworkspace] emptySpaceContextMenuForViewer: [viewer win]];
    }
  }
  
  return [super menuForEvent: theEvent];
}

@end




