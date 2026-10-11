/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

/* t_GWOpenItemAnimation.m - opening a document or an application lets its
 * icon grow out of its place and fade away.  The class methods decide where
 * the icon is drawn and how opaque it is at each moment; they are checked
 * here headless (no window is created). */

#import <AppKit/AppKit.h>
#import "Testing.h"
#include "../../Workspace/GWOpenItemAnimation.m"

int main(void)
{
  NSAutoreleasePool *arp = [NSAutoreleasePool new];
  NSRect icon = NSMakeRect (100, 200, 64, 64);
  NSRect start = [GWOpenItemAnimation rectForIconRect: icon progress: 0.0];
  NSRect half = [GWOpenItemAnimation rectForIconRect: icon progress: 0.5];
  NSRect end = [GWOpenItemAnimation rectForIconRect: icon progress: 1.0];

  PASS (NSEqualRects (start, icon), "the animation starts with the icon where it is");
  PASS (NSWidth (end) > NSWidth (icon) * 2.0 && fabs (NSWidth (end) - NSHeight (end)) < 0.001,
        "it ends more than twice as large and keeps its proportions");
  PASS (fabs (NSMidX (end) - NSMidX (icon)) < 0.001 && fabs (NSMidY (end) - NSMidY (icon)) < 0.001,
        "it grows about the icon's centre");
  PASS (NSWidth (half) - NSWidth (start) > NSWidth (end) - NSWidth (half),
        "it grows fastest at first (ease out)");

  PASS ([GWOpenItemAnimation opacityAtProgress: 0.0] == 1.0, "it starts fully opaque");
  PASS ([GWOpenItemAnimation opacityAtProgress: 1.0] == 0.0, "it is gone at the end");
  PASS ([GWOpenItemAnimation opacityAtProgress: 0.25] > [GWOpenItemAnimation opacityAtProgress: 0.5]
        && [GWOpenItemAnimation opacityAtProgress: 0.5] > [GWOpenItemAnimation opacityAtProgress: 0.75],
        "it fades steadily");

  PASS (NSEqualRects ([GWOpenItemAnimation iconPartOfRect: icon], icon),
        "an icon-view rect is used as it is");
  PASS (NSEqualRects ([GWOpenItemAnimation iconPartOfRect: NSMakeRect (10, 20, 300, 18)],
                      NSMakeRect (10, 20, 18, 18)),
        "a list row or browser cell yields the square at its left end, where the icon is");

  [arp release];
  return 0;
}
