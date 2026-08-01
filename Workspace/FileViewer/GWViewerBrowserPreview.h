/*
 * GWViewerBrowserPreview.h
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

@class Contents;

@interface GWViewerBrowserPreview : NSView
{
  Contents *contents;
}

- (void)showSelection:(NSArray *)paths;
- (void)showContentsAt:(NSString *)path;

@end
