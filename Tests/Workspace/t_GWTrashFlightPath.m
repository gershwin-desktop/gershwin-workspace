/* t_GWTrashFlightPath.m - ObjectTesting coverage for the pure "fly to Trash"
 * path function.  Foundation-only, headless: no AppKit, no window server.
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */
#import <Foundation/Foundation.h>
#import "Testing.h"
#include <math.h>
#include "../../Workspace/GWTrashFlightPath.m"

int main(void)
{
  NSAutoreleasePool *arp = [NSAutoreleasePool new];

  /* --- t=0 and t=1 are the two rects exactly, size included --- */
  {
    NSRect start = NSMakeRect(10.0, 20.0, 64.0, 64.0);
    NSRect end = NSMakeRect(500.0, 30.0, 24.0, 24.0);
    NSRect atStart = GWTrashFlightRectAtTime(start, end, 0.0);
    NSRect atEnd = GWTrashFlightRectAtTime(start, end, 1.0);

    PASS(NSEqualRects(atStart, start), "t=0 gives the start rect exactly");
    PASS(NSEqualRects(atEnd, end), "t=1 gives the end rect, size included");
  }

  /* --- the midpoint deviates from the straight line by the designed
   * fraction, for a mostly horizontal path --- */
  {
    NSRect start = NSMakeRect(0.0, 100.0, 64.0, 64.0);
    NSRect end = NSMakeRect(800.0, 100.0, 32.0, 32.0);
    NSRect mid = GWTrashFlightRectAtTime(start, end, 0.5);
    NSPoint p0 = NSMakePoint(NSMidX(start), NSMidY(start));
    NSPoint p3 = NSMakePoint(NSMidX(end), NSMidY(end));
    NSPoint straightMid = NSMakePoint((p0.x + p3.x) / 2.0, (p0.y + p3.y) / 2.0);
    NSPoint midCenter = NSMakePoint(NSMidX(mid), NSMidY(mid));
    CGFloat dist = sqrt(pow(p3.x - p0.x, 2) + pow(p3.y - p0.y, 2));
    /* Derived in GWTrashFlightPath.m's header comment: a cubic built with
     * both control points offset by `bow` from the chord deviates from the
     * chord's own midpoint by exactly 0.75*bow at u=0.5, and t=0.5 is where
     * the symmetric ease-in-out also sits at u=0.5. */
    CGFloat expectedDeviation = 0.75 * GWTrashFlightBowFraction * dist;
    CGFloat actualDeviation = sqrt(pow(midCenter.x - straightMid.x, 2)
                                   + pow(midCenter.y - straightMid.y, 2));

    PASS(fabs(actualDeviation - expectedDeviation) < 0.01,
         "midpoint deviates from the straight line by the designed fraction");
    /* A mostly horizontal path bows UP (screen +y), not down or sideways -
     * "rises and then swoops down" is only true if the bulge is above the
     * chord partway through the flight. */
    PASS(midCenter.y > straightMid.y + 1.0,
         "a horizontal path bows upward, not sideways or downward");
  }

  /* --- a near-vertical path bows sideways instead of degenerating --- */
  {
    NSRect start = NSMakeRect(100.0, 0.0, 48.0, 48.0);
    NSRect end = NSMakeRect(100.0, 800.0, 48.0, 48.0);
    NSRect mid = GWTrashFlightRectAtTime(start, end, 0.5);
    NSPoint midCenter = NSMakePoint(NSMidX(mid), NSMidY(mid));

    PASS(fabs(midCenter.x - 100.0) > 1.0,
         "a vertical path bows sideways rather than staying on the line");
  }

  /* --- monotonic progress: easing never runs backward, and neither does
   * the interpolated position on a straightforward path --- */
  {
    NSRect start = NSMakeRect(0.0, 0.0, 64.0, 64.0);
    NSRect end = NSMakeRect(600.0, -200.0, 24.0, 24.0);
    CGFloat lastEase = -1.0;
    CGFloat lastRemaining = 1.0e9;
    BOOL easeMonotonic = YES;
    BOOL progressMonotonic = YES;
    int i;

    for (i = 0; i <= 20; i++)
      {
        CGFloat t = i / 20.0;
        CGFloat ease = GWTrashFlightEaseInOut(t);
        NSRect r = GWTrashFlightRectAtTime(start, end, t);
        NSPoint c = NSMakePoint(NSMidX(r), NSMidY(r));
        CGFloat remaining = sqrt(pow(c.x - NSMidX(end), 2)
                                 + pow(c.y - NSMidY(end), 2));

        if (ease < lastEase - 1.0e-9)
          easeMonotonic = NO;
        /* Allow a hair of slack: near the very ends the eased speed is
           near zero, where floating point noise could otherwise trip a
           strict decrease check. */
        if (remaining > lastRemaining + 0.5)
          progressMonotonic = NO;

        lastEase = ease;
        lastRemaining = remaining;
      }

    PASS(easeMonotonic, "the easing curve never runs backward over t in [0,1]");
    PASS(progressMonotonic,
         "the flight gets no farther from the destination as t increases");
  }

  /* --- easing is symmetric: ease(1-t) == 1-ease(t) --- */
  {
    CGFloat samples[] = { 0.1, 0.25, 0.4, 0.6, 0.75, 0.9 };
    BOOL symmetric = YES;
    unsigned int i;

    for (i = 0; i < sizeof(samples) / sizeof(samples[0]); i++)
      {
        CGFloat t = samples[i];
        CGFloat a = GWTrashFlightEaseInOut(t);
        CGFloat b = GWTrashFlightEaseInOut(1.0 - t);

        if (fabs((a + b) - 1.0) > 1.0e-9)
          symmetric = NO;
      }

    PASS(symmetric, "ease(1-t) == 1-ease(t) for every sampled t");
    PASS(fabs(GWTrashFlightEaseInOut(0.5) - 0.5) < 1.0e-9,
         "the halfway point of the ease is exactly halfway");
  }

  [arp release];
  return 0;
}
