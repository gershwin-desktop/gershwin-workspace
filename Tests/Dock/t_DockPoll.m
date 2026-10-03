/* t_DockPoll.m - headless coverage for the Dock's magnification poll rate.
 *
 * DockMagnifyPollInterval() lives in Dock.h as a Foundation-only static
 * inline function precisely so the timing rule can be proven without
 * building a Dock (which needs NSWorkspace, X11 and a running desktop).
 * Dock.h drags in GWDesktopManager.h and FSNodeRep.h for their declarations
 * only; nothing here links FSNode or messages any AppKit class.
 *
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import "Testing.h"
#import "Dock.h"

#define CLOSE(a, b) (fabs((a) - (b)) < 0.001)

int
main(void)
{
  NSAutoreleasePool *arp = [NSAutoreleasePool new];

  /* --- the near zone is untouched --- */
  {
    PASS(CLOSE(DockMagnifyPollInterval(500.0, 64.0, YES), MAGNIFY_FRAME_INTERVAL),
         "mid-magnification (armed) always looks every frame, however far "
         "the pointer reads");

    PASS(CLOSE(DockMagnifyPollInterval(10.0, 64.0, NO), MAGNIFY_FRAME_INTERVAL),
         "a pointer already inside the trigger radius is looked at every "
         "frame, same as before the fix");

    PASS(CLOSE(DockMagnifyPollInterval(64.0 + 5.0, 64.0, NO), MAGNIFY_FRAME_INTERVAL),
         "just past the trigger radius still floors at the frame interval "
         "(the ramp has not had room to climb yet)");
  }

  /* --- the far side must actually go idle --- */
  {
    NSTimeInterval midRamp = DockMagnifyPollInterval(64.0 + 100.0, 64.0, NO);

    PASS((midRamp > MAGNIFY_FRAME_INTERVAL) && (midRamp < MAGNIFY_IDLE_INTERVAL),
         "partway out, the wait still ramps between the frame and idle "
         "intervals rather than snapping straight to one of them");

    /* This is the distance the live desktop was actually parked at
     * (evidence/idle-cpu-hunt/combined-trace-10s.txt: 126 writev in 10.6 s,
     * an 84 ms average gap, which is (distance-near)/4000 solved for ~336 px
     * of "far"). Under the unfixed 4000 px/s bound this returns 0.336/4 =
     * 0.084 s - well under the idle cap, which is the bug. Reverting just
     * MAGNIFY_POINTER_SPEED to 4000.0 turns this PASS into a FAIL (0.084 not
     * >= 0.25), which is how this assertion was confirmed to discriminate. */
    PASS(DockMagnifyPollInterval(64.0 + 336.0, 64.0, NO) >= MAGNIFY_IDLE_INTERVAL,
         "a pointer parked a few hundred points from the bar polls no "
         "faster than the idle interval");

    PASS(CLOSE(DockMagnifyPollInterval(64.0 + 10000.0, 64.0, NO), MAGNIFY_IDLE_INTERVAL),
         "a pointer parked at the far side of any screen is capped at the "
         "idle interval, same as before the fix");
  }

  [arp release];
  return 0;
}
