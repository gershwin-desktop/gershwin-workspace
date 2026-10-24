/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

/* The toolbar of a browsing viewer window: its NSToolbar delegate, the item
 * views and their actions.  Every action reuses what the menus already do;
 * which control is usable when is decided by GWViewerToolbarModel. */

#import <AppKit/AppKit.h>

@class GWViewer;

@interface GWViewerToolbar : NSObject {
  GWViewer *viewer; /* not retained: the viewer owns this object */
  NSToolbar *toolbar;
}

- (id)initForViewer:(GWViewer *)aViewer;

- (NSToolbar *)toolbar;

/* The viewer is going away: the toolbar must not call back into it. */
- (void)invalidate;

@end
