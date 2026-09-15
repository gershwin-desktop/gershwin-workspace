/*
 * GWViewerBrowserPreview.h
 *
 * Rightmost pane of the browser viewer: shows the same information as the
 * Get Info Inspector window, but in a compact fixed-width pane.  A popup
 * button at the top switches between the Info, Contents and Comments
 * inspectors, whose views are swapped in the content box below - exactly
 * like the Inspector window.  It reuses the Inspector framework's
 * Attributes (Info), Contents and Annotations (Comments) classes.
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

#import <AppKit/AppKit.h>

@class Contents;
@class Attributes;
@class Annotations;

/* Fixed width (in points) of the rightmost Contents preview pane shown
 * beside the browser columns.  Shared by both the browsing GWViewer and
 * the spatial GWSpatialViewer.  Set to 1.2x the original 200px column. */
#define GW_PREVIEW_PANE_WIDTH 288.0

@interface GWViewerBrowserPreview : NSView
{
  Attributes *info;
  Contents *contents;
  Annotations *comments;

  NSPopUpButton *popUp;
  NSBox *contentBox;
  NSMutableArray *inspectorViews;
  NSArray *currentPaths;

  id viewer;
}

- (void)setViewer:(id)aViewer;
- (void)showSelection:(NSArray *)paths;
- (void)showContentsAt:(NSString *)path;
- (void)selectInspectorAtIndex:(int)index;

@end


/* The viewer hosting the preview pane receives this when the user changes
 * the inspector popup, so it can remember the selection per view type. */
@interface NSObject (GWViewerBrowserPreviewDelegate)
- (void)previewPane:(GWViewerBrowserPreview *)pane
  didSelectInspectorAtIndex:(int)index;
@end
