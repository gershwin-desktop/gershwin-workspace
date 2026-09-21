/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 */

/* -[FSNIconsView tile] sets its own frame, which a surrounding scroll view
 * answers by resizing the clip view, which tiles the icons view again.  With
 * autohiding scrollers that loop does not always settle: opening a folder of
 * a few thousand entries drove it until the stack was gone and Workspace
 * died in cairo.  The view has to stop re-entering itself. */

#import <AppKit/AppKit.h>
#import "Testing.h"
#import "FSNIconsView.h"

static NSUInteger callDepth = 0;
static NSUInteger maxDepth = 0;
static NSUInteger reentries = 0;

@interface ReentrantIconsView : FSNIconsView
@end

@implementation ReentrantIconsView

/* Stands in for the scroll view: every layout pass asks for another one,
 * the way the frame change notification does in a running viewer. */
- (void) layoutIcons
{
  callDepth++;
  if (callDepth > maxDepth)
    maxDepth = callDepth;
  if (reentries < 1000)
    {
      reentries++;
      [self tile];
    }
  callDepth--;
}

@end

int
main(void)
{
  NSAutoreleasePool *arp = [NSAutoreleasePool new];
  ReentrantIconsView *view;

  view = [[ReentrantIconsView alloc] initWithFrame: NSMakeRect(0, 0, 600, 400)];
  [view tile];

  PASS(maxDepth <= 32,
       "a layout pass that asks for another one stops nesting at some point");
  PASS(reentries < 1000,
       "it stops on its own rather than running until the harness cuts it off");
  PASS(reentries > 0, "the test really did ask for another layout pass");

  [view release];
  [arp release];
  return 0;
}
