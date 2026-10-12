/* t_DockLabelPlacement.m - headless coverage for where the Dock puts the
 * label of the icon under the pointer: above it at the bottom of the
 * screen, beside it towards the middle at a side, always on the screen,
 * with the arrow pointing at the icon.
 *
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

#import <Foundation/Foundation.h>
#import "Testing.h"
#import "DockStyleGeometry.h"

#define CLOSE(a, b) (fabs((a) - (b)) < 0.001)

static const CGFloat gap = 6, arrow = 7, radius = 6, margin = 4;

int
main(void)
{
  NSAutoreleasePool *arp = [NSAutoreleasePool new];
  NSRect screen = NSMakeRect(0, 0, 1280, 800);
  NSSize text = NSMakeSize(120, 26);

  /* --- bottom --- */
  {
    NSRect icon = NSMakeRect(600, 0, 64, 64);
    DockLabelLayout l = DockLabelPlace(icon, text, DockEdgeBottom, screen,
                                       gap, arrow, radius, margin);

    PASS(CLOSE(NSMinY(l.frame), 64 + gap),
         "at the bottom the label is above the icon, a gap away");
    PASS(CLOSE(NSMidX(l.frame), NSMidX(icon)),
         "and centred over it");
    PASS(CLOSE(NSHeight(l.frame), 26 + arrow) && CLOSE(NSMinY(l.body), arrow),
         "the arrow hangs below the box");
    PASS(CLOSE(NSMinX(l.frame) + l.tip.x, NSMidX(icon)) && CLOSE(l.tip.y, 0),
         "the arrow points at the middle of the icon");
  }

  {
    /* The first icon of a Dock that reaches the left screen edge. */
    NSRect icon = NSMakeRect(0, 0, 64, 64);
    DockLabelLayout l = DockLabelPlace(icon, text, DockEdgeBottom, screen,
                                       gap, arrow, radius, margin);

    PASS(CLOSE(NSMinX(l.frame), margin),
         "a label that would hang off the left edge is kept on the screen");
    PASS(CLOSE(NSMinX(l.frame) + l.tip.x, NSMidX(icon)),
         "and its arrow still points at the icon");
  }

  {
    NSRect icon = NSMakeRect(1280 - 20, 0, 20, 64);
    DockLabelLayout l = DockLabelPlace(icon, text, DockEdgeBottom, screen,
                                       gap, arrow, radius, margin);

    PASS(CLOSE(NSMaxX(l.frame), 1280 - margin),
         "a label that would hang off the right edge is kept on the screen");
    PASS(l.tip.x <= NSWidth(l.frame) - radius - arrow + 0.001,
         "the arrow stops short of the rounded corner when the icon is past it");
  }

  {
    /* A magnified icon is taller; the label stays clear of it. */
    NSRect icon = NSMakeRect(600, 0, 128, 128);
    DockLabelLayout l = DockLabelPlace(icon, text, DockEdgeBottom, screen,
                                       gap, arrow, radius, margin);

    PASS(CLOSE(NSMinY(l.frame), 128 + gap),
         "over a magnified icon the label sits above its grown top");
  }

  /* --- left --- */
  {
    NSRect icon = NSMakeRect(0, 400, 64, 64);
    DockLabelLayout l = DockLabelPlace(icon, text, DockEdgeLeft, screen,
                                       gap, arrow, radius, margin);

    PASS(CLOSE(NSMinX(l.frame), 64 + gap),
         "at the left the label is to the right of the icon, towards the middle");
    PASS(CLOSE(NSMidY(l.frame), NSMidY(icon)), "and level with it");
    PASS(CLOSE(l.tip.x, 0) && CLOSE(NSMinX(l.body), arrow),
         "the arrow is on the side facing the icon");
    PASS(CLOSE(NSMinY(l.frame) + l.tip.y, NSMidY(icon)),
         "and points at its middle");
  }

  {
    /* The top icon of a full-height Dock. */
    NSRect icon = NSMakeRect(0, 800 - 30, 64, 30);
    DockLabelLayout l = DockLabelPlace(icon, text, DockEdgeLeft, screen,
                                       gap, arrow, radius, margin);

    PASS(CLOSE(NSMaxY(l.frame), 800 - margin),
         "a label that would hang off the top is kept on the screen");
  }

  /* --- right --- */
  {
    NSRect icon = NSMakeRect(1280 - 64, 400, 64, 64);
    DockLabelLayout l = DockLabelPlace(icon, text, DockEdgeRight, screen,
                                       gap, arrow, radius, margin);

    PASS(CLOSE(NSMaxX(l.frame), 1280 - 64 - gap),
         "at the right the label is to the left of the icon, towards the middle");
    PASS(CLOSE(l.tip.x, NSWidth(l.frame)) && CLOSE(NSMinX(l.body), 0),
         "the arrow is on the box's right, facing the icon");
    PASS(CLOSE(NSMinY(l.frame) + l.tip.y, NSMidY(icon)),
         "and points at its middle");
  }

  {
    /* A name longer than the screen is wide. */
    NSSize wide = NSMakeSize(2000, 26);
    NSRect icon = NSMakeRect(600, 0, 64, 64);
    DockLabelLayout l = DockLabelPlace(icon, wide, DockEdgeBottom, screen,
                                       gap, arrow, radius, margin);

    PASS(NSMinX(l.frame) >= margin && NSMaxX(l.frame) <= 1280 - margin,
         "a label wider than the screen is cut to fit it");
  }

  {
    /* A screen whose origin is not zero (a second monitor). */
    NSRect second = NSMakeRect(1280, 0, 1024, 768);
    NSRect icon = NSMakeRect(1280, 0, 64, 64);
    DockLabelLayout l = DockLabelPlace(icon, text, DockEdgeBottom, second,
                                       gap, arrow, radius, margin);

    PASS(CLOSE(NSMinX(l.frame), 1280 + margin),
         "the label is kept on the screen the Dock is on, wherever it lies");
  }

  [arp release];
  return 0;
}
