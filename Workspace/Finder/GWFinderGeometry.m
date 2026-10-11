/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

#import <math.h>
#import "GWFinderGeometry.h"

NSRect GWFinderFrameForModulesHeight(NSRect frame,
                                     CGFloat currentHeight,
                                     CGFloat neededHeight,
                                     CGFloat scaleFactor)
{
  /* Rounded up to whole pixels: a frame between pixels is truncated by the
     backend, which would cut the bottom row by a pixel line again. */
  CGFloat delta = ceil((neededHeight - currentHeight) * scaleFactor);

  frame.origin.y -= delta;
  frame.size.height += delta;
  return frame;
}
