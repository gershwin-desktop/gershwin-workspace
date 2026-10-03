/* t_DockIconScan.m - headless coverage for which icons the launch-refresh
 * round actually needs to scan.
 *
 * DockIconNeedsLaunchedStateScan() lives in Dock.h as a Foundation-only
 * static inline function, mirroring what -refreshLaunchedStateWorker:
 * (DockIcon.m) does with its inputs: an X11-tracked icon always re-checks
 * its windows, a launched icon whose pid is not yet known tries once to
 * discover it, and anything else takes an early-return path that makes no
 * X call at all. Dock.h drags in GWDesktopManager.h and FSNodeRep.h for
 * their declarations only; nothing here links FSNode or DockIcon.
 *
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import "Testing.h"
#import "Dock.h"

int
main(void)
{
  NSAutoreleasePool *arp = [NSAutoreleasePool new];

  PASS(DockIconNeedsLaunchedStateScan(NO, NO, 0) == NO,
       "a docked, not-running icon needs no scan: refreshLaunchedStateWorker: "
       "takes its early-return path and makes no X call for it");

  PASS(DockIconNeedsLaunchedStateScan(NO, YES, 4242) == NO,
       "a launched GNUstep icon whose pid is already known needs no scan "
       "either: same early-return path");

  PASS(DockIconNeedsLaunchedStateScan(NO, YES, 0) == YES,
       "a launched icon whose pid is still unknown needs a scan: the "
       "worker spends one X call trying to discover it");

  PASS(DockIconNeedsLaunchedStateScan(YES, NO, 0) == YES,
       "an X11-tracked icon needs a scan even while not launched: the "
       "worker always re-checks its windows once tracking has started");

  PASS(DockIconNeedsLaunchedStateScan(YES, YES, 4242) == YES,
       "an X11-tracked, running icon needs a scan every round: only a "
       "fresh hasWindowsForPID: call can notice its windows closing "
       "without the process exiting");

  [arp release];
  return 0;
}
