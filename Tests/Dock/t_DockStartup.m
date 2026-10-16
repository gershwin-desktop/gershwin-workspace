/* t_DockStartup.m - headless coverage for when the Dock first appears.
 *
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

#import <Foundation/Foundation.h>
#import "Testing.h"
#import "DockStartup.h"

#define CLOSE(a, b) (fabs((a) - (b)) < 0.001)

int
main(void)
{
  NSAutoreleasePool *arp = [NSAutoreleasePool new];
  DockStartupSources pending = DockStartupAwaitedSources;
  DockStartupSources none = 0;

  PASS(pending != 0, "the Dock waits for something at startup");
  PASS((pending & DockStartupRunningApps) != 0,
       "the restored running applications are awaited");
  PASS((pending & DockStartupX11Apps) != 0,
       "the adopted running X11 applications are awaited");

  PASS(DockStartupIsReady(pending, 0.0) == NO,
       "not ready while a source is pending and the bound has not passed");
  PASS(DockStartupIsReady(pending, DOCK_STARTUP_MAX_WAIT / 2) == NO,
       "still not ready half way to the bound");

  pending = DockStartupSourceDone(pending, DockStartupRunningApps);
  PASS(pending != none && DockStartupIsReady(pending, 0.0) == NO,
       "the registry alone does not let the Dock appear");
  pending = DockStartupSourceDone(pending, DockStartupX11Apps);
  PASS(pending == none, "reporting the last source leaves nothing pending");
  PASS(DockStartupIsReady(pending, 0.0),
       "ready as soon as every source reported, without any waiting");

  pending = DockStartupAwaitedSources;
  PASS(DockStartupIsReady(pending, DOCK_STARTUP_MAX_WAIT),
       "a source that never reports holds the Dock back no longer than the bound");
  PASS(DockStartupIsReady(pending, DOCK_STARTUP_MAX_WAIT * 5),
       "and stays ready afterwards");

  PASS(DOCK_STARTUP_MAX_WAIT <= 1.0, "the bound is short");
  PASS(CLOSE(DockStartupRemainingWait(0.25), DOCK_STARTUP_MAX_WAIT - 0.25),
       "the timer is armed for what is left of the bound");
  PASS(CLOSE(DockStartupRemainingWait(DOCK_STARTUP_MAX_WAIT * 3), 0.0),
       "nothing is left once the bound passed");
  PASS(CLOSE(DockStartupRemainingWait(-1.0), DOCK_STARTUP_MAX_WAIT),
       "a clock that went back does not stretch the bound");

  [arp release];
  return 0;
}
