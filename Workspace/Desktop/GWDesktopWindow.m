/* GWDesktopWindow.m
 *  
 * Copyright (C) 2005-2012 Free Software Foundation, Inc.
 *
 * Author: Enrico Sersale
 *         Riccardo Mottola
 * Date: January 2005
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
#import <GNUstepGUI/GSDisplayServer.h>
#ifndef _WIN32
#import <X11/Xlib.h>
#import <X11/Xatom.h>
#endif

#import "GWDesktopWindow.h"
#ifndef _WIN32
#import "PrimaryMonitor.h"
#endif
#import "GWDesktopManager.h"
#import "FSNSpringLoader.h"
#import "Dock/DockStack.h"
#import "X11AppSupport.h"
#include <unistd.h>

@implementation GWDesktopWindow

/* Spring-loaded folders follow a drag across windows, and a window's drag
 * events only pass through here.  The loader hears of an event before it is
 * handled: handling a drop can run a confirmation panel, and the loader must
 * know where the drop landed before that.  A press on the Desktop also puts
 * away a Dock stack that is open. */
- (void)sendEvent:(NSEvent *)theEvent
{
  [[FSNSpringLoader sharedLoader] noteEvent: theEvent inWindow: self];
  [DockStack noteEvent: theEvent inWindow: self];
  /* A click on the desktop makes Workspace the frontmost application.  The
   * window manager cannot tell from the focus alone: the desktop also gets
   * it when the frontmost application's last window goes away, and when a
   * click into the Dock activates Workspace. */
  if ([theEvent type] == NSLeftMouseDown || [theEvent type] == NSRightMouseDown)
    [[GWX11WindowManager sharedManager] makeApplicationFrontmostWithPID: getpid()];
  [super sendEvent: theEvent];
}

#ifndef _WIN32
/* Only an X server has a Display to ask; the other backends keep the
 * screen list.  NULL also before the backend is up (first init). */
static Display *GWDesktopXDisplay(void)
{
  GSDisplayServer *server = GSCurrentServer();

  if ([NSStringFromClass([server class]) hasPrefix: @"XG"]
      && [server respondsToSelector: @selector(serverDevice)])
    return (Display *)[server serverDevice];
  return NULL;
}
#endif

+ (NSRect)desktopPixelFrame
{
  /* The frames must come from the X server, not from [NSScreen screens]:
   * after a live RandR resize NSScreen keeps reporting the pre-resize
   * geometry indefinitely (resetScreens does not refresh the backend's
   * cached screen list), which sizes the desktop from stale geometry and
   * exposes the root window.  Streamed desktops (Selkies/VNC) resize the
   * X screen on every client reconnect, so this is the common path, not
   * an edge case.  The root window of the default X screen spans the
   * union of all monitors; NSScreen remains as the fallback when no
   * display server is reachable yet (first init). */
#ifndef _WIN32
  Display *dpy = GWDesktopXDisplay();

  if (dpy)
    {
      /* Asked of the server, not DisplayWidth/DisplayHeight: those are
       * cached in the connection and refreshed by the backend from the
       * FIRST RandR event of a burst (XGServerEvent.m passes the original
       * event, not the last one it drained, to XRRUpdateConfiguration).
       * Unplugging a monitor is such a burst - the output goes off at the
       * old size, then the screen shrinks - so the desktop kept the old,
       * wider size. */
      NSSize root = PrimaryMonitorRootSize(dpy);

      if (root.width > 0 && root.height > 0)
        return NSMakeRect(0, 0, root.width, root.height);
    }
#endif

  {
    NSArray *screens = [NSScreen screens];
    NSRect fullFrame = [[screens objectAtIndex: 0] frame];
    NSUInteger i;

    for (i = 1; i < [screens count]; i++)
      fullFrame = NSUnionRect(fullFrame, [[screens objectAtIndex: i] frame]);
    return fullFrame;
  }
}

+ (NSRect)desktopFullFrame
{
  /* The pixel frame divided by GSScaleFactor (like the menu bar does in
   * Menu.app): the size of the desktop in the points its view is laid out
   * in, so icons keep a constant physical size at any scale factor. */
  NSRect frame = [self desktopPixelFrame];
  CGFloat factor = [GWDesktopWindow desktopScaleFactor];

  frame.size.width /= factor;
  frame.size.height /= factor;
  return frame;
}

