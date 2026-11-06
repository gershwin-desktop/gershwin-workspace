/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

/* t_GWWindowAnimationGeometry.m - the window manager plays the folder
 * window's birth and close animations from the folder icon's rect, which
 * Workspace writes in X root coordinates (origin top left, y down).
 * GNUstep screen coordinates have their origin at the bottom left of the
 * whole X screen, not of one monitor, and are device pixels at every
 * GSScaleFactor and on every monitor.  The layouts are the user's: eDP-1
 * 1920x1080 primary at 0,0 and HDMI-1 1920x1080 beside it, then HDMI-1
 * moved down by 400, which makes the X screen taller than either monitor. */

#import <Foundation/Foundation.h>
#import "Testing.h"
#import "GWWindowAnimationGeometry.h"

static BOOL same(NSRect a, NSRect b)
{
  if (NSEqualRects (a, b) == NO)
    {
      NSLog (@"got %@, expected %@", NSStringFromRect (a), NSStringFromRect (b));
      return NO;
    }
  return YES;
}

int main(void)
{
  NSAutoreleasePool *arp = [NSAutoreleasePool new];

  /* side by side, X screen 3840x1080: both monitors' GNUstep frames start at y 0 */
  PASS (same (GWX11RootRectForScreenRect (NSMakeRect (100, 936, 64, 64), 1080),
              NSMakeRect (100, 80, 64, 64)),
        "eDP-1: an icon 80 px below the top is 80 px below the top in X");
  PASS (same (GWX11RootRectForScreenRect (NSMakeRect (100, 20, 64, 64), 1080),
              NSMakeRect (100, 996, 64, 64)),
        "eDP-1: an icon at the bottom is at the bottom in X");
  PASS (same (GWX11RootRectForScreenRect (NSMakeRect (2020, 936, 64, 64), 1080),
              NSMakeRect (2020, 80, 64, 64)),
        "HDMI-1 beside it: x is already global and is not offset by the monitor again");

  /* HDMI-1 at +1920+400, X screen 3840x1480: eDP-1's GNUstep frame is
     (0, 400, 1920, 1080), HDMI-1's (1920, 0, 1920, 1080) */
  PASS (same (GWX11RootRectForScreenRect (NSMakeRect (100, 1400, 64, 64), 1480),
              NSMakeRect (100, 16, 64, 64)),
        "eDP-1 above the bottom of the X screen: an icon at its top stays at the top");
  PASS (same (GWX11RootRectForScreenRect (NSMakeRect (100, 410, 64, 64), 1480),
              NSMakeRect (100, 1006, 64, 64)),
        "eDP-1 above the bottom of the X screen: an icon at its bottom stays at its bottom");
  PASS (same (GWX11RootRectForScreenRect (NSMakeRect (2000, 1406, 64, 64), 1480),
              NSMakeRect (2000, 10, 64, 64)),
        "HDMI-1 moved down: an icon at its top is 400 px below the top of the X screen");
  PASS (same (GWX11RootRectForScreenRect (NSMakeRect (2000, 10, 64, 64), 1480),
              NSMakeRect (2000, 1406, 64, 64)),
        "HDMI-1 moved down: an icon at its bottom is at the bottom of the X screen");

  /* GSScaleFactor 1.25 (DPI 120): icon rects land between pixels; both
     edges are rounded, so the rect covers the pixels the icon covers */
  PASS (same (GWX11RootRectForScreenRect (NSMakeRect (100.4, 900.6, 80.2, 80.2), 1080),
              NSMakeRect (100, 99, 81, 80)),
        "a fractional rect is rounded at both edges, not truncated");

  [arp release];
  return 0;
}
