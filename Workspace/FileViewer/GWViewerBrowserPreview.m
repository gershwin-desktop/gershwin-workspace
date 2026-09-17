/*
 * GWViewerBrowserPreview.m
 *
 * Rightmost pane of the browser viewer: shows the same information as the
 * Get Info Inspector window, but in a compact fixed-width pane.  A popup
 * button at the top switches between the Info, Contents and Comments
 * inspectors, whose views are swapped in the content box below - exactly
 * like the Inspector window.  The pane reuses the Inspector framework's
 * Attributes (Info), Contents and Annotations (Comments) classes, and acts
 * as the minimal "inspector" adapter they need for watchers, the desktop
 * application and window title updates.
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
#import "GWViewerBrowserPreview.h"
#import "Attributes.h"
#import "Contents.h"
#import "Annotations.h"
#import "FSNode.h"
#import "Workspace.h"

#define GW_PREVIEW_POPUP_HEIGHT 24.0

@implementation GWViewerBrowserPreview

- (void)dealloc
{
  /* Stop any background work (e.g. the GenericView `file` task, image
   * loaders) before releasing the inspectors, so no notification observer
   * is left pointing into freed memory when the window closes. */
  if (contents && [contents respondsToSelector: @selector(stopTasks)])
    {
      [contents stopTasks];
    }
  RELEASE (info);
  RELEASE (contents);
  RELEASE (comments);
  RELEASE (inspectorViews);
  RELEASE (currentPaths);
  [super dealloc];
}

- (void)setViewer:(id)aViewer
{
  viewer = aViewer;
}

/* Creates one inspector, keeping its view in the given array slot. */
- (void)createInspector:(id *)inspector
              withClass:(Class)cls
                 inArray:(NSMutableArray *)views
{
  *inspector = [[cls alloc] initForInspector: self];
  if (*inspector)
    {
      NSView *iv = [*inspector inspView];
      [iv setAutoresizingMask: NSViewWidthSizable | NSViewHeightSizable];
      [views addObject: iv];
    }
  else
    {
      [views addObject: [NSNull null]];
    }
}

- (id)initWithFrame:(NSRect)frameRect
{
  self = [super initWithFrame: frameRect];

  if (self)
    {
      NSRect r = [self bounds];
      CGFloat w = r.size.width;
      CGFloat h = r.size.height;
      NSRect popupRect, boxRect;

      inspectorViews = [NSMutableArray new];

      /* Popup at the top to switch between the inspectors. */
      popupRect = NSMakeRect(0, h - GW_PREVIEW_POPUP_HEIGHT,
                             w, GW_PREVIEW_POPUP_HEIGHT);
      popUp = [[NSPopUpButton alloc] initWithFrame: popupRect pullsDown: NO];
      [popUp setAutoresizingMask: NSViewMinYMargin | NSViewWidthSizable];

      /* Info */
      [self createInspector: &info withClass: [Attributes class]
                    inArray: inspectorViews];
      [popUp addItemWithTitle: NSLocalizedString(@"Info", @"")];

      /* Contents */
      [self createInspector: &contents withClass: [Contents class]
                    inArray: inspectorViews];
      [popUp addItemWithTitle: NSLocalizedString(@"Contents", @"")];

      /* Comments */
      [self createInspector: &comments withClass: [Annotations class]
                    inArray: inspectorViews];
      [popUp addItemWithTitle: NSLocalizedString(@"Comments", @"")];

      [popUp setTarget: self];
      [popUp setAction: @selector(switchInspector:)];
      [self addSubview: popUp];
      RELEASE (popUp);

      /* Content box below the popup: hosts the selected inspector's view. */
      boxRect = NSMakeRect(0, 0, w, h - GW_PREVIEW_POPUP_HEIGHT);
      contentBox = [[NSBox alloc] initWithFrame: boxRect];
      [contentBox setTitlePosition: NSNoTitle];
      [contentBox setBorderType: NSNoBorder];
      [contentBox setContentViewMargins: NSZeroSize];
      [contentBox setAutoresizingMask: NSViewHeightSizable | NSViewWidthSizable];
      [self addSubview: contentBox];
      RELEASE (contentBox);

      /* Show the first inspector (Info) by default. */
      [popUp selectItemAtIndex: 0];
      [self switchInspector: popUp];
    }

  return self;
}

