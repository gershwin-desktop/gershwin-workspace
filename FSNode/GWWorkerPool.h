/*
 * GWWorkerPool.h
 *
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

/* Runs queued jobs on at most a fixed number of GNUstep threads, started
 * when there is work and ended when the queue is empty, so a burst of
 * small jobs neither starts a thread each nor waits for one another.
 * GNUstep threads rather than libdispatch: a GCD worker running ObjC can
 * race the main thread's +load dispatch and crash in libobjc's
 * load_messages_insert. */

#ifndef GW_WORKER_POOL_H
#define GW_WORKER_POOL_H

#import <Foundation/Foundation.h>

@interface GWWorkerPool : NSObject
{
  NSLock *lock;
  NSMutableArray *jobs;
  NSUInteger maximumWorkers;
  NSUInteger activeWorkers;
  id target;
  SEL selector;
}

/* target receives selector with each job, on a worker thread, inside its
 * own autorelease pool. target is retained. */
- (id)initWithMaximumWorkers:(NSUInteger)count
                      target:(id)aTarget
                    selector:(SEL)aSelector;

- (void)addJob:(id)job;

@end

#endif
