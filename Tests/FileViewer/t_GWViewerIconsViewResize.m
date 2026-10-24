/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 */

/* While a browsing window in icon view is resized, its icons must stay where
 * they are on the screen: they may only move when the number of columns
 * changes.  The browsing view used to lay out from the bottom of its
 * document, so its top - where the icons are read from - was reached by
 * scrolling, and NSClipView rounds every scroll origin to whole window units.
 * The height of the visible area is fractional at a scale factor such as
 * 1.2, so every step of a live resize left the icons a different fraction
 * below the top: they jumped up and down by one or two pixels all the time.
 *
 * The test resizes a real GWViewerIconsView inside a real scroll view in
 * small fractional steps, larger and then smaller again, and checks that
 * every icon keeps its place relative to the visible top-left corner as long
 * as the column count stays the same, and that the same size gives the same
 * positions again (the layout is a function of the size alone). */

#import <AppKit/AppKit.h>
#import "Testing.h"
#import "GWViewerIconsView.h"
#import "GWViewersManager.h"
#import "Workspace.h"
#import "FSNIcon.h"
#import "FSNode.h"

/* GWViewerIconsView.m talks to these only from event handlers this test
 * never sends; they are here so the class can be linked on its own. */
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wincomplete-implementation"
#pragma clang diagnostic ignored "-Wprotocol"
@implementation GWViewersManager
+ (GWViewersManager *)viewersManager
{
  return nil;
}
@end

@implementation Workspace
+ (Workspace *)gworkspace
{
  return nil;
}
@end
#pragma clang diagnostic pop

BOOL GWForeignWindowIsUnderPointer(void)
{
  return NO;
}

#include "../../Workspace/FileViewer/GWViewerIconsView.m"

/* Every icon's place relative to the visible area's top-left corner, in
 * window units, keyed by the icon's file name. */
static NSDictionary *
iconPlaces(GWViewerIconsView *view, NSClipView *clip)
{
  NSMutableDictionary *places = [NSMutableDictionary dictionary];
  NSRect visible = [clip convertRect: [clip bounds] toView: nil];
  NSEnumerator *e = [[view subviews] objectEnumerator];
  id sub;

  while ((sub = [e nextObject]) != nil)
    {
      NSRect r;

      if ([sub isKindOfClass: [FSNIcon class]] == NO)
        continue;
      r = [sub convertRect: [sub bounds] toView: nil];
      [places setObject: [NSValue valueWithPoint:
                           NSMakePoint(NSMinX(r) - NSMinX(visible),
                                       NSMaxY(visible) - NSMaxY(r))]
                 forKey: [[sub node] name]];
    }
  return places;
}

static NSUInteger
columnCount(NSDictionary *places)
{
  NSMutableSet *xs = [NSMutableSet set];
  NSEnumerator *e = [places objectEnumerator];
  NSValue *v;

  while ((v = [e nextObject]) != nil)
    [xs addObject: [NSNumber numberWithDouble: floor([v pointValue].x * 100.0)]];
  return [xs count];
}

/* The largest distance any icon moved between two sets of places. */
static CGFloat
largestMove(NSDictionary *a, NSDictionary *b)
{
  CGFloat largest = 0;
  NSEnumerator *e = [a keyEnumerator];
  NSString *name;

  while ((name = [e nextObject]) != nil)
    {
      NSPoint p = [[a objectForKey: name] pointValue];
      NSValue *q = [b objectForKey: name];
      CGFloat d;

      if (q == nil)
        return 1e9;
      d = MAX(fabs(p.x - [q pointValue].x), fabs(p.y - [q pointValue].y));
      if (d > largest)
        largest = d;
    }
  return largest;
}

int
main(void)
{
  NSAutoreleasePool *arp = [NSAutoreleasePool new];
  NSFileManager *fm = [NSFileManager defaultManager];
  NSString *dir;
  NSWindow *window;
  NSScrollView *scroll;
  GWViewerIconsView *view;
  NSMutableArray *sizes = [NSMutableArray array];
  NSMutableArray *firstPass = [NSMutableArray array];
  NSDictionary *previous = nil;
  CGFloat worstMove = 0;
  CGFloat worstRepeat = 0;
  NSUInteger columnChanges = 0;
  NSUInteger steps, i;

  /* Views and scroll views need a display server before AppKit makes any. */
  if (getenv("DISPLAY") == NULL)
    {
      printf("no DISPLAY, skipping\n");
      [arp release];
      return 0;
    }
  [NSApplication sharedApplication];

  dir = [NSTemporaryDirectory() stringByAppendingPathComponent:
          [NSString stringWithFormat: @"t_GWViewerIconsViewResize_%d", (int)getpid()]];
  [fm removeFileAtPath: dir handler: nil];
  [fm createDirectoryAtPath: dir attributes: nil];
  for (i = 0; i < 30; i++)
    {
      NSString *name = (i % 7 == 0)
        ? [NSString stringWithFormat: @"A rather long file name number %lu.txt", (unsigned long)i]
        : [NSString stringWithFormat: @"file%02lu.txt", (unsigned long)i];
      [@"x" writeToFile: [dir stringByAppendingPathComponent: name] atomically: NO];
    }

  window = [[NSWindow alloc] initWithContentRect: NSMakeRect(0, 0, 1200, 900)
                                       styleMask: NSBorderlessWindowMask
                                         backing: NSBackingStoreBuffered
                                           defer: YES];
  /* Configured as GWViewer configures the scroll view of an icon view. */
  scroll = [[NSScrollView alloc] initWithFrame: NSMakeRect(0, 40, 700, 420)];
  [scroll setHasHorizontalScroller: YES];
  [scroll setHasVerticalScroller: YES];
  [scroll setAutohidesScrollers: YES];
  [[window contentView] addSubview: scroll];

  view = [[GWViewerIconsView alloc] initForViewer: nil];
  [scroll setDocumentView: view];
  [view showContentsOfNode: [FSNode nodeWithPath: dir]];

  /* A live resize at a scale factor of 1.2: one pixel of the screen is 5/6
   * of a window unit, so the visible area takes fractional sizes. */
  steps = 120;
  for (i = 0; i <= steps; i++)
    [sizes addObject: [NSValue valueWithSize:
                        NSMakeSize(700.0 + i * 3.0 / 1.2, 420.0 + i / 1.2)]];

  for (i = 0; i < 2 * steps + 1; i++)
    {
      NSUInteger k = (i <= steps) ? i : 2 * steps - i;
      NSDictionary *places;

      [scroll setFrameSize: [[sizes objectAtIndex: k] sizeValue]];
      places = iconPlaces(view, [scroll contentView]);

      if (previous != nil)
        {
          if (columnCount(places) == columnCount(previous))
            worstMove = MAX(worstMove, largestMove(previous, places));
          else
            columnChanges++;
        }
      if (i <= steps)
        [firstPass addObject: places];
      else
        worstRepeat = MAX(worstRepeat, largestMove([firstPass objectAtIndex: k], places));
      previous = places;
    }

  PASS([previous count] == 30, "every file has an icon");
  PASS(columnChanges > 0, "the resize did cross column boundaries");
  PASS(worstMove < 0.001,
       "icons keep their place while the column count stays the same");
  PASS(worstRepeat < 0.001,
       "the same size gives the same places on the way back");
  printf("largest move within a column count %.3f, on the way back %.3f, "
         "%lu column changes\n", worstMove, worstRepeat, (unsigned long)columnChanges);

  [view release];
  [scroll release];
  [window release];
  [fm removeFileAtPath: dir handler: nil];
  [arp release];
  return 0;
}
