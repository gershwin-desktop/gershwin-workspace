/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 */

/* Resizing a spatial window in icon view crashed Workspace: the scroll view
 * and its scrollers retiled each other until the stack was gone (a SIGSEGV
 * in -[NSView _rebuildCoordinates] under thousands of alternating
 * -[GWViewerScrollView tile] / -[NSScrollView reflectScrolledClipView:]
 * frames).  The spatial scroll view keeps its top row for a separator line
 * and gives the clip view one row less than NSScrollView laid out.  Whenever
 * the document was exactly as high as NSScrollView's clip, it fitted while
 * NSScrollView decided about the scroller and did not fit once the row was
 * taken away, so the vertical scroller came and went for ever.
 *
 * The test resizes a real GWViewerScrollView with the separator around a
 * real GWSpatialIconsView in small fractional steps and checks that tiling
 * never nests more than a few levels deep. */

#import <AppKit/AppKit.h>
#import "Testing.h"
#import "GWViewerScrollView.h"
#import "GWSpatialIconsView.h"
#import "GWViewersManager.h"
#import "Workspace.h"
#import "FSNIcon.h"
#import "FSNode.h"

/* GWViewerIconsView.m talks to these only from event handlers this test
 * never sends; they are here so the classes can be linked on their own. */
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
#include "../../Workspace/FileViewer/GWSpatialIconsView.m"
#include "../../Workspace/FileViewer/GWViewerScrollView.m"

/* What GWViewerScrollView asks its viewer. */
@interface SpatialViewerStub : NSObject
{
@public
  id view;
}
@end

@implementation SpatialViewerStub
- (BOOL)isSpatial
{
  return YES;
}
- (id)nodeView
{
  return view;
}
- (void)selectionChanged:(NSArray *)selection
{
}
@end

static NSUInteger depth = 0;
static NSUInteger deepest = 0;

/* Counts how deep -tile nests, and cuts the nesting off where the unfixed
 * code would only have gone on until the stack was gone. */
@interface CountingScrollView : GWViewerScrollView
@end

@implementation CountingScrollView
- (void)tile
{
  depth++;
  if (depth > deepest)
    deepest = depth;
  if (depth <= 64)
    [super tile];
  depth--;
}
@end

int
main(void)
{
  NSAutoreleasePool *arp = [NSAutoreleasePool new];
  NSFileManager *fm = [NSFileManager defaultManager];
  SpatialViewerStub *viewer;
  NSString *dir;
  NSWindow *window;
  CountingScrollView *scroll;
  GWSpatialIconsView *view;
  NSUInteger i, deepAt = 0;
  NSSize deepSize = NSZeroSize;

  /* Views and scroll views need a display server before AppKit makes any. */
  if (getenv("DISPLAY") == NULL)
    {
      printf("no DISPLAY, skipping\n");
      [arp release];
      return 0;
    }
  [NSApplication sharedApplication];

  dir = [NSTemporaryDirectory() stringByAppendingPathComponent:
          [NSString stringWithFormat: @"t_GWSpatialScrollResize_%d", (int)getpid()]];
  [fm removeFileAtPath: dir handler: nil];
  [fm createDirectoryAtPath: dir attributes: nil];
  for (i = 0; i < 31; i++)
    [@"x" writeToFile: [dir stringByAppendingPathComponent:
                         [NSString stringWithFormat: @"file%02lu.txt", (unsigned long)i]]
           atomically: NO];

  window = [[NSWindow alloc] initWithContentRect: NSMakeRect(0, 0, 1400, 1000)
                                       styleMask: NSBorderlessWindowMask
                                         backing: NSBackingStoreBuffered
                                           defer: YES];
  viewer = [SpatialViewerStub new];

  /* Set up as GWSpatialViewer sets up an icon view's scroll view
   * (-createSubviews, then the vertical scroller for the icon view). */
  scroll = [[CountingScrollView alloc] initWithFrame: NSMakeRect(0, 0, 800, 560)
                                             inViewer: viewer];
  [scroll setBorderType: NSNoBorder];
  [scroll setDrawsTopSeparator: YES];
  [scroll setHasHorizontalScroller: YES];
  [scroll setHasVerticalScroller: YES];
  [scroll setAutohidesScrollers: YES];
  [[window contentView] addSubview: scroll];

  view = [[GWSpatialIconsView alloc] initForViewer: viewer];
  viewer->view = view;
  [scroll setDocumentView: view];
  [view showContentsOfNode: [FSNode nodeWithPath: dir]];

  /* A live resize at a scale factor of 1.2 (a screen pixel is 5/6 of a
   * window unit), larger and smaller, past the size of the canvas. */
  for (i = 0; i <= 2 * 600; i++)
    {
      NSUInteger k = (i <= 600) ? i : 2 * 600 - i;
      NSSize s = NSMakeSize(400.0 + k * 1.0 / 1.2, 300.0 + k * 1.0 / 1.2);

      depth = 0;
      deepest = 0;
      [scroll setFrameSize: s];
      if (deepest > deepAt)
        {
          deepAt = deepest;
          deepSize = s;
        }
    }

  /* The heights where it happened: the canvas (the document view, as
   * high as its lowest icon) just higher than the scroll view, by less than
   * the separator's row. */
  {
    CGFloat canvas;
    NSUInteger j;

    [scroll setFrameSize: NSMakeSize(900, 200)];
    canvas = NSHeight([view frame]);
    for (j = 0; j <= 48; j++)
      {
        NSSize s = NSMakeSize(900.0 + j / 1.2, canvas - 2.0 + j / 12.0);

        depth = 0;
        deepest = 0;
        [scroll setFrameSize: s];
        if (deepest > deepAt)
          {
            deepAt = deepest;
            deepSize = s;
          }
      }
  }

  PASS(deepAt > 0, "the resize did tile the scroll view");
  PASS(deepAt <= 8, "tiling settles instead of retiling itself without end");
  printf("deepest nesting of -tile %lu (at %.2f x %.2f)\n",
         (unsigned long)deepAt, deepSize.width, deepSize.height);

  [view release];
  [scroll release];
  [window release];
  [viewer release];
  [fm removeFileAtPath: dir handler: nil];
  [arp release];
  return 0;
}
