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
#import "GWViewer.h"
#import "GWViewersManager.h"
#import "Workspace.h"

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

- (NSMenu *)menuForEvent:(NSEvent *)theEvent
{
  if ([theEvent type] == NSRightMouseDown) {
    NSPoint location = [theEvent locationInWindow];
    int row = [self rowAtPoint: [self convertPoint: location fromView: nil]];
    
    if (row != -1) {
      NSArray *selnodes = [self selectedNodes];
      NSAutoreleasePool *pool;
      NSMenu *menu;
      NSMenuItem *menuItem;
      NSString *firstext; 
      NSDictionary *apps;
      NSEnumerator *app_enum;
      id key; 
      int i;
      BOOL isMountPoint = NO;
      BOOL allMountPoints = YES;

      if (selnodes && [selnodes count]) {
        FSNListViewNodeRep *rep = [[self reps] objectAtIndex: row];

        if ([selnodes containsObject: [rep node]] == NO) {
          return [super menuForEvent: theEvent];
        }
        
        firstext = [[[selnodes objectAtIndex: 0] path] pathExtension];
        
        // Check if any selected items are mount points
        for (i = 0; i < [selnodes count]; i++) {
          FSNode *snode = [selnodes objectAtIndex: i];
          if ([snode isMountPoint]) {
            isMountPoint = YES;
          } else {
            allMountPoints = NO;
          }
        }
        
        menu = [[NSMenu alloc] initWithTitle: @""];
        pool = [NSAutoreleasePool new];

        // Open
        menuItem = [NSMenuItem new];
        [menuItem setTitle: NSLocalizedString(@"Open", @"")];
        [menuItem setTarget: viewer];
        [menuItem setAction: @selector(openSelection:)];
        [menu addItem: menuItem];
        RELEASE (menuItem);

        // Open With submenu - only for files with same extension
        BOOL canShowOpenWith = YES;
        for (i = 0; i < [selnodes count]; i++) {
          FSNode *snode = [selnodes objectAtIndex: i];
          NSString *ext = [[snode path] pathExtension];   

          if ([ext isEqual: firstext] == NO) {
            canShowOpenWith = NO;
            break;
          }

          if ([snode isDirectory] == NO) {
            if ([snode isPlain] == NO) {
              canShowOpenWith = NO;
              break;
            }
          } else {
            if (([snode isPackage] == NO) || [snode isApplication]) {
              canShowOpenWith = NO;
              break;
            } 
          }
        }

        if (canShowOpenWith) {
          menuItem = [NSMenuItem new];
          [menuItem setTitle: NSLocalizedString(@"Open With", @"")];
          NSMenu *openWithMenu = [[NSMenu alloc] initWithTitle: @""];
          
          apps = [[NSWorkspace sharedWorkspace] infoForExtension: firstext];
          app_enum = [[apps allKeys] objectEnumerator];

          while ((key = [app_enum nextObject])) {
            NSMenuItem *appItem = [NSMenuItem new];    
            key = [key stringByDeletingPathExtension];
            [appItem setTitle: key];
            [appItem setTarget: [Workspace gworkspace]];      
            [appItem setAction: @selector(openSelectionWithApp:)];      
            [appItem setRepresentedObject: key];            
            [openWithMenu addItem: appItem];
            RELEASE (appItem);
          }
          
          [menuItem setSubmenu: openWithMenu];
          RELEASE (openWithMenu);
          [menu addItem: menuItem];
          RELEASE (menuItem);
        }

        [menu addItem: [NSMenuItem separatorItem]];

        // Get Info
        menuItem = [NSMenuItem new];
        [menuItem setTitle: NSLocalizedString(@"Get Info", @"")];
        [menuItem setTarget: [Workspace gworkspace]];
        [menuItem setAction: @selector(showAttributesInspector:)];
        [menu addItem: menuItem];
        RELEASE (menuItem);

      // Only show Duplicate if not all mount points
      if (!allMountPoints) {
        [menu addItem: [NSMenuItem separatorItem]];

        // Duplicate
        menuItem = [NSMenuItem new];
        [menuItem setTitle: NSLocalizedString(@"Duplicate", @"")];
        [menuItem setTarget: viewer];
        [menuItem setAction: @selector(duplicateFiles:)];
        [menu addItem: menuItem];
        RELEASE (menuItem);

        [menu addItem: [NSMenuItem separatorItem]];
      }

      // Show Eject for mount points, Move to Recycler for regular files
      if (isMountPoint) {
        BOOL hasRootFS = NO;
        // Check if any selected item is the root filesystem
        for (i = 0; i < [selnodes count]; i++) {
          FSNode *snode = [selnodes objectAtIndex: i];
          if ([[snode path] isEqualToString: @"/"]) {
            hasRootFS = YES;
            break;
          }
        }
        
        menuItem = [NSMenuItem new];
        [menuItem setTitle: NSLocalizedString(@"Eject", @"")];
        [menuItem setTarget: viewer];
        [menuItem setAction: @selector(ejectVolumes:)];
        [menuItem setEnabled: !hasRootFS];
        [menu addItem: menuItem];
        RELEASE (menuItem);
      } else {
        // Move to Recycler
        menuItem = [NSMenuItem new];
        [menuItem setTitle: NSLocalizedString(@"Move to Recycler", @"")];
        [menuItem setTarget: viewer];
        [menuItem setAction: @selector(recycleFiles:)];
        [menu addItem: menuItem];
        RELEASE (menuItem);
      }
      RELEASE (pool);
      return [menu autorelease];
      }
    }
  }
  
  return [super menuForEvent: theEvent];
}

@end




