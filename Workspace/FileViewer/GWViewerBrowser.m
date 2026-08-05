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
#import "Workspace.h"
#import "GWDesktopManager.h"

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


  // Handle arrow keys with modifiers
  if (character == NSDownArrowFunctionKey)
    {
      if ((flags & NSShiftKeyMask) && !(flags & NSCommandKeyMask))
        {
          [viewer openSelectionInNewViewer: NO];
          return;
        }
      if ((flags & NSCommandKeyMask) && (flags & NSShiftKeyMask))
        {
          [viewer openSelectionAsFolder];
          return;
        }
      if ((flags & NSCommandKeyMask) && !(flags & NSShiftKeyMask))
        {
          [viewer openSelectionInNewViewer: NO];
          return;
        }
    }

  if (character == NSUpArrowFunctionKey)
    {
      if ((flags & NSShiftKeyMask) && !(flags & NSCommandKeyMask))
        {
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
      if ((flags & NSCommandKeyMask))
        {
          id delegate = viewer;
          if ([delegate respondsToSelector: @selector(baseNode)])
            {
              FSNode *node = [delegate baseNode];
              if (node)
                {
                  NSString *parentPath = [[node path] stringByDeletingLastPathComponent];
                  if (parentPath && ![parentPath isEqual: [node path]])
                    {
                      FSNode *parentNode = [FSNode nodeWithPath: parentPath];
                      FSNode *dskNode = [[[Workspace gworkspace] desktopManager] desktopNode];
                      if (dskNode && [[parentNode path] isEqual: [dskNode path]])
                        return;

                      if (parentNode)
                        {
                          GWViewersManager *mgr = [GWViewersManager viewersManager];
                          if (mgr)
                            {
                              if (flags & NSShiftKeyMask)
                                {
                                  [mgr viewerOfType: SPATIAL
                                        showType: nil
                                         forNode: parentNode
                                   showSelection: NO
                                  closeOldViewer: delegate
                                        forceNew: NO];
                                }
                              else
                                {
                                  [mgr viewerOfType: SPATIAL
                                        showType: nil
                                         forNode: parentNode
                                   showSelection: NO
                                  closeOldViewer: nil
                                        forceNew: NO];
                                }
                            }
                        }
                    }
                }
            }
          return;
        }
    }

  // Handle Shift-Enter and Tab to select first item if nothing selected
  if ((character == '\r' && (flags & NSShiftKeyMask)) || character == '\t')
    {
      NSArray *selection = [self selectedNodes];
      if (selection == nil || [selection count] == 0)
        {
          // Select the first item in the first column
          [self selectRow: 0 inColumn: 0];
          return;
        }

      if (character == '\r' && (flags & NSShiftKeyMask))
        {
          [viewer openSelectionAsFolder];
          return;
        }
    }

  // Auto-select first item when pressing arrow keys with no selection
  if ((character == NSUpArrowFunctionKey
       || character == NSDownArrowFunctionKey
       || character == NSLeftArrowFunctionKey
       || character == NSRightArrowFunctionKey)
      && !(flags & NSCommandKeyMask))
    {
      NSArray *selection = [self selectedNodes];
      if (selection == nil || [selection count] == 0)
        {
          [self selectRow: 0 inColumn: 0];
        }
    }

  // Pass other keys to parent
  [super keyDown: theEvent];
}

@end




