/* DockWindow.h
 *
 * Copyright (C) 2026 Free Software Foundation, Inc.
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

#import <AppKit/NSWindow.h>
#import "GWDesktopManager.h"

@class Dock;

/**
 * DockWindow is a separate top-level X11 window for the Dock.
 * It sets _NET_WM_WINDOW_TYPE_DOCK so window managers treat it
 * as a dock panel (always visible, above other windows, excluded
 * from task lists).  It also sets _NET_WM_STRUT_PARTIAL so that
 * other windows' maximize area excludes the dock strip.
 */
@interface DockWindow : NSWindow

/**
 * Designated initialiser.
 * @param pos  Current dock position (left / right / bottom).
 */
- (id)initWithPosition:(DockPosition)pos;

/**
 * Show the dock window at the correct level and set X11 atoms.
 */
- (void)activate;

/**
 * Hide the dock window.
 */
- (void)deactivate;

/**
 * Call after the Dock view has tiled so the window frame matches
 * the new content size, and X11 struts are refreshed.
 */
- (void)updateFrameForDock;

/**
 * Update the dock position and refresh X11 atoms/struts.
 */
- (void)setDockPosition:(DockPosition)pos;

@end
