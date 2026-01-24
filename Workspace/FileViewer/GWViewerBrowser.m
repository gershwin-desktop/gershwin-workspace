/* GWViewerBrowser.m
 *  
 * Copyright (C) 2004-2013 Free Software Foundation, Inc.
 *
 * Author: Enrico Sersale <enrico@imago.ro>
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
#import "GWViewerBrowser.h"
#import "GWViewerWindow.h"
#import "FSNode.h"
#import "FSNBrowserColumn.h"
#import "FSNBrowserMatrix.h"
#import "FSNBrowserCell.h"
#import "GWViewersManager.h"

@implementation GWViewerBrowser

- (id)initWithBaseNode:(FSNode *)bsnode
              inViewer:(id)vwr
        visibleColumns:(int)vcols 
              scroller:(NSScroller *)scrl
            cellsIcons:(BOOL)cicns
         editableCells:(BOOL)edcells
       selectionColumn:(BOOL)selcol
{
  self = [super initWithBaseNode: bsnode
                  visibleColumns: vcols 
                        scroller: scrl
                      cellsIcons: cicns
                   editableCells: edcells    
                 selectionColumn: selcol];

  if (self) {
    viewer = vwr;
    manager = [GWViewersManager viewersManager];
  }
  
  return self;
}

- (void)notifySelectionChange:(NSArray *)newsel
{
  if (newsel)
    {
      if ((lastSelection == nil) || ([newsel isEqual: lastSelection] == NO))
        {
          if ([newsel count] == 0)
            {
              newsel = [NSArray arrayWithObject: baseNode]; 
            }

          ASSIGN (lastSelection, newsel);
          [viewer selectionChanged: newsel];
          [self synchronizeViewer];
        } 
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

  NSLog(@"GWViewerBrowser.keyDown: character=0x%x, flags=0x%x", character, flags);

  // Handle arrow keys with modifiers
  if (character == NSDownArrowFunctionKey)
    {
      NSLog(@"GWViewerBrowser: NSDownArrowFunctionKey pressed, flags=0x%x", flags);
      if ((flags & NSShiftKeyMask) && !(flags & NSCommandKeyMask))
        {
          NSLog(@"GWViewerBrowser: Shift-Down detected - opening selection");
          [viewer openSelectionInNewViewer: NO];
          return;
        }
      if ((flags & NSCommandKeyMask) && (flags & NSShiftKeyMask))
        {
          NSLog(@"GWViewerBrowser: Command-Shift-Down detected - opening as folder");
          [viewer openSelectionAsFolder];
          return;
        }
      if ((flags & NSCommandKeyMask) && !(flags & NSShiftKeyMask))
        {
          NSLog(@"GWViewerBrowser: Command-Down detected - opening selection");
          [viewer openSelectionInNewViewer: NO];
          return;
        }
    }

  if (character == NSUpArrowFunctionKey)
    {
      NSLog(@"GWViewerBrowser: NSUpArrowFunctionKey pressed, flags=0x%x", flags);
      if ((flags & NSShiftKeyMask) && !(flags & NSCommandKeyMask))
        {
          NSLog(@"GWViewerBrowser: Shift-Up detected - opening parent folder");
          id delegate = viewer;
          if ([delegate respondsToSelector: @selector(baseNode)])
            {
              FSNode *targetNode = [delegate baseNode];
              if (targetNode)
                {
                  NSString *parentPath = [[targetNode path] stringByDeletingLastPathComponent];
                  if (parentPath && ![parentPath isEqual: [targetNode path]])
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
      if ((flags & NSCommandKeyMask) && !(flags & NSShiftKeyMask))
        {
          NSLog(@"GWViewerBrowser: Command-Up - opening parent folder in viewer");
          [[viewer win] openParentFolder];
          return;
        }
    }

  // Handle Shift-Enter and Tab to select first item if nothing selected
  if ((character == '\r' && (flags & NSShiftKeyMask)) || character == '\t')
    {
      NSArray *selection = [self selectedNodes];
      if (selection == nil || [selection count] == 0)
        {
          NSLog(@"GWViewerBrowser: No selection, selecting first item");
          // Select the first item in the first column
          [self selectRow: 0 inColumn: 0];
          return;
        }

      if (character == '\r' && (flags & NSShiftKeyMask))
        {
          NSLog(@"GWViewerBrowser: Shift-Enter - opening as folder");
          [viewer openSelectionAsFolder];
          return;
        }
    }

  // Pass other keys to parent
  [super keyDown: theEvent];
}

@end




