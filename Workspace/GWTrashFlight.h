/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

/* Move to Trash, played out the way a drag to the Dock would look: every
 * selected icon's picture flies from where it sits to the Trash icon along
 * the curve in GWTrashFlightPath.h, shrinking toward the Trash icon's own
 * size, then the flight is over and the caller's completion block runs (to
 * actually recycle the files and, on refusal, show the source icons again).
 *
 * One shaped, borderless overlay window carries every flying icon at once -
 * the same window recipe FSNIconDragSession.m uses for its own drag image
 * (see the gnustep-shaped-drag-window skill) - so nothing but the icons
 * themselves is ever visible while they travel. */

#ifndef GW_TRASH_FLIGHT_H
#define GW_TRASH_FLIGHT_H

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>

@interface GWTrashFlight : NSObject
{
  NSArray *items;                    /* GWTrashFlightItem, one per icon */
  NSRect trashRect;                  /* screen coordinates */
  NSWindow *overlay;
  NSTimer *timer;
  NSTimeInterval startTime;
  NSTimeInterval flightDuration;
  NSTimeInterval staggerStep;
  void (^completion)(void);
  BOOL finished;
}

/* `sourceItems` is an array of NSDictionary, one per flying icon, each with
 * @"rect" (NSValue-wrapped NSRect, the icon's CURRENT screen rect) and
 * @"image" (NSImage, its drag-look picture) - exactly what
 * -flightSourcesForSelectedReps returns.  `aTrashRect` is the Trash icon's
 * current screen rect, the common destination every item flies to.
 * `aCompletion` runs once, after the last icon lands (or at once, on the
 * next run loop turn, if `sourceItems` is empty) - never synchronously
 * inside -start, so the caller's own stack has always unwound first. */
- (id)initWithItems:(NSArray *)sourceItems
          trashRect:(NSRect)aTrashRect
         completion:(void (^)(void))aCompletion;

/* Starts the flight (schedules its timer / orders its window).  The
 * receiver keeps itself alive for the duration of the flight (see the
 * class's -dealloc comment), so the caller does not need to hold onto it -
 * create, -start, and forget. */
- (void)start;

@end

#endif /* GW_TRASH_FLIGHT_H */
