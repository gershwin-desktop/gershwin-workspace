/* GWDockWindow.h
 *
 * Copyright (C) 2025 Free Software Foundation, Inc.
 *
 * Author: Gershwin Team
 * Date: June 2025
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

@class Dock;

/**
 * GWDockWindow is a borderless NSWindow that presents the Dock as its own
 * X11 window, annotated with _NET_WM_WINDOW_TYPE_DOCK so the window manager
 * recognizes it as a dock/panel.  It floats above ordinary windows, never
 * becomes key or main, and sets _NET_WM_STRUT to reserve screen space.
 */
@interface GWDockWindow : NSWindow
{
  Dock *dockView;
}

- (instancetype)initWithDockView:(Dock *)aDock;

/**
 * Show or hide the dock window.
 */
- (void)showDock;
- (void)hideDock;

/**
 * Update _NET_WM_STRUT and _NET_WM_STRUT_PARTIAL based on the dock's
 * current position and size.  Call after the dock has been tiled.
 */
- (void)updateX11Strut;

/**
 * Re-apply the X11 dock type and state properties.
 * Called once during init; safe to call again if needed.
 */
- (void)updateX11DockProperties;

@end
