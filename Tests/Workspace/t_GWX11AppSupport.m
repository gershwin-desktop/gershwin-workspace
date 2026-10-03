/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

/* t_GWX11AppSupport.m - a window whose _NET_WM_NAME is not valid UTF-8 must
 * not crash the app monitor's window scan.
 * -[GWX11WindowManager getWindowName:window:] used to XFree the property
 * buffer, find that -stringWithUTF8String: rejected the bytes, and then fall
 * through to an unconditional XFree of the same already-freed pointer - a
 * double free that a modern glibc's tcache guard aborts the process for.
 * Needs a private Xvfb: no window manager or the live desktop is touched. */

#import <Foundation/Foundation.h>
#import "Testing.h"
/* X11AppSupport.m message-sends GWProcessOwnership from windowsMatchingName:,
 * which the Objective-C runtime resolves through a class reference that must
 * still link even though this test never calls that method. */
#include "../../Workspace/GWProcessOwnership.m"
#include "../../Workspace/X11AppSupport.m"

#include <X11/Xlib.h>
#include <X11/Xatom.h>
#include <unistd.h>
#include <signal.h>
#include <stdlib.h>

/* :95-:99 are reserved for the isolated uitest slots; the range well below
 * that keeps this test from ever colliding with one. A display whose server
 * answers belongs to someone else and is skipped; a leftover socket or lock
 * of a dead server is no obstacle, Xvfb cleans those up itself. */
static const int firstDisplay = 70;
static const int lastDisplay = 89;
static NSString *displayName = nil;

static Display *waitForXvfb(void)
{
  int tries;

  for (tries = 0; tries < 50; tries++)
    {
      Display *dpy = XOpenDisplay([displayName UTF8String]);
      if (dpy != NULL)
        {
          return dpy;
        }
      usleep(100000); /* 100ms */
    }
  return NULL;
}

/* Starts a private Xvfb on the first display of the range nobody serves;
 * returns the connection and leaves the task in *task, or NULL. */
static Display *startPrivateXvfb(NSTask **task)
{
  int n;

  for (n = firstDisplay; n <= lastDisplay; n++)
    {
      Display *dpy;

      displayName = [NSString stringWithFormat: @":%d", n];
      dpy = XOpenDisplay([displayName UTF8String]);
      if (dpy != NULL)
        {
          XCloseDisplay(dpy);
          continue;
        }
      *task = [NSTask new];
      [*task setLaunchPath: @"/usr/bin/Xvfb"];
      [*task setArguments: [NSArray arrayWithObjects:
          displayName, @"-screen", @"0", @"320x240x24", nil]];
      [*task launch];
      dpy = waitForXvfb();
      if (dpy != NULL)
        {
          return dpy;
        }
      [*task terminate];
      [*task waitUntilExit];
      [*task release];
      *task = nil;
    }
  return NULL;
}

int main(void)
{
  NSAutoreleasePool *arp = [NSAutoreleasePool new];
  NSTask *xvfb;
  Display *dpy;
  Window win;
  Atom net_wm_name, utf8_string;
  /* 0xFF and 0xFE are never valid UTF-8 lead bytes, so this cannot decode -
   * exactly the property content that used to trigger the double free. */
  unsigned char badName[] = { 0xFF, 0xFE, 'X' };
  GWX11WindowManager *wm;
  NSString *name;

  xvfb = nil;
  dpy = startPrivateXvfb(&xvfb);
  if (dpy == NULL)
    {
      NSLog(@"no private Xvfb could be started on :%d-:%d", firstDisplay, lastDisplay);
      [arp release];
      return 1;
    }

  win = XCreateSimpleWindow(dpy, DefaultRootWindow(dpy), 0, 0, 10, 10, 0, 0, 0);
  net_wm_name = XInternAtom(dpy, "_NET_WM_NAME", False);
  utf8_string = XInternAtom(dpy, "UTF8_STRING", False);
  XChangeProperty(dpy, win, net_wm_name, utf8_string, 8, PropModeReplace,
                  badName, sizeof(badName));
  XSync(dpy, False);

  wm = [GWX11WindowManager sharedManager];
  /* If getWindowName:window: still double frees, the process aborts right
   * here and no PASS below ever runs - that is the RED signal. */
  name = [wm getWindowName: dpy window: win];
  PASS(name == nil,
       "a non-UTF8 _NET_WM_NAME yields no name instead of crashing");

  XDestroyWindow(dpy, win);
  XCloseDisplay(dpy);
  [xvfb terminate];
  [xvfb waitUntilExit];

  [arp release];
  return 0;
}
