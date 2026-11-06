/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

#import "GWOpenAnimationGate.h"

@implementation GWOpenAnimationGate

- (void)dealloc
{
  [pending release];
  [super dealloc];
}

- (void)arm:(id)request
{
  [request retain];
  [pending release];
  pending = request;
}

- (id)fire
{
  id request = [pending autorelease];

  pending = nil;
  return request;
}

- (void)disarm
{
  [pending release];
  pending = nil;
}

@end
