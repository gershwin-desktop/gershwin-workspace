/* GWDockWindow.m
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

#import "GWDockWindow.h"

#import <AppKit/AppKit.h>
#include <GNUstepGUI/GSDisplayServer.h>

#import "Dock.h"
#include <X11/Xlib.h>
#include <X11/Xatom.h>

/**
 * Custom X11 error handler for the dock window's X11 operations.
 * Silently ignores BadWindow/BadMatch errors from stale X11 windows.
 */
static int dockX11ErrorHandler(Display *dpy, XErrorEvent *event)
{
  char errorText[256];
  XGetErrorText(dpy, event->error_code, errorText, sizeof(errorText));
  NSDebugLLog(@"gwspace", @"GWDockWindow X11 error: %s (request %d, error %d)",
        errorText, event->request_code, event->error_code);
  return 0;
}

static BOOL dockX11ErrorHandlerInstalled = NO;

static void ensureDockX11ErrorHandler(void)
{
  if (!dockX11ErrorHandlerInstalled)
    {
      XSetErrorHandler(dockX11ErrorHandler);
      dockX11ErrorHandlerInstalled = YES;
    }
}

@implementation GWDockWindow

- (void)dealloc
{
  [super dealloc];
}

- (instancetype)initWithDockView:(Dock *)aDock
{
  /*
   * Start with a small default rect; the dock's -tile method will resize the
   * window to the correct size and position shortly after creation.
   */
  NSRect initRect = NSMakeRect(0, 0, 100, 100);

  self = [super initWithContentRect: initRect
                          styleMask: NSBorderlessWindowMask
                            backing: NSBackingStoreBuffered
                              defer: NO];
  if (self)
    {
      dockView = aDock;

      [self setContentView: dockView];
      [self setReleasedWhenClosed: NO];
      [self setExcludedFromWindowsMenu: YES];
      [self setAcceptsMouseMovedEvents: YES];
      [self setCanHide: NO];
      [self setHidesOnDeactivate: NO];
      [self setTitle: @"Dock"];

      /*
       * Use a level high enough to float above regular application windows
       * and the desktop, but below the main menu and status items.
       */
      [self setLevel: NSFloatingWindowLevel];

      /*
       * Allow the dock view's alpha-channel drawing (e.g. Modern style's
       * semi-transparent gray) to composite over the desktop below instead
       * of rendering against an opaque window backing store.
       */
      [self setOpaque: NO];
      [self setBackgroundColor: [NSColor clearColor]];
    }

  return self;
}

- (BOOL)canBecomeKeyWindow
{
  return NO;
}

- (BOOL)canBecomeMainWindow
{
  return NO;
}

- (void)showDock
{
  [self orderFront: nil];
  /*
   * Re-assert the window level after ordering front; the windowing system
   * can sometimes reset level after the initial order.
   */
  [self setLevel: NSFloatingWindowLevel];

  /*
   * Set X11 EWMH properties after the window is mapped so the window
   * manager sees them and treats this as a DOCK window (above others,
   * on all desktops, etc.).  This follows the same pattern used by
   * XDesktopWindow for its X11 property setup.
   */
  [self updateX11DockProperties];
  [self updateX11Strut];
}

- (void)hideDock
{
  [self orderOut: self];
}

- (Window)dockX11Window
{
  GSDisplayServer *srv = GSServerForWindow(self);
  if (srv == nil)
    return (Window)0;

  return (Window)(uintptr_t)[srv windowDevice: [self windowNumber]];
}

#pragma mark - X11 Dock Properties

