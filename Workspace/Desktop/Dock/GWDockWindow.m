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
#import "FSNSpringLoader.h"
#import "DockStack.h"
#import "DockLabel.h"
#ifndef _WIN32
#include <X11/Xlib.h>
#include <X11/Xatom.h>
#include <X11/extensions/shape.h>
#import "PrimaryMonitor.h"
#endif

@implementation GWDockWindow

- (void)dealloc
{
  [super dealloc];
}

/* A drop on the Dock ends a drag like one anywhere else: the loader closes
 * what sprang open on the way, and must know before the drop is handled. */
- (void)sendEvent:(NSEvent *)theEvent
{
  [[FSNSpringLoader sharedLoader] noteEvent: theEvent inWindow: self];
  [DockStack noteEvent: theEvent inWindow: self];
  [DockLabel noteEvent: theEvent inWindow: self];
  [super sendEvent: theEvent];
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

- (void)performClose:(id)sender
{
  NSLog(@"GWDockWindow performClose: called - IGNORED (dock cannot be closed)");
}

- (void)showDock
{
  /* Set before the window is mapped, so that the window manager has the
   * window type and the strut when it first sees the Dock instead of a
   * moment later. */
  [self updateX11DockProperties];
  [self updateX11Strut];
  [dockView decorateIcons];
  [self orderFront: nil];
  /*
   * Re-assert the window level after ordering front; the windowing system
   * can sometimes reset level after the initial order.
   */
  [self setLevel: NSFloatingWindowLevel];

  /*
   * Set X11 EWMH properties after the window is mapped so the window
   * manager sees them and treats this as a DOCK window (dock layer,
   * on all desktops, etc.).  This follows the same pattern used by
   * XDesktopWindow for its X11 property setup.
   */
  [self updateX11DockProperties];
  [self updateX11Strut];
  /* Mapped anew: X knows nothing of the shape given before. */
  inputRect = NSMakeRect(-1, -1, 0, 0);
  [dockView updateInputShape];
  [dockView setMagnificationTracking: YES];
}

- (void)hideDock
{
  [dockView setMagnificationTracking: NO];
  [DockLabel hide];
  [self orderOut: self];
}

#ifndef _WIN32
- (Window)dockX11Window
{
  GSDisplayServer *srv = GSServerForWindow(self);
  if (srv == nil)
    return (Window)0;

  return (Window)(uintptr_t)[srv windowDevice: [self windowNumber]];
}

/* The process already holds an X11 connection through the GNUstep backend;
 * reuse it instead of opening (and leaking) a fresh Display on every call.
 * Never XCloseDisplay this — it belongs to the backend. */
- (Display *)dockDisplay
{
  GSDisplayServer *srv = GSServerForWindow(self);
  if (srv == nil)
    srv = GSCurrentServer();
  if (srv == nil)
    return NULL;
  return (Display *)[srv serverDevice];
}
#endif

- (void)setInputRect:(NSRect)rect
{
#ifndef _WIN32
  Display *display = [self dockDisplay];
  Window xwin = [self dockX11Window];
  CGFloat sf = [self userSpaceScaleFactor];
  CGFloat h = NSHeight([self frame]);
  NSRect px = NSZeroRect;

  if (display == NULL || xwin == (Window)0)
    return;
  if (sf <= 0.0)
    sf = 1.0;

  /* X measures from the top left, in pixels; rounded outwards so the bar's
   * edge pixels still take the pointer (Fitts: the screen edge row). */
  if (NSIsEmptyRect(rect) == NO)
    {
      CGFloat x0 = floor(NSMinX(rect) * sf);
      CGFloat x1 = ceil(NSMaxX(rect) * sf);
      CGFloat y0 = floor(h - NSMaxY(rect) * sf);
      CGFloat y1 = ceil(h - NSMinY(rect) * sf);

      px = NSMakeRect(x0, y0, x1 - x0, y1 - y0);
    }

  /* Asked again on every layout; X is only told about a change. */
  if (NSEqualRects(px, inputRect))
    return;
  inputRect = px;

  if (NSIsEmptyRect(px))
    {
      XShapeCombineMask(display, xwin, ShapeInput, 0, 0, None, ShapeSet);
    }
  else
    {
      XRectangle r;

      r.x = (short)NSMinX(px);
      r.y = (short)NSMinY(px);
      r.width = (unsigned short)NSWidth(px);
      r.height = (unsigned short)NSHeight(px);
      XShapeCombineRectangles(display, xwin, ShapeInput, 0, 0, &r, 1,
                              ShapeSet, Unsorted);
    }
  XFlush(display);
#endif
}

#pragma mark - X11 Dock Properties

- (void)updateX11DockProperties
{
#ifndef _WIN32
  Display *display = [self dockDisplay];
  if (display == NULL)
    return;

  Window dockXWindow = [self dockX11Window];
  if (dockXWindow == (Window)0)
    return;

  /* ---- _NET_WM_WINDOW_TYPE (_NET_WM_WINDOW_TYPE_DOCK) ---- */
  Atom netWmWindowType = XInternAtom(display, "_NET_WM_WINDOW_TYPE", False);
  Atom netWmWindowTypeDock = XInternAtom(display, "_NET_WM_WINDOW_TYPE_DOCK", False);
  XChangeProperty(display, dockXWindow, netWmWindowType, XA_ATOM, 32,
                  PropModeReplace, (unsigned char *)&netWmWindowTypeDock, 1);

  /*
   * ---- _NET_WM_STATE (SKIP_TASKBAR | SKIP_PAGER | STICKY) ----
   *
   * _NET_WM_STATE_ABOVE is intentionally NOT set; a DOCK-type window
   * belongs in the WM's dock stacking layer (above normal windows but
   * below menus, tooltips, and popups).  Adding _NET_WM_STATE_ABOVE
   * can push the dock higher than intended, competing with transient
   * UI elements.  Compliant WMs handle the DOCK type's layer placement
   * automatically.
   */
  Atom netWmState = XInternAtom(display, "_NET_WM_STATE", False);
  Atom netWmStateSkipTaskbar = XInternAtom(display, "_NET_WM_STATE_SKIP_TASKBAR", False);
  Atom netWmStateSkipPager = XInternAtom(display, "_NET_WM_STATE_SKIP_PAGER", False);
  Atom netWmStateSticky = XInternAtom(display, "_NET_WM_STATE_STICKY", False);
  Atom states[3] = { netWmStateSkipTaskbar, netWmStateSkipPager, netWmStateSticky };
  XChangeProperty(display, dockXWindow, netWmState, XA_ATOM, 32,
                  PropModeReplace, (unsigned char *)states, 3);

  /* ---- _NET_WM_DESKTOP (0xFFFFFFFF = all desktops) ---- */
  Atom netWmDesktop = XInternAtom(display, "_NET_WM_DESKTOP", False);
  unsigned long allDesktops = 0xFFFFFFFFUL;
  XChangeProperty(display, dockXWindow, netWmDesktop, XA_CARDINAL, 32,
                  PropModeReplace, (unsigned char *)&allDesktops, 1);

  XFlush(display);
#endif

}

- (void)updateX11Strut
{
#ifndef _WIN32
  Display *display = [self dockDisplay];
  if (display == NULL)
    return;

  Window dockXWindow = [self dockX11Window];
  if (dockXWindow == (Window)0)
    return;

  /* The bar is what the Dock takes up; the room its magnified icons reach
   * into is not reserved, or the windows below would move out of the way of
   * an effect that is gone as soon as the pointer is. */
  NSRect windowFrame = [dockView barFrame];

  if (NSIsEmptyRect(windowFrame))
    windowFrame = [self frame];

  /* EWMH struts are measured from the edges of the root window, not of the
   * monitor the Dock is on, and in root coordinates with Y from the top;
   * NSWindow frames are bottom-left origin over the whole X screen.  A Dock
   * on a monitor that does not reach the root edge it is attached to (a
   * shorter monitor, or one with another beside it) reserves up to that
   * edge, over its own extent only. */
  NSSize rootSize = NSMakeSize(DisplayWidth(display, DefaultScreen(display)),
                               DisplayHeight(display, DefaultScreen(display)));
  NSRect barXRect = PrimaryMonitorFlipRect(windowFrame, rootSize.height);
  PrimaryMonitorEdge edge;

  switch ([dockView position])
    {
      case DockPositionLeft:
        edge = PrimaryMonitorEdgeLeft;
        break;
      case DockPositionRight:
        edge = PrimaryMonitorEdgeRight;
        break;
      case DockPositionBottom:
      default:
        edge = PrimaryMonitorEdgeBottom;
        break;
    }

  /*
   * _NET_WM_STRUT: left, right, top, bottom
   * _NET_WM_STRUT_PARTIAL: left, right, top, bottom,
   *                        left_start_y, left_end_y,
   *                        right_start_y, right_end_y,
   *                        top_start_x, top_end_x,
   *                        bottom_start_x, bottom_end_x
   */
  unsigned long strutPartial[12];
  PrimaryMonitorStrutForPanel(barXRect, rootSize, edge, strutPartial);

  Atom netWmStrut = XInternAtom(display, "_NET_WM_STRUT", False);
  Atom netWmStrutPartial = XInternAtom(display, "_NET_WM_STRUT_PARTIAL", False);

  /* _NET_WM_STRUT uses the first four values */
  XChangeProperty(display, dockXWindow, netWmStrut, XA_CARDINAL, 32,
                  PropModeReplace, (unsigned char *)strutPartial, 4);

  /* _NET_WM_STRUT_PARTIAL uses all twelve */
  XChangeProperty(display, dockXWindow, netWmStrutPartial, XA_CARDINAL, 32,
                  PropModeReplace, (unsigned char *)strutPartial, 12);

  XFlush(display);
#endif

}

@end