+ (void)primaryMonitorXRect:(NSRect *)xRect rootSize:(NSSize *)rootSize
{
#ifndef _WIN32
  /* Asked of the X server, not taken from [NSScreen screens]: that list can
   * lag behind a RandR change (see +desktopFullFrame), and its first entry
   * is the primary only while a RandR primary is set. */
  Display *dpy = GWDesktopXDisplay();

  if (dpy)
    {
      PrimaryMonitorQuery(dpy, xRect, rootSize);
      return;
    }
#endif
  {
    /* A backend without X: its first screen is the primary by definition. */
    NSArray *screens = [NSScreen screens];
    NSRect full = [[screens objectAtIndex: 0] frame];
    NSRect first = full;
    NSUInteger i;

    for (i = 1; i < [screens count]; i++)
      full = NSUnionRect(full, [[screens objectAtIndex: i] frame]);
    first.origin.y = NSMaxY(full) - NSMaxY(first);
    if (xRect != NULL)
      *xRect = first;
    if (rootSize != NULL)
      *rootSize = full.size;
  }
}

+ (NSRect)primaryMonitorFrame
{
  NSRect xRect;
  NSSize rootSize;

  [self primaryMonitorXRect: &xRect rootSize: &rootSize];
  xRect.origin.y = rootSize.height - xRect.origin.y - xRect.size.height;
  return xRect;
}

+ (CGFloat)desktopScaleFactor
{
  id val = [[NSUserDefaults standardUserDefaults] objectForKey: @"GSScaleFactor"];
  CGFloat factor = val ? [val floatValue] : 1.0;

  return (factor > 0.0) ? factor : 1.0;
}

- (void)dealloc
{
  [super dealloc];
}

- (id)init
{
  // Compute the union of all screen frames so the desktop covers every monitor
  NSRect fullFrame = [GWDesktopWindow desktopFullFrame];

  self = [super initWithContentRect: fullFrame
                          styleMask: NSBorderlessWindowMask
			    backing: NSBackingStoreBuffered
                              defer: NO];
  if (self)
    {
      /* At desktop level from the start: libs-gui then never gives the
       * window the factor of one of the monitors it spans, which would
       * resize it and scale its content away from desktopScaleFactor. */
      [self setLevel: NSDesktopWindowLevel];
      /* initWithContentRect: scaled the frame with the factor of the main
       * screen, which with monitors of different scales need not be the
       * desktop's; the root window in pixels is what it must cover. */
      [self setFrame: [GWDesktopWindow desktopPixelFrame] display: NO];
      [self setReleasedWhenClosed: NO];
      [self setExcludedFromWindowsMenu: YES];
      [self setAcceptsMouseMovedEvents: YES];
      [self setCanHide: NO];
      [self setTitle: @"Desktop"];
    }

  return self;
}

/* Every size on the desktop (desktopFullFrame, the icon grid, the
 * wallpaper rects) is divided by desktopScaleFactor, so the window's views
 * must be scaled by exactly that, not by the factor libs-gui would pick from
 * the main screen or from one of the monitors the window spans. */
- (CGFloat)userSpaceScaleFactor
{
  return [GWDesktopWindow desktopScaleFactor];
}

- (void)activate
{
  [self setLevel: NSDesktopWindowLevel];
  [self orderFront: nil];

  // Set EWMH/ICCCM atoms so the window manager recognizes this as
  // a desktop window and keeps it below normal windows.
  // Must happen after orderFront: — the X11 window isn't realised yet
  // during applicationWillFinishLaunching:.
  [self setX11DesktopAtoms];

}

