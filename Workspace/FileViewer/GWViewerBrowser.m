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
            acceptsDnd:(BOOL)dnd
         editableCells:(BOOL)edcells
       selectionColumn:(BOOL)selcol
{
  self = [super initWithBaseNode: bsnode
                  visibleColumns: vcols 
                        scroller: scrl
                      cellsIcons: cicns
                      acceptsDnd: dnd
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


  /* Shift with an arrow extends the selection (FSNBrowserMatrix), as in
     the reference; opening and going up are Command's. */
  if (character == NSDownArrowFunctionKey)
    {
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

  // Shift-Return opens the selection as a folder
  if (character == '\r' && (flags & NSShiftKeyMask) && [[self selectedNodes] count] > 0)
    {
      [viewer openSelectionAsFolder];
      return;
    }

  // Nothing selected yet: Down and Right start in the first column
  if ((character == NSDownArrowFunctionKey || character == NSRightArrowFunctionKey)
      && !(flags & NSCommandKeyMask) && [[self selectedNodes] count] == 0)
    {
      [self selectRow: 0 inColumn: 0];
      return;
    }

  // Pass other keys to parent
  [super keyDown: theEvent];
}

@end




