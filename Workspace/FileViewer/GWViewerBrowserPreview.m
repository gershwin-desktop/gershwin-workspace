/*
 * GWViewerBrowserPreview.m
 *
 * Rightmost pane of the Miller columns in a browser viewer: shows the
 * "Contents" inspector (like the Contents tab of Get Info) for the
 * currently selected file.  It reuses the Inspector framework's Contents
 * class so every content viewer (images, text, archives, ...) works here
 * too.  The pane also acts as the minimal "inspector" adapter the
 * Contents class needs for watchers and window title updates.
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
#import "Contents.h"

@implementation GWViewerBrowserPreview

- (void)dealloc
{
  RELEASE (contents);
  [super dealloc];
}

- (id)initWithFrame:(NSRect)frameRect
{
  self = [super initWithFrame: frameRect];

  if (self)
    {
      NSView *iv;

      contents = [[Contents alloc] initForInspector: self];
      iv = [contents inspView];
      [iv setFrame: [self bounds]];
      [iv setAutoresizingMask: NSViewWidthSizable | NSViewHeightSizable];
      [self addSubview: iv];
      RELEASE (iv);
    }

  return self;
}

- (void)showSelection:(NSArray *)paths
{
  if (paths && [paths count])
    {
      [contents activateForPaths: paths];
    }
}

- (void)showContentsAt:(NSString *)path
{
  [contents showContentsAt: path];
}

/* Minimal inspector adapter used by the Contents class and its viewers. */

- (void)addWatcherForPath:(NSString *)path
{
  /* File watching is handled by the real Inspector window; the preview
   * pane re-renders on every selection change, so no watcher is needed. */
}

- (void)removeWatcherForPath:(NSString *)path
{
}

- (NSWindow *)win
{
  /* The Contents class sets the inspector window's title on display; the
   * preview pane must not retitle the viewer window, so return nil. */
  return nil;
}

- (Class)class
{
  return [super class];
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
