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
#import <X11/Xlib.h>
#import <X11/Xatom.h>

#import "GWDesktopWindow.h"

@implementation GWDesktopWindow

- (void)dealloc
{
  [super dealloc];
}

- (id)init
{	
  // Compute the union of all screen frames so the desktop covers every monitor
  NSArray *screens = [NSScreen screens];
  NSRect fullFrame = [[screens objectAtIndex:0] frame];
  for (NSUInteger i = 1; i < [screens count]; i++) {
    fullFrame = NSUnionRect(fullFrame, [[screens objectAtIndex:i] frame]);
  }
  self = [super initWithContentRect: fullFrame
                          styleMask: NSBorderlessWindowMask
			    backing: NSBackingStoreBuffered
                              defer: NO];
  if (self)
    {
      [self setReleasedWhenClosed: NO];
      [self setExcludedFromWindowsMenu: YES];
      [self setAcceptsMouseMovedEvents: YES];
      [self setCanHide: NO];
      [self setTitle: @"Desktop"];
    }

  return self;
}

- (void)activate
{
  NSDebugLLog(@"gwspace", @"DEBUG: GWDesktopWindow activate called - setting level and ordering front");
  [self setLevel: NSDesktopWindowLevel];
  [self orderFront: nil];

  // Set EWMH/ICCCM atoms so the window manager recognizes this as
  // a desktop window and keeps it below normal windows.
  // Must happen after orderFront: — the X11 window isn't realised yet
  // during applicationWillFinishLaunching:.
  [self setX11DesktopAtoms];

  NSDebugLLog(@"gwspace", @"DEBUG: GWDesktopWindow is now visible: %d, level: %ld", [self isVisible], (long)[self level]);
}

- (void)setX11DesktopAtoms
{
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

  XFlush(dpy);
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
