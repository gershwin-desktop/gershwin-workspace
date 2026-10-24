/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 */

/* Layout of the browsing window's content box: the content (with its
 * horizontal scroller at its bottom edge) sits directly above the path
 * bar, the inspector beside the content, the path bar under both. */

#import <Foundation/Foundation.h>
#import "Testing.h"

#include "../../Workspace/FileViewer/GWViewerGeometry.m"

int
main(void)
{
  NSAutoreleasePool *arp = [NSAutoreleasePool new];
  NSSize size = NSMakeSize(500, 300);
  GWViewerBoxLayout l;

  l = GWViewerBoxLayoutForSize(size, YES, 30, NO, 288);
  PASS(NSEqualRects(l.pathBar, NSMakeRect(0, 0, 500, 30)),
       "path bar is the bottom strip over the full width");
  PASS(NSEqualRects(l.content, NSMakeRect(0, 30, 500, 270)),
       "content starts right on top of the path bar, nothing between");
  PASS(NSMinY(l.content) == NSMaxY(l.pathBar),
       "the content's bottom edge (its horizontal scroller) touches the path bar's top");
  PASS(NSIsEmptyRect(l.inspector), "no inspector without the toggle");

  l = GWViewerBoxLayoutForSize(size, NO, 30, NO, 288);
  PASS(NSEqualRects(l.content, NSMakeRect(0, 0, 500, 300)),
       "hidden path bar gives its height back to the content");
  PASS(NSIsEmptyRect(l.pathBar), "hidden path bar has no frame");

  l = GWViewerBoxLayoutForSize(size, YES, 30, YES, 288);
  PASS(NSEqualRects(l.content, NSMakeRect(0, 30, 212, 270)),
       "content gives the inspector's width away on the right");
  PASS(NSEqualRects(l.inspector, NSMakeRect(212, 30, 288, 270)),
       "inspector sits beside the content, above the path bar");
  PASS(NSEqualRects(l.pathBar, NSMakeRect(0, 0, 500, 30)),
       "path bar spans under the inspector too");

  l = GWViewerBoxLayoutForSize(size, NO, 30, YES, 288);
  PASS(NSEqualRects(l.inspector, NSMakeRect(212, 0, 288, 300)),
       "inspector fills the full height without a path bar");

  l = GWViewerBoxLayoutForSize(NSMakeSize(200, 20), YES, 30, YES, 288);
  PASS(NSWidth(l.content) == 0 && NSHeight(l.content) == 0
       && NSWidth(l.inspector) == 200,
       "a box smaller than path bar and inspector gives empty, never negative, sizes");

  RELEASE(arp);
  return 0;
}
