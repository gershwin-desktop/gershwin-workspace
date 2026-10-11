/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

/* t_FinderGeometry.m
 *
 * The Find window grows and shrinks by one row whenever a criterion row is
 * added or removed (Finder -tile). The row heights are points, the window
 * frame is in screen coordinates; at GSScaleFactor 1.5 the window grew by
 * only two thirds of a row, so the last row and the bottom and right edges
 * of the criteria box were cut off. */
#import <Foundation/Foundation.h>
#import "Testing.h"
#import "GWFinderGeometry.h"

int main(void)
{
  NSAutoreleasePool *arp = [NSAutoreleasePool new];
  /* The Find window as the slot showed it at 1.5: 726x426 at y 175. */
  NSRect frame = NSMakeRect(0, 175, 726, 426);
  NSRect r;

  r = GWFinderFrameForModulesHeight(frame, 34, 84, 1.0);
  PASS(r.size.height == 476 && NSMaxY(r) == NSMaxY(frame),
    "at scale 1 a 50 pt taller criteria box makes the window 50 px taller, title bar in place");

  r = GWFinderFrameForModulesHeight(frame, 34, 84, 1.5);
  PASS(r.size.height == 501,
    "at scale 1.5 a 50 pt taller criteria box makes the window 75 px taller");
  PASS(NSMaxY(r) == NSMaxY(frame),
    "at scale 1.5 the title bar stays where it was");
  r = GWFinderFrameForModulesHeight(frame, 34, 67, 1.5);
  PASS(r.size.height == 476 && NSMaxY(r) == NSMaxY(frame),
    "a growth of 49.5 px is rounded up to 50 whole pixels so no row is cut");

  r = GWFinderFrameForModulesHeight(frame, 118, 84, 1.5);
  PASS(r.size.height == 375 && NSMaxY(r) == NSMaxY(frame),
    "removing a row at scale 1.5 shrinks the window by 51 px, title bar in place");

  r = GWFinderFrameForModulesHeight(frame, 84, 84, 1.5);
  PASS(NSEqualRects(r, frame),
    "a criteria box that already fits leaves the frame alone");

  [arp release];
  return 0;
}
