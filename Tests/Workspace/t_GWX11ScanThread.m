/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

/* t_GWX11ScanThread.m - the app monitor's persistent scan thread must really
 * receive the scans the main thread hands it with performSelector:onThread:.
 * A worker run loop with no input source returns from runMode:beforeDate: at
 * once: the thread spins a whole core and the hand-offs are never delivered,
 * so an app's window is never noticed. No display is needed: only the
 * thread and its run loop are exercised. */

#import <Foundation/Foundation.h>
#import "Testing.h"
#include "../../Workspace/GWProcessOwnership.m"
#include "../../Workspace/X11AppSupport.m"

@interface GWX11AppManager (ScanThreadProbe)
- (NSThread *)probeScanThread;
@end
@implementation GWX11AppManager (ScanThreadProbe)
- (NSThread *)probeScanThread
{
  return scanThread;
}
@end

@interface ScanCounter : NSObject
{
  int hits;
}
- (int)hits;
- (void)hit:(id)ignored;
@end
@implementation ScanCounter
- (int)hits { return hits; }
- (void)hit:(id)ignored { hits++; }
@end

int main(void)
{
  NSAutoreleasePool *arp = [NSAutoreleasePool new];
  GWX11AppManager *manager = [GWX11AppManager sharedManager];
  ScanCounter *counter = [ScanCounter new];
  NSThread *thread;
  int i;
  int loops = 0;
  NSDate *deadline;

  START_SET("X11 app monitor scan thread")
  [manager ensureScanThreadRunning];
  thread = [manager probeScanThread];
  PASS(thread != nil, "the monitor starts one scan thread on demand");
  [NSThread sleepForTimeInterval: 0.3];

  for (i = 0; i < 5; i++)
    {
      [counter performSelector: @selector(hit:)
                      onThread: thread
                    withObject: nil
                 waitUntilDone: NO];
    }
  /* Give the worker two of its one-second run loop timeouts at most. */
  deadline = [NSDate dateWithTimeIntervalSinceNow: 2.5];
  while ([counter hits] < 5 && [deadline timeIntervalSinceNow] > 0)
    {
      [NSThread sleepForTimeInterval: 0.05];
      loops++;
    }
  PASS_EQUAL([counter hits], 5,
             "every scan handed to the persistent thread is delivered");
  [manager stopScanThread];
  END_SET("X11 app monitor scan thread")

  [counter release];
  [arp release];
  return 0;
}
