/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

/* t_GWWorkerPool.m - Workspace started one thread per AppImage icon, so a
 * folder of fifty AppImages started fifty loader threads at once.
 * GWWorkerPool runs queued jobs on a bounded number of threads: every job
 * runs, several run at the same time, never more than the limit, and the
 * pool comes back after it ran dry. Headless, Foundation only. */

#import <Foundation/Foundation.h>
#import "Testing.h"
#import "GWWorkerPool.h"

@interface Counter : NSObject
{
@public
  NSLock *lock;
  NSUInteger running, peak, done;
}
- (void)work: (id)job;
@end

@implementation Counter
- (id)init
{
  self = [super init];
  lock = [NSLock new];
  return self;
}
- (void)dealloc
{
  [lock release];
  [super dealloc];
}
- (void)work: (id)job
{
  [lock lock];
  running++;
  if (running > peak) peak = running;
  [lock unlock];
  usleep(20000);
  [lock lock];
  running--;
  done++;
  [lock unlock];
}
- (NSUInteger)done
{
  NSUInteger d;
  [lock lock];
  d = done;
  [lock unlock];
  return d;
}
@end

static BOOL
waitForDone(Counter *c, NSUInteger n)
{
  int i;

  for (i = 0; i < 500 && [c done] < n; i++)
    {
      usleep(10000);
    }
  return [c done] == n;
}

int
main(void)
{
  NSAutoreleasePool *arp = [NSAutoreleasePool new];
  Counter *counter = [Counter new];
  GWWorkerPool *pool = [[GWWorkerPool alloc] initWithMaximumWorkers: 4
                                                             target: counter
                                                           selector: @selector(work:)];
  NSUInteger i;

  for (i = 0; i < 20; i++)
    {
      [pool addJob: [NSNumber numberWithUnsignedInteger: i]];
    }
  PASS(waitForDone(counter, 20), "all twenty jobs ran");
  PASS(counter->peak <= 4, "never more than four at once (peak %lu)",
       (unsigned long)counter->peak);
  PASS(counter->peak >= 2, "jobs ran in parallel (peak %lu)",
       (unsigned long)counter->peak);

  for (i = 0; i < 3; i++)
    {
      [pool addJob: [NSNumber numberWithUnsignedInteger: i]];
    }
  PASS(waitForDone(counter, 23), "jobs added after the pool ran dry still run");

  [pool release];
  [counter release];
  [arp release];
  return 0;
}
