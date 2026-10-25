/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-2.0-or-later
 *
 * Coverage for the primary-monitor rule shared by Menu and the Workspace
 * desktop (PrimaryMonitor.h), the X <-> GNUstep flip and the EWMH strut
 * of a panel on a monitor that need not touch the root edge.  Headless.
 * The same cases run in gershwin-components against its copy of the file.
 */
#import <Foundation/Foundation.h>
#import "Testing.h"
#import "../../Workspace/Desktop/PrimaryMonitor.h"

static NSString * const kSuiteName = @"PrimaryMonitor rule and struts";

int main(void)
{
  NSAutoreleasePool *arp = [NSAutoreleasePool new];
  NSLog(@"%@", kSuiteName);

  /* Laptop 1280x800 at 0,0 and an external 1920x1080 to its right. */
  NSRect leftRight[2] = { NSMakeRect(0, 0, 1280, 800),
                          NSMakeRect(1280, 0, 1920, 1080) };
  /* The external one left of the laptop, laptop listed first. */
  NSRect extLeft[2] = { NSMakeRect(1920, 0, 1280, 800),
                        NSMakeRect(0, 0, 1920, 1080) };

  PASS(PrimaryMonitorChooseIndex(leftRight, 2, 1) == 1,
       "a set RandR primary wins, even when it is not at the root origin");
  PASS(PrimaryMonitorChooseIndex(extLeft, 2, 0) == 0,
       "a set RandR primary wins over the monitor at the root origin");
  PASS(PrimaryMonitorChooseIndex(extLeft, 2, -1) == 1,
       "without a primary, the monitor containing 0,0 is chosen, not the first listed");
  PASS(PrimaryMonitorChooseIndex(leftRight, 2, 5) == 0,
       "a primary index out of range counts as no primary");

  {
    /* Nothing at 0,0 (e.g. both monitors moved down): first one. */
    NSRect gap[2] = { NSMakeRect(100, 50, 800, 600),
                      NSMakeRect(900, 50, 800, 600) };
    PASS(PrimaryMonitorChooseIndex(gap, 2, -1) == 0,
         "without a primary and nothing at 0,0, the first lit monitor is chosen");
  }
  PASS(PrimaryMonitorChooseIndex(NULL, 0, -1) == -1,
       "no monitor at all gives -1");

  {
    /* Root 3200x1080: the laptop (800 tall) is top-aligned, so in GNUstep
     * coordinates it starts 280 px above the bottom. */
    NSRect gs = PrimaryMonitorFlipRect(leftRight[0], 1080);
    PASS(NSEqualRects(gs, NSMakeRect(0, 280, 1280, 800)),
         "X rect of a shorter top-aligned monitor flips to y = rootH - h");
    PASS(NSEqualRects(PrimaryMonitorFlipRect(gs, 1080), leftRight[0]),
         "the flip is its own inverse");
  }

  {
    unsigned long s[12];
    NSSize root = NSMakeSize(3200, 1080);

    /* Menu bar 22 px on the laptop at the left. */
    PrimaryMonitorStrutForPanel(NSMakeRect(0, 0, 1280, 22), root,
                                PrimaryMonitorEdgeTop, s);
    PASS(s[2] == 22 && s[8] == 0 && s[9] == 1279
         && s[0] == 0 && s[1] == 0 && s[3] == 0,
         "top strut covers only the primary's columns 0..1279");

    /* Primary is the external one on the right, 44 px bar at scale 2. */
    PrimaryMonitorStrutForPanel(NSMakeRect(1280, 0, 1920, 44), root,
                                PrimaryMonitorEdgeTop, s);
    PASS(s[2] == 44 && s[8] == 1280 && s[9] == 3199,
         "top strut of a bar on the right monitor starts at its x");

    /* Bottom Dock on the 800-tall laptop: the root bottom is 280 px lower. */
    PrimaryMonitorStrutForPanel(NSMakeRect(400, 736, 480, 64), root,
                                PrimaryMonitorEdgeBottom, s);
    PASS(s[3] == 344 && s[10] == 400 && s[11] == 879,
         "bottom strut of a Dock on a shorter monitor counts from the root bottom");

    /* Left Dock on a monitor that starts at x 1280. */
    PrimaryMonitorStrutForPanel(NSMakeRect(1280, 300, 64, 400), root,
                                PrimaryMonitorEdgeLeft, s);
    PASS(s[0] == 1344 && s[4] == 300 && s[5] == 699,
         "left strut of a Dock on the right monitor counts from the root left");

    /* Right Dock on the laptop at the left. */
    PrimaryMonitorStrutForPanel(NSMakeRect(1216, 200, 64, 400), root,
                                PrimaryMonitorEdgeRight, s);
    PASS(s[1] == 1984 && s[6] == 200 && s[7] == 599,
         "right strut of a Dock on the left monitor counts from the root right");

    /* Fractional bar height (22 pt at 1.25) never reserves less. */
    PrimaryMonitorStrutForPanel(NSMakeRect(0, 0, 1280, 27.5), root,
                                PrimaryMonitorEdgeTop, s);
    PASS(s[2] == 28, "a fractional panel extent rounds outward");
  }

  [arp release];
  return 0;
}