- (void)setX11DesktopAtoms
{
#ifndef _WIN32
  GSDisplayServer *server = GSCurrentServer();
  if (!server) return;
  NSInteger winNum = [self windowNumber];
  if (winNum <= 0) return;
  Display *dpy = (Display *)[server serverDevice];
  if (!dpy) return;

  Window win = (Window)(uintptr_t)[server windowDevice: winNum];
  if (!win) return;

  Atom netWmWindowType = XInternAtom(dpy, "_NET_WM_WINDOW_TYPE", False);
  Atom netWmWindowTypeDesktop = XInternAtom(dpy, "_NET_WM_WINDOW_TYPE_DESKTOP", False);
  XChangeProperty(dpy, win, netWmWindowType, XA_ATOM, 32,
                  PropModeReplace, (unsigned char *)&netWmWindowTypeDesktop, 1);

  Atom netWmState = XInternAtom(dpy, "_NET_WM_STATE", False);
  Atom netWmStateBelow = XInternAtom(dpy, "_NET_WM_STATE_BELOW", False);
  Atom netWmStateSticky = XInternAtom(dpy, "_NET_WM_STATE_STICKY", False);
  Atom states[2] = { netWmStateBelow, netWmStateSticky };
  XChangeProperty(dpy, win, netWmState, XA_ATOM, 32,
                  PropModeReplace, (unsigned char *)states, 2);

  Atom netWmDesktop = XInternAtom(dpy, "_NET_WM_DESKTOP", False);
  unsigned long allDesktops = 0xFFFFFFFFUL;
  XChangeProperty(dpy, win, netWmDesktop, XA_CARDINAL, 32,
                  PropModeReplace, (unsigned char *)&allDesktops, 1);

  /* Without it the window manager cannot tell that a click on the desktop
   * (reported with _ACTIVATE_APPLICATION) comes from the application whose
   * window already has the focus, and takes the active window away. */
  unsigned long pid = (unsigned long)getpid();
  XChangeProperty(dpy, win, XInternAtom(dpy, "_NET_WM_PID", False),
                  XA_CARDINAL, 32, PropModeReplace, (unsigned char *)&pid, 1);

  XFlush(dpy);
#endif
}

- (void)deactivate
{
  [self orderOut: self];
}

- (id)desktopView
{
  return [self contentView];
}

- (void)openSelection:(id)sender
{
  [delegate openSelectionInNewViewer: NO];
}

- (void)openSelectionAsFolder:(id)sender
{
  [delegate openSelectionAsFolder];
}

- (void)openWith:(id)sender
{
  [delegate openSelectionWith];
}

- (void)newFolder:(id)sender
{
  [delegate newFolder];
}

- (void)newFile:(id)sender
{
  [delegate newFile];
}

- (void)duplicateFiles:(id)sender
{
  [delegate duplicateFiles];
}

- (void)makeAliasFiles:(id)sender
{
  [delegate makeAliasFiles];
}

- (void)recycleFiles:(id)sender
{
  [delegate recycleFiles];
}

- (void)deleteFiles:(id)sender
{
  [delegate deleteFiles];
}

- (void)setShownType:(id)sender
{
  [delegate setShownType: sender];
}

- (void)setExtendedShownType:(id)sender
{
  [delegate setExtendedShownType: sender];
}

- (void)setIconsSize:(id)sender
{
  [delegate setIconsSize: sender];
}

- (void)setIconsPosition:(id)sender
{
  [delegate setIconsPosition: sender];
}

- (void)setLabelSize:(id)sender
{
  [delegate setLabelSize: sender];
}

- (void)chooseLabelColor:(id)sender
{
  [delegate chooseLabelColor: sender];
}

- (void)chooseBackColor:(id)sender
{
  [delegate chooseBackColor: sender];
}

- (void)selectAllInViewer:(id)sender
{
  [delegate selectAllInViewer];
}

- (void)showTerminal:(id)sender
{
  [delegate showTerminal];
}

- (void)keyDown:(NSEvent *)theEvent
{	
  [super keyDown: theEvent];
}

- (void)setDelegate:(id)adelegate
{
  delegate = adelegate;
  [super setDelegate: adelegate];
}

- (BOOL)validateMenuItem:(id <NSMenuItem>)menuItem
{	
  return [delegate validateItem: menuItem];
}

- (void)print:(id)sender
{
  [super print: sender];
}

- (void)performClose:(id)sender
{
  NSLog(@"GWDesktopWindow performClose: called - IGNORED (desktop cannot be closed)");
}

- (void)orderWindow:(NSWindowOrderingMode)place 
         relativeTo:(NSInteger)otherWin
{
  [super orderWindow: place relativeTo: otherWin];
  [self setLevel: NSDesktopWindowLevel];
  [self setX11DesktopAtoms];
}

- (BOOL)canBecomeKeyWindow
{
  return YES;
}

- (BOOL)canBecomeMainWindow
{
  return YES;
}

@end
