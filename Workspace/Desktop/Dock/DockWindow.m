/* DockWindow.m
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

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#include <GNUstepGUI/GSDisplayServer.h>
#include <X11/Xlib.h>
#include <X11/Xatom.h>

/* Make Xcomposite optional at compile time */
#if defined(__has_include)
# if __has_include(<X11/extensions/Xcomposite.h>)
#  include <X11/extensions/Xcomposite.h>
#  define HAVE_XCOMPOSITE 1
# else
#  define HAVE_XCOMPOSITE 0
# endif
#else
# define HAVE_XCOMPOSITE 0
#endif

#import "DockWindow.h"
#import "Dock.h"

@implementation DockWindow
{
  DockPosition _position;
}

- (id)initWithPosition:(DockPosition)pos
{
  /* Start with a small frame; updateFrameForDock will resize it. */
  NSRect frame = NSMakeRect(0, 0, 64, 64);

  self = [super initWithContentRect:frame
                          styleMask:NSBorderlessWindowMask
                            backing:NSBackingStoreBuffered
                              defer:NO];
  if (self)
    {
      _position = pos;

      [self setReleasedWhenClosed:NO];
      [self setExcludedFromWindowsMenu:YES];
      [self setAcceptsMouseMovedEvents:YES];
      [self setCanHide:NO];
      [self setTitle:@"Dock"];

      /* If a compositor is present, enable true window transparency
         (use non-opaque window with a clear background and draw the
         dock view with a 50% alpha). */
      BOOL compositorActive = NO;
      Class compCls = NSClassFromString(@"URSCompositingManager");
      if (compCls) {
        id cm = [compCls performSelector:@selector(sharedManager)];
        if (cm && [cm respondsToSelector:@selector(compositingActive)]) {
          BOOL (*getCompActive)(id, SEL) = (BOOL (*)(id, SEL))[cm methodForSelector:@selector(compositingActive)];
          compositorActive = getCompActive ? getCompActive(cm, @selector(compositingActive)) : NO;
        }
      }
#if defined(__linux__) && HAVE_XCOMPOSITE
      if (!compositorActive) {
        Display *dpy = XOpenDisplay(NULL);
        if (dpy) {
          int ev, er;
          if (XCompositeQueryExtension(dpy, &ev, &er)) {
            Atom sel = XInternAtom(dpy, "_NET_WM_CM_S0", False);
            Window owner = XGetSelectionOwner(dpy, sel);
            if (owner != None) compositorActive = YES;
          }
          XCloseDisplay(dpy);
        }
      }
#endif

      if (compositorActive) {
        [self setOpaque:NO];
        [self setBackgroundColor:[NSColor clearColor]];
      }

      /* Floating-panel level keeps dock above normal windows.
         The X11 atoms below make the WM enforce this too. */
      [self setLevel:NSFloatingWindowLevel];

      NSLog(@"DockWindow: created with position %d", (int)pos);
    }
  return self;
}

#pragma mark - X11 helpers

/**
 * Set _NET_WM_WINDOW_TYPE to _NET_WM_WINDOW_TYPE_DOCK on our X11 window.
 * This tells any EWMH-compliant window manager that we are a dock.
 */
- (void)_setDockTypeAtom
{
  GSDisplayServer *srv = GSServerForWindow(self);
  if (!srv) {
    NSLog(@"DockWindow: no display server – skipping X11 atoms");
    return;
  }

  Window xwin = (Window)(uintptr_t)[srv windowDevice:[self windowNumber]];
  if (!xwin) {
    NSLog(@"DockWindow: no X11 window id – skipping X11 atoms");
    return;
  }

  Display *dpy = XOpenDisplay(NULL);
  if (!dpy) {
    NSLog(@"DockWindow: XOpenDisplay failed");
    return;
  }

  Atom wmWindowType   = XInternAtom(dpy, "_NET_WM_WINDOW_TYPE",      False);
  Atom typeDock       = XInternAtom(dpy, "_NET_WM_WINDOW_TYPE_DOCK", False);
  Atom wmState        = XInternAtom(dpy, "_NET_WM_STATE",            False);
  Atom stateAbove     = XInternAtom(dpy, "_NET_WM_STATE_ABOVE",      False);
  Atom stateSticky    = XInternAtom(dpy, "_NET_WM_STATE_STICKY",     False);
  Atom stateSkipTB    = XInternAtom(dpy, "_NET_WM_STATE_SKIP_TASKBAR", False);
  Atom stateSkipPager = XInternAtom(dpy, "_NET_WM_STATE_SKIP_PAGER", False);

  /* Window type */
  XChangeProperty(dpy, xwin, wmWindowType, XA_ATOM, 32,
                  PropModeReplace, (unsigned char *)&typeDock, 1);

  /* State: above + sticky + skip-taskbar + skip-pager */
  Atom states[4] = { stateAbove, stateSticky, stateSkipTB, stateSkipPager };
  XChangeProperty(dpy, xwin, wmState, XA_ATOM, 32,
                  PropModeReplace, (unsigned char *)states, 4);

  XFlush(dpy);
  XCloseDisplay(dpy);

  NSLog(@"DockWindow: set _NET_WM_WINDOW_TYPE_DOCK on xwin 0x%lx", xwin);
}

