/*
 * GWWorkerPool.m
 *
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

#import "GWWorkerPool.h"

@implementation GWWorkerPool

- (id)initWithMaximumWorkers:(NSUInteger)count
                      target:(id)aTarget
                    selector:(SEL)aSelector
{
  self = [super init];
  if (self != nil)
    {
      lock = [NSLock new];
      jobs = [NSMutableArray new];
      maximumWorkers = (count > 0) ? count : 1;
      target = [aTarget retain];
      selector = aSelector;
    }
  return self;
}

- (void)dealloc
{
  [lock release];
  [jobs release];
  [target release];
  [super dealloc];
}

- (void)addJob:(id)job
{
  BOOL startWorker = NO;

  [lock lock];
  [jobs addObject: job];
  if (activeWorkers < maximumWorkers)
    {
      activeWorkers++;
      startWorker = YES;
    }
  [lock unlock];

  /* detachNewThreadSelector retains the pool for as long as the worker
   * runs, so jobs in flight outlive a release by the owner. */
  if (startWorker)
    {
      [NSThread detachNewThreadSelector: @selector(runWorker:)
                               toTarget: self
                             withObject: nil];
    }
}

- (void)runWorker:(id)unused
{
  for (;;)
    {
      id job;

      [lock lock];
      if ([jobs count] == 0)
        {
          /* Decided under the lock, so a job added right now either sees
           * this worker still counted (and is taken by it on the next
           * turn) or starts a new one. */
          activeWorkers--;
          [lock unlock];
          return;
        }
      job = [[jobs objectAtIndex: 0] retain];
      [jobs removeObjectAtIndex: 0];
      [lock unlock];

      @autoreleasepool
        {
          [target performSelector: selector withObject: job];
        }
      [job release];
    }
}

@end
