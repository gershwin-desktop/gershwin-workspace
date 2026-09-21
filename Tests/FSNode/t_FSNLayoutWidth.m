/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 */

/* The width an icons view lays out for must not change when an autohiding
 * vertical scroller comes and goes: the icons would reflow, the new height
 * would turn the scroller off again, and the scroll view and the view would
 * swap sizes for as long as the process lived. */

#import <AppKit/AppKit.h>
#import "Testing.h"
#import "FSNIconsView.h"

int
main(void)
{
  NSAutoreleasePool *arp = [NSAutoreleasePool new];
  NSScrollView *scroll;
  FSNIconsView *view;
  CGFloat withoutScroller, withScroller;
  CGFloat contentWithout, contentWith;

  /* Views and a scroll view are all this needs, but AppKit wants a display
   * server before it will make any of them. */
  if (getenv("DISPLAY") == NULL)
    {
      printf("no DISPLAY, skipping\n");
      [arp release];
      return 0;
    }
  [NSApplication sharedApplication];

  scroll = [[NSScrollView alloc] initWithFrame: NSMakeRect(0, 0, 400, 300)];
  [scroll setAutohidesScrollers: YES];
  [scroll setHasVerticalScroller: NO];

  view = [[FSNIconsView alloc] initWithFrame: NSMakeRect(0, 0, 400, 300)];
  [scroll setDocumentView: view];

  [scroll tile];
  contentWithout = [scroll contentSize].width;
  withoutScroller = [view windowContentWidthForLayout];

  [scroll setHasVerticalScroller: YES];
  [scroll tile];
  contentWith = [scroll contentSize].width;
  withScroller = [view windowContentWidthForLayout];

  PASS_EQUAL([NSNumber numberWithDouble: withoutScroller],
             [NSNumber numberWithDouble: contentWithout - [NSScroller scrollerWidth]],
             "the scroller's width is kept free while the scroller is hidden");
  PASS_EQUAL([NSNumber numberWithDouble: withoutScroller],
             [NSNumber numberWithDouble: withScroller],
             "so the layout width does not change when the scroller appears");
  printf("content area %.2f/%.2f, layout width %.2f/%.2f\n",
         contentWithout, contentWith, withoutScroller, withScroller);

  [view release];
  [scroll release];
  [arp release];
  return 0;
}