/* Swaps the inspector view shown in the content box to match the popup. */
- (void)switchInspector:(id)sender
{
  NSInteger index = [sender indexOfSelectedItem];
  [self selectInspectorAtIndex: index];
  if (viewer && [viewer respondsToSelector:
                          @selector(previewPane:didSelectInspectorAtIndex:)])
    {
      [viewer previewPane: self didSelectInspectorAtIndex: index];
    }
}

/* Selects the inspector at the given index, updating the popup and the
 * content box.  Used both by the popup action and to restore a remembered
 * selection for the view type. */
- (void)selectInspectorAtIndex:(int)index
{
  if (index < 0 || index >= [inspectorViews count])
    {
      return;
    }
  if (popUp && [popUp indexOfSelectedItem] != index)
    {
      [popUp selectItemAtIndex: index];
    }
  id view = [inspectorViews objectAtIndex: index];
  if (view == [NSNull null])
    {
      return;
    }
  [contentBox setContentView: view];

  /* Refresh the newly selected inspector with the current selection. */
  if (currentPaths)
    {
      [self activateInspectorAtIndex: index];
    }
}

/* Activates the inspector at the given popup index with the current paths. */
- (void)activateInspectorAtIndex:(NSInteger)index
{
  if (index == 0 && info)
    {
      [info activateForPaths: currentPaths];
    }
  else if (index == 1 && contents)
    {
      [contents activateForPaths: currentPaths];
    }
  else if (index == 2 && comments)
    {
      [comments activateForPaths: currentPaths];
    }
}

- (void)showSelection:(NSArray *)selection
{
  /* The viewers pass FSNode objects; the inspectors expect path strings.
   * Convert here so both call sites (GWViewer and GWSpatialViewer) can pass
   * their node selection unchanged. */
  if (selection && [selection count])
    {
      NSMutableArray *paths = [NSMutableArray arrayWithCapacity: [selection count]];
      for (id obj in selection)
        {
          if ([obj isKindOfClass: [FSNode class]])
            {
              [paths addObject: [obj path]];
            }
          else if ([obj isKindOfClass: [NSString class]])
            {
              [paths addObject: obj];
            }
        }
      if ([paths count])
        {
          ASSIGN (currentPaths, paths);
          [self activateInspectorAtIndex: [popUp indexOfSelectedItem]];
        }
    }
  else
    {
      DESTROY (currentPaths);
    }
}

- (void)showContentsAt:(NSString *)path
{
  if (contents && [contents respondsToSelector: @selector(showContentsAt:)])
    {
      [contents showContentsAt: path];
    }
}

/* Minimal inspector adapter used by the Inspector classes and their views. */

- (void)addWatcherForPath:(NSString *)path
{
  [[Workspace gworkspace] addWatcherForPath: path];
}

- (void)removeWatcherForPath:(NSString *)path
{
  [[Workspace gworkspace] removeWatcherForPath: path];
}

- (id)desktopApp
{
  return [Workspace gworkspace];
}

- (NSWindow *)win
{
  /* The Contents class sets the inspector window's title on display; the
   * preview pane must not retitle the viewer window, so return nil. */
  return nil;
}

- (NSDragOperation)draggingEntered:(id <NSDraggingInfo>)sender
                        inIconView:(id)iview
{
  return NSDragOperationNone;
}

- (void)draggingExited:(id <NSDraggingInfo>)sender
            inIconView:(id)iview
{
}

- (void)concludeDragOperation:(id <NSDraggingInfo>)sender
                    inIconView:(id)iview
{
}

@end
