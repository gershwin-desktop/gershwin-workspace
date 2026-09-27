/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

#import "GWChangePaths.h"

NSString *
GWChangePathsDestinationAtIndex(NSArray *dstpaths, NSUInteger j)
{
  return (j < [dstpaths count]) ? [dstpaths objectAtIndex: j] : nil;
}