- (void)updateX11DockProperties
{
  ensureDockX11ErrorHandler();

  Display *display = XOpenDisplay(NULL);
  if (display == nil)
    return;

  /* Ensure the display connection uses our error handler */
  XSetErrorHandler(dockX11ErrorHandler);

  Window dockXWindow = [self dockX11Window];
  if (dockXWindow == (Window)0)
    {
      XCloseDisplay(display);
      return;
    }

  /* ---- _NET_WM_WINDOW_TYPE (_NET_WM_WINDOW_TYPE_DOCK) ---- */
  Atom netWmWindowType = XInternAtom(display, "_NET_WM_WINDOW_TYPE", False);
  Atom netWmWindowTypeDock = XInternAtom(display, "_NET_WM_WINDOW_TYPE_DOCK", False);
  XChangeProperty(display, dockXWindow, netWmWindowType, XA_ATOM, 32,
                  PropModeReplace, (unsigned char *)&netWmWindowTypeDock, 1);

  /* ---- _NET_WM_STATE (ABOVE | STICKY) ---- */
  Atom netWmState = XInternAtom(display, "_NET_WM_STATE", False);
  Atom netWmStateAbove = XInternAtom(display, "_NET_WM_STATE_ABOVE", False);
  Atom netWmStateSticky = XInternAtom(display, "_NET_WM_STATE_STICKY", False);
  Atom states[2] = { netWmStateAbove, netWmStateSticky };
  XChangeProperty(display, dockXWindow, netWmState, XA_ATOM, 32,
                  PropModeReplace, (unsigned char *)states, 2);

  /* ---- _NET_WM_DESKTOP (0xFFFFFFFF = all desktops) ---- */
  Atom netWmDesktop = XInternAtom(display, "_NET_WM_DESKTOP", False);
  unsigned long allDesktops = 0xFFFFFFFFUL;
  XChangeProperty(display, dockXWindow, netWmDesktop, XA_CARDINAL, 32,
                  PropModeReplace, (unsigned char *)&allDesktops, 1);

  XFlush(display);
  XCloseDisplay(display);

  NSDebugLLog(@"gwspace", @"GWDockWindow: set X11 dock properties on window 0x%lx",
              (unsigned long)dockXWindow);
}

- (void)updateX11Strut
{
  ensureDockX11ErrorHandler();

  Display *display = XOpenDisplay(NULL);
  if (display == nil)
    return;

  XSetErrorHandler(dockX11ErrorHandler);

  Window dockXWindow = [self dockX11Window];
  if (dockXWindow == (Window)0)
    {
      XCloseDisplay(display);
      return;
    }

  NSRect windowFrame = [self frame];

  DockPosition pos = [dockView position];

  /*
   * _NET_WM_STRUT: left, right, top, bottom
   * _NET_WM_STRUT_PARTIAL: left, right, top, bottom,
   *                        left_start_y, left_end_y,
   *                        right_start_y, right_end_y,
   *                        top_start_x, top_end_x,
   *                        bottom_start_x, bottom_end_x
   */
  unsigned long strutPartial[12] = { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 };

  switch (pos)
    {
      case DockPositionLeft:
        strutPartial[0] = (unsigned long)windowFrame.size.width;  /* left */
        strutPartial[4] = (unsigned long)windowFrame.origin.y;    /* left_start_y */
        strutPartial[5] = (unsigned long)(windowFrame.origin.y
                                          + windowFrame.size.height); /* left_end_y */
        break;

      case DockPositionRight:
        strutPartial[1] = (unsigned long)windowFrame.size.width;  /* right */
        strutPartial[6] = (unsigned long)windowFrame.origin.y;    /* right_start_y */
        strutPartial[7] = (unsigned long)(windowFrame.origin.y
                                          + windowFrame.size.height); /* right_end_y */
        break;

      case DockPositionBottom:
        strutPartial[3] = (unsigned long)windowFrame.size.height; /* bottom */
        strutPartial[10] = (unsigned long)windowFrame.origin.x;   /* bottom_start_x */
        strutPartial[11] = (unsigned long)(windowFrame.origin.x
                                           + windowFrame.size.width); /* bottom_end_x */
        break;
    }

  Atom netWmStrut = XInternAtom(display, "_NET_WM_STRUT", False);
  Atom netWmStrutPartial = XInternAtom(display, "_NET_WM_STRUT_PARTIAL", False);

  /* _NET_WM_STRUT uses the first four values */
  XChangeProperty(display, dockXWindow, netWmStrut, XA_CARDINAL, 32,
                  PropModeReplace, (unsigned char *)strutPartial, 4);

  /* _NET_WM_STRUT_PARTIAL uses all twelve */
  XChangeProperty(display, dockXWindow, netWmStrutPartial, XA_CARDINAL, 32,
                  PropModeReplace, (unsigned char *)strutPartial, 12);

  XFlush(display);
  XCloseDisplay(display);

  NSDebugLLog(@"gwspace", @"GWDockWindow: set X11 strut (pos %d, size %@)",
              pos, NSStringFromSize(windowFrame.size));
}

@end
