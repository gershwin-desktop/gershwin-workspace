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

/* Stands in for the browsing viewer's content view, an NSSplitView, which
   libs-gui makes flipped (y grows downwards). */
@interface TFlippedHost : NSView
@end
@implementation TFlippedHost
- (BOOL)isFlipped
{
  return YES;
}
@end

/* Where the overlay draws an icon that `host` shows at `rectInHost`, given
   back in the host's own coordinates: it must be the very same rect. */
static NSRect drawnRectInHost(NSView *host, NSRect rectInHost)
{
  GWOpenItemAnimation *overlay;
  NSRect inOverlay;
  NSRect back;

  overlay = [[GWOpenItemAnimation alloc] initWithFrame: [host bounds]
                                                  icon: nil
                                              iconRect: NSZeroRect];
  [host addSubview: overlay];
  inOverlay = [GWOpenItemAnimation iconRectInOverlay: overlay
                                             forRect: rectInHost
                                              ofView: host];
  back = [host convertRect: inOverlay fromView: overlay];
  [overlay removeFromSuperview];
  [overlay release];
  return back;
}

int main(void)
{
  NSAutoreleasePool *arp = [NSAutoreleasePool new];
  NSRect icon = NSMakeRect (100, 200, 64, 64);
  NSRect start = [GWOpenItemAnimation rectForIconRect: icon progress: 0.0];
  NSRect half = [GWOpenItemAnimation rectForIconRect: icon progress: 0.5];
  NSRect end = [GWOpenItemAnimation rectForIconRect: icon progress: 1.0];

  PASS (NSEqualRects (start, icon), "the animation starts with the icon where it is");
  PASS (fabs (NSWidth (end) - NSWidth (icon) * 4.4) < 0.001 && fabs (NSWidth (end) - NSHeight (end)) < 0.001,
        "it ends 4.4 times as large and keeps its proportions");
  PASS (fabs (NSMidX (end) - NSMidX (icon)) < 0.001 && fabs (NSMidY (end) - NSMidY (icon)) < 0.001,
        "it grows about the icon's centre");
  PASS (NSWidth (half) - NSWidth (start) > NSWidth (end) - NSWidth (half),
        "it grows fastest at first (ease out)");

  {
    NSRect area = NSMakeRect (0, 0, 1920, 1080);

    PASS (NSEqualRects ([GWOpenItemAnimation rect: NSMakeRect (500, 500, 200, 200) keptInside: area],
                        NSMakeRect (500, 500, 200, 200)),
          "away from the monitor's edges it stays centered on the icon");
    PASS (NSEqualRects ([GWOpenItemAnimation rect: NSMakeRect (1800, 950, 200, 200) keptInside: area],
                        NSMakeRect (1720, 880, 200, 200)),
          "at the right and top edge it is shifted back onto the monitor, at full size");
    PASS (NSEqualRects ([GWOpenItemAnimation rect: NSMakeRect (-60, -30, 200, 200) keptInside: area],
                        NSMakeRect (0, 0, 200, 200)),
          "at the left and bottom edge as well");
    PASS (NSEqualRects ([GWOpenItemAnimation rect: NSMakeRect (0, 0, 300, 120)
                                       keptInside: NSMakeRect (0, 0, 200, 100)],
                        NSMakeRect (-50, -10, 300, 120)),
          "larger than the monitor it is centered on it (and clipped there)");
  }
  PASS ([GWOpenItemAnimation progressAtTime: 1000.0 startedAt: 0] == 0.0,
        "before its first tick it shows its first frame, however long the open held the run loop");
  PASS ([GWOpenItemAnimation progressAtTime: 1000.0 startedAt: 1000.0] == 0.0
        && [GWOpenItemAnimation progressAtTime: 1010.0 startedAt: 1000.0] == 1.0,
        "from its first tick it runs its course and ends");
  {
    BOOL falling = YES;
    int f;

    for (f = 1; f <= 60; f++)
      {
        if ([GWOpenItemAnimation opacityAtProgress: f / 60.0]
            > [GWOpenItemAnimation opacityAtProgress: (f - 1) / 60.0])
          {
            falling = NO;
          }
      }
    PASS (falling, "its opacity never rises from one frame to the next");
    PASS ([GWOpenItemAnimation opacityAtProgress: 1.0] == 0.0
          && [GWOpenItemAnimation opacityAtProgress: 1.5] == 0.0,
          "its last frame is fully transparent");
    PASS ([GWOpenItemAnimation opacityAtProgress: 0.94] < 0.02,
          "one 60 Hz tick before the end it is all but gone: nothing pops off");
  }
  PASS ([GWOpenItemAnimation opacityAtProgress: 0.0] == 1.0, "it starts fully opaque");
  PASS ([GWOpenItemAnimation opacityAtProgress: 1.0] == 0.0, "it is gone at the end");
  PASS ([GWOpenItemAnimation opacityAtProgress: 0.25] > [GWOpenItemAnimation opacityAtProgress: 0.5]
        && [GWOpenItemAnimation opacityAtProgress: 0.5] > [GWOpenItemAnimation opacityAtProgress: 0.75],
        "it fades steadily");

  /* every frame keeps the picture's aspect, also from fractional rects as
     they come out at GSScaleFactor 1.25 or 1.5, and for a wide thumbnail */
  {
    NSRect starts[3];
    BOOL kept = YES;
    int i;
    int f;

    starts[0] = NSMakeRect (100.4, 200.6, 80.2, 80.2);
    starts[1] = NSMakeRect (12.5, 7.25, 96, 54);       /* 16:9 thumbnail */
    starts[2] = NSMakeRect (3, 4, 20, 30);             /* tall thumbnail */
    for (i = 0; i < 3; i++)
      {
        CGFloat aspect = NSWidth (starts[i]) / NSHeight (starts[i]);

        for (f = 0; f <= 30; f++)
          {
            NSRect r = [GWOpenItemAnimation rectForIconRect: starts[i]
                                                   progress: f / 30.0];

            if (fabs (NSWidth (r) / NSHeight (r) - aspect) > 1e-9
                || fabs (NSMidX (r) - NSMidX (starts[i])) > 1e-9
                || fabs (NSMidY (r) - NSMidY (starts[i])) > 1e-9)
              {
                kept = NO;
              }
          }
      }
    PASS (kept, "every frame keeps the aspect and the center of the picture it starts from");
  }

  PASS (NSEqualRects ([GWOpenItemAnimation rect: icon fittedToAspectOfSize: NSMakeSize (64, 64)], icon),
        "a square icon in its square rect is used as it is");
  PASS (NSEqualRects ([GWOpenItemAnimation rect: NSMakeRect (0, 0, 100, 90)
                                fittedToAspectOfSize: NSMakeSize (64, 64)],
                      NSMakeRect (5, 0, 90, 90)),
        "a square icon in an icon's whole rect (wider for its name) is not stretched");
  PASS (NSEqualRects ([GWOpenItemAnimation rect: NSMakeRect (0, 0, 64, 64)
                                fittedToAspectOfSize: NSMakeSize (64, 36)],
                      NSMakeRect (0, 14, 64, 36)),
        "a 16:9 thumbnail keeps its aspect in a square rect");

  {
    NSView *flipped = [[TFlippedHost alloc] initWithFrame: NSMakeRect (0, 0, 400, 300)];
    NSView *plain = [[NSView alloc] initWithFrame: NSMakeRect (0, 0, 400, 300)];
    NSRect nearTop = NSMakeRect (10, 20, 64, 64);      /* flipped: 20 from the top */
    NSRect nearBottom = NSMakeRect (10, 210, 64, 64);  /* flipped: 26 from the bottom */
    NSRect plainRect = NSMakeRect (10, 20, 64, 64);

    PASS (NSEqualRects (drawnRectInHost (flipped, nearTop), nearTop),
          "in a flipped window (a browsing viewer) an icon at the top grows at the top, not at the bottom");
    PASS (NSEqualRects (drawnRectInHost (flipped, nearBottom), nearBottom),
          "in a flipped window an icon at the bottom grows at the bottom, not at the top");
    PASS (NSEqualRects (drawnRectInHost (plain, plainRect), plainRect),
          "in an unflipped window (the desktop, a spatial viewer) the icon grows where it is");
    [flipped release];
    [plain release];
  }

  [arp release];
  return 0;
}
