/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

/* The pure geometry behind the "fly to Trash" animation, kept Foundation-only
 * (no AppKit, no window server) so it can be red/green tested headless: no
 * Xvfb, no NSApplication, just NSRect/NSPoint arithmetic in and out. */

#ifndef GW_TRASH_FLIGHT_PATH_H
#define GW_TRASH_FLIGHT_PATH_H

#import <Foundation/Foundation.h>

/* How far the flight path bows away from the straight line between the
 * start and end rects, as a fraction of the distance between their centers.
 * Public so a test can check the midpoint deviation against it without
 * duplicating the curve's own arithmetic. */
extern const CGFloat GWTrashFlightBowFraction;

/* Symmetric ease-in-out: 0 at t=0, 1 at t=1, 0.5 at t=0.5, and
 * ease(1-t) == 1-ease(t) for every t - so a flight that eases in exactly
 * mirrors the way it eases out. */
CGFloat GWTrashFlightEaseInOut(CGFloat t);

/* The rect a flying icon occupies at time t (0...1, un-eased - the easing
 * is applied inside): interpolates the CENTER of startRect to the CENTER of
 * endRect along a cubic Bezier that bows away from the straight line by
 * GWTrashFlightBowFraction of the distance between them, and interpolates
 * the SIZE from startRect's to endRect's, both using the eased time so the
 * whole flight (position and shrink together) starts and ends gently.
 *
 * The bow direction is the straight line's own perpendicular, biased toward
 * +y (screen up) whenever that is meaningful.  For the common case - a
 * source well to the side of the Dock, mostly a horizontal path - the
 * perpendicular is close to vertical, so the path rises and swoops down as
 * asked for; the same rule degrades into a sideways bow on its own once the
 * path is itself close to vertical, where "rises" has nowhere clearly
 * upward left to mean.  One rule instead of a case split on the path's
 * angle, and it never produces a degenerate (zero-width) arc.
 *
 * t <= 0 returns startRect exactly; t >= 1 returns endRect exactly (size
 * included) - the two ends a caller can rely on without special-casing the
 * first and last frame. */
NSRect GWTrashFlightRectAtTime(NSRect startRect, NSRect endRect, CGFloat t);

#endif /* GW_TRASH_FLIGHT_PATH_H */
