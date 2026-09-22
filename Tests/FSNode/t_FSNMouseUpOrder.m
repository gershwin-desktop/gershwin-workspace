/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 */

/* An icon's mouseDown: takes the release off the queue to find out whether
 * the press becomes a drag, then puts it back for mouseUp:.  Put back at the
 * end of the queue, it came after a second click that a busy app already had
 * waiting behind it: the window handed the first release to the view in place
 * of the second one, and the second release - the one that opens a
 * double-clicked item - reached no view at all. */

#import <AppKit/AppKit.h>
#import "Testing.h"
#import "FSNFunctions.h"

static NSEvent *
mouseEvent(NSEventType type, NSInteger clicks, NSWindow *window)
{
  return [NSEvent mouseEventWithType: type
			    location: NSMakePoint(10, 10)
		       modifierFlags: 0
			   timestamp: 0
			windowNumber: [window windowNumber]
			     context: nil
			 eventNumber: 0
			  clickCount: clicks
			    pressure: 1.0];
}

/* The mouse events still queued, oldest first, as "up1", "down2", ... */
static NSArray *
drainMouseEvents(void)
{
  NSMutableArray *order = [NSMutableArray array];
  NSUInteger mask = NSLeftMouseDownMask | NSLeftMouseUpMask
    | NSLeftMouseDraggedMask;
  NSEvent *e;

  while ((e = [NSApp nextEventMatchingMask: mask
				 untilDate: [NSDate distantPast]
				    inMode: NSDefaultRunLoopMode
				   dequeue: YES]) != nil)
    {
      NSString *kind = ([e type] == NSLeftMouseDown) ? @"down"
	: (([e type] == NSLeftMouseUp) ? @"up" : @"dragged");

      [order addObject: [NSString stringWithFormat: @"%@%ld",
				  kind, (long)[e clickCount]]];
    }
  return order;
}

int
main(void)
{
  NSAutoreleasePool *arp = [NSAutoreleasePool new];
  NSWindow *window;
  NSEvent *event;

  /* The event queue belongs to NSApp, which wants a display server. */
  if (getenv("DISPLAY") == NULL)
    {
      printf("no DISPLAY, skipping\n");
      [arp release];
      return 0;
    }
  [NSApplication sharedApplication];

  window = [[NSWindow alloc] initWithContentRect: NSMakeRect(0, 0, 100, 100)
				       styleMask: NSBorderlessWindowMask
					 backing: NSBackingStoreBuffered
					   defer: YES];

  /* The first press is being handled; behind it wait its own release and
   * the whole second click of a double click. */
  [NSApp postEvent: mouseEvent(NSLeftMouseUp, 1, window) atStart: NO];
  [NSApp postEvent: mouseEvent(NSLeftMouseDown, 2, window) atStart: NO];
  [NSApp postEvent: mouseEvent(NSLeftMouseUp, 2, window) atStart: NO];

  event = FSNNextMouseUpOrDraggedEvent(window);
  PASS([event type] == NSLeftMouseUp && [event clickCount] == 1,
       "the first press ends with its own release");
  PASS_EQUAL(drainMouseEvents(),
	     ([NSArray arrayWithObjects: @"up1", @"down2", @"up2", nil]),
	     "the release is back where it was, ahead of the second click");

  [NSApp postEvent: mouseEvent(NSLeftMouseDragged, 1, window) atStart: NO];
  event = FSNNextMouseUpOrDraggedEvent(window);
  PASS([event type] == NSLeftMouseDragged,
       "a drag is handed to the caller");
  PASS_EQUAL(drainMouseEvents(), [NSArray array],
	     "and is not put back, the caller starts the drag with it");

  [window release];
  [arp release];
  return 0;
}