/**
 * Set _NET_WM_STRUT_PARTIAL so that maximised windows don't
 * overlap the dock area.
 *
 * The 12-value array is:
 *   left, right, top, bottom,
 *   left_start_y, left_end_y,
 *   right_start_y, right_end_y,
 *   top_start_x, top_end_x,
 *   bottom_start_x, bottom_end_x
 */
- (void)_setStrutAtom
{
  GSDisplayServer *srv = GSServerForWindow(self);
  if (!srv) return;

  Window xwin = (Window)(uintptr_t)[srv windowDevice:[self windowNumber]];
  if (!xwin) return;

  Display *dpy = XOpenDisplay(NULL);
  if (!dpy) return;

  NSRect scr = [[NSScreen mainScreen] frame];
  NSRect fr  = [self frame];

  /* Convert GNUstep frame (origin at lower-left) to X11 (origin at
     upper-left) for the strut start/end values. */
  CGFloat screenH = scr.size.height;

  long strut[12] = {0};

  switch (_position)
    {
    case DockPositionLeft:
      strut[0] = (long)ceil(fr.size.width);     /* left */
      strut[4] = 0;                              /* left_start_y */
      strut[5] = (long)screenH - 1;              /* left_end_y */
      break;
    case DockPositionRight:
      strut[1] = (long)ceil(fr.size.width);      /* right */
      strut[6] = 0;                              /* right_start_y */
      strut[7] = (long)screenH - 1;              /* right_end_y */
      break;
    case DockPositionBottom:
      strut[3] = (long)ceil(fr.size.height);     /* bottom */
      strut[10] = 0;                             /* bottom_start_x */
      strut[11] = (long)scr.size.width - 1;      /* bottom_end_x */
      break;
    }

  Atom strutPartial = XInternAtom(dpy, "_NET_WM_STRUT_PARTIAL", False);
  Atom strutAtom    = XInternAtom(dpy, "_NET_WM_STRUT",         False);

  XChangeProperty(dpy, xwin, strutPartial, XA_CARDINAL, 32,
                  PropModeReplace, (unsigned char *)strut, 12);
  /* Legacy strut (just the first 4 values) */
  XChangeProperty(dpy, xwin, strutAtom, XA_CARDINAL, 32,
                  PropModeReplace, (unsigned char *)strut, 4);

  XFlush(dpy);
  XCloseDisplay(dpy);

  NSLog(@"DockWindow: set _NET_WM_STRUT_PARTIAL (l=%ld r=%ld t=%ld b=%ld)",
        strut[0], strut[1], strut[2], strut[3]);
}

#pragma mark - Public API

- (void)activate
{
  NSLog(@"DockWindow: activate");
  [self setLevel:NSFloatingWindowLevel];
  [self orderFront:nil];

  /* The X11 window ID is only available after the window has been
     mapped, so we set atoms after orderFront.  */
  [self _setDockTypeAtom];
  [self _setStrutAtom];
}

- (void)deactivate
{
  NSLog(@"DockWindow: deactivate");
  [self orderOut:self];
}

- (void)updateFrameForDock
{
  Dock *dock = (Dock *)[self contentView];
  if (!dock) return;

  NSRect dockFrame = [dock frame];
  NSRect screenFrame = [[NSScreen mainScreen] frame];

  /* Dock view frame origin is (0,0) from tile().
     We compute the window position based on dock position and screen geometry. */
  NSRect winFrame = NSZeroRect;
  winFrame.size = dockFrame.size;

  switch (_position)
    {
    case DockPositionLeft:
      winFrame.origin.x = 0;
      winFrame.origin.y = ceil((screenFrame.size.height - winFrame.size.height) / 2);
      break;
    case DockPositionRight:
      winFrame.origin.x = screenFrame.size.width - winFrame.size.width;
      winFrame.origin.y = ceil((screenFrame.size.height - winFrame.size.height) / 2);
      break;
    case DockPositionBottom:
      winFrame.origin.x = ceil((screenFrame.size.width - winFrame.size.width) / 2);
      winFrame.origin.y = 0;
      break;
    }

  [self setFrame:winFrame display:YES];

  /* Dock view is positioned at (0,0) inside the window. */
  [dock setFrameOrigin:NSZeroPoint];

  /* Refresh struts so maximised windows respect the new size. */
  if ([self isVisible]) {
    [self _setStrutAtom];
  }

  NSLog(@"DockWindow: updateFrameForDock -> %@ (pos=%d)", NSStringFromRect(winFrame), (int)_position);
}

- (void)setDockPosition:(DockPosition)pos
{
  _position = pos;
  [self updateFrameForDock];
  if ([self isVisible]) {
    [self _setDockTypeAtom];
    [self _setStrutAtom];
  }
}

#pragma mark - NSWindow overrides

- (BOOL)canBecomeKeyWindow
{
  return NO;
}

- (BOOL)canBecomeMainWindow
{
  return NO;
}

/* Keep the dock at its floating level even when other windows are
   re-ordered. */
- (void)orderWindow:(NSWindowOrderingMode)place
         relativeTo:(NSInteger)otherWin
{
  [super orderWindow:place relativeTo:otherWin];
  [self setLevel:NSFloatingWindowLevel];
}

@end
