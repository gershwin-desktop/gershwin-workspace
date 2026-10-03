/* t_DockLaunchRefreshThread.m - the Dock's launch-refresh round must share
 * one persistent worker thread across rounds, instead of detaching a new
 * NSThread (and paying for a fresh X connection through
 * -[GWX11WindowManager openDisplay]'s per-thread cache) every 2s.
 *
 * Compiles Dock.m in-process to reach the real
 * -performLaunchRefreshSelector:target:withObject: and -stopLaunchRefreshThread
 * (Dock.h), the same methods -_launchRefreshTimerFired: and
 * -[DockIcon refreshLaunchedStateAsync] use - not a copy of their logic.  A
 * bare `[Dock alloc]` (no -initForManager:) is enough: those two methods only
 * touch the launchRefreshThread/launchRefreshThreadShouldStop ivars, so
 * nothing else Dock.m links against (Workspace, DockService, the desktop
 * manager) is ever reached at runtime - see GNUmakefile.preamble for why
 * those symbols are still allowed to stay undefined in this binary.
 *
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import "Testing.h"
#include "../../Workspace/Desktop/Dock/Dock.m"

/* Records which NSThread ran it and signals the main thread it is done, so
 * the test can drive one round at a time instead of racing
 * performLaunchRefreshSelector:'s waitUntilDone: NO. */
@interface DockLaunchRefreshStub : NSObject
{
@public
  NSMutableArray *seenThreads;
  volatile int roundsDone;
}
- (void)recordThread:(id)ignored;
@end

@implementation DockLaunchRefreshStub
- (id)init
{
  self = [super init];
  if (self)
    {
      seenThreads = [[NSMutableArray alloc] init];
      roundsDone = 0;
    }
  return self;
}
- (void)dealloc
{
  RELEASE(seenThreads);
  [super dealloc];
}
- (void)recordThread:(id)ignored
{
  [seenThreads addObject: [NSThread currentThread]];
  roundsDone++;
}
@end

/* Waits (polling the run loop, since the hand-off is always asynchronous)
 * until the stub has recorded as many rounds as expected, or a timeout - a
 * hang here is itself proof of a bug, not something to wait out forever. */
static BOOL
waitForRounds(DockLaunchRefreshStub *stub, int expected, NSTimeInterval timeout)
{
  NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow: timeout];

  while (stub->roundsDone < expected && [deadline timeIntervalSinceNow] > 0)
    {
      [[NSRunLoop currentRunLoop] runMode: NSDefaultRunLoopMode
                               beforeDate: [NSDate dateWithTimeIntervalSinceNow: 0.01]];
    }
  return stub->roundsDone >= expected;
}

int
main(void)
{
  NSAutoreleasePool *arp = [NSAutoreleasePool new];
  Dock *dock;
  DockLaunchRefreshStub *stub;
  NSMutableSet *distinctThreads;
  int round;
  const int totalRounds = 5;

  /* No -initForManager: - see the file comment above for why a bare alloc is
   * enough for this. */
  dock = [Dock alloc];
  stub = [[DockLaunchRefreshStub alloc] init];

  for (round = 0; round < totalRounds; round++)
    {
      [dock performLaunchRefreshSelector: @selector(recordThread:)
                                   target: stub
                               withObject: nil];
      PASS(waitForRounds(stub, round + 1, 2.0),
           "round %d of %d completed within the timeout", round + 1, totalRounds);
    }

  distinctThreads = [NSMutableSet set];
  for (NSThread *t in stub->seenThreads)
    {
      [distinctThreads addObject: [NSValue valueWithNonretainedObject: t]];
    }

  PASS([stub->seenThreads count] == (NSUInteger)totalRounds,
       "the stub worker ran once per round (%lu of %d)",
       (unsigned long)[stub->seenThreads count], totalRounds);

  PASS([distinctThreads count] == 1,
       "%d launch-refresh rounds all ran on the Dock's one persistent worker "
       "thread instead of detaching a new NSThread per round (saw %lu "
       "distinct threads)",
       totalRounds, (unsigned long)[distinctThreads count]);

  PASS([[NSThread currentThread] isEqual:
          [[distinctThreads anyObject] nonretainedObjectValue]] == NO,
       "the worker thread is not the main thread - the X scans it runs must "
       "not block the main run loop");

  /* -dealloc would also stop it; called directly since this Dock was never
   * -initForManager:'d. Proves the thread really is stoppable, not just
   * reused. */
  [dock stopLaunchRefreshThread];

  RELEASE(stub);
  [arp release];
  return 0;
}
