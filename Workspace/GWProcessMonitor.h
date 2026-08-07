/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#ifndef GWPROCESSMONITOR_H
#define GWPROCESSMONITOR_H

#import <Foundation/Foundation.h>

/**
 * Monitors process lifetime using kernel-optimized mechanisms:
 *
 *  - Linux: pidfd_open() + poll()  (kernel 5.3+)
 *  - BSD:   kqueue() + EVFILT_PROC + NOTE_EXIT
 *  - Fallback: NSTimer-based kill(pid, 0) polling
 *
 * This is the primary path for detecting application termination
 * in the Dock.  It is more robust than NSWorkspace notifications
 * (which only fire for GNUstep apps cleanly launched via NSWorkspace)
 * and avoids the PID-reuse race inherent to kill(pid,0) polling.
 */
@interface GWProcessMonitor : NSObject

+ (instancetype)sharedMonitor;

/**
 * Start monitoring a PID.  When the process exits, callback is invoked
 * on the main thread with the PID and the opaque token that was passed here.
 * If the PID is already being tracked, it is re-registered (callback
 * replaced).
 */
- (void)addPID:(pid_t)pid
         token:(id)token
      callback:(void (^)(pid_t pid, id token))block;

/**
 * Stop monitoring a PID.  Safe to call even if the PID was never added.
 */
- (void)removePID:(pid_t)pid;

/**
 * Synchronously check whether a process or any direct child of it is still
 * running.  Used as a lightweight poll (e.g. once per dock bounce iteration)
 * as a complement to the event-driven addPID: monitoring, so a process that
 * dies while an animation is in flight can be detected immediately.
 */
- (BOOL)processOrChildrenAlive:(pid_t)pid;

/**
 * Synchronously check whether any live process matches the given app name.
 * Used by the Dock launch bounce when no PID was ever bound (a launch that
 * failed before creating a process), where there is no PID to poll.
 */
- (BOOL)processNamedAlive:(NSString *)name;

@end

#endif
