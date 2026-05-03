/* GWViewerSidebar.h
 *
 * Copyright (C) 2026 Free Software Foundation, Inc.
 *
 * This file is part of the GNUstep Workspace application
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 */

#import <Foundation/Foundation.h>
#import <AppKit/NSView.h>

@class NSOutlineView;
@class NSScrollView;
@class GWSidebarItem;

@interface GWViewerSidebar : NSView
{
  NSScrollView *scrollView;
  NSOutlineView *outlineView;
  NSMutableArray *rootItems;
  NSMutableSet *collapsedGroupTitles;
  id viewer;
}

- (id)initWithFrame:(NSRect)frameRect
          forViewer:(id)vwr;

- (void)reloadData;

@end
