/* t_DockLaunchState.m - headless coverage for the launch state of a Dock
 * icon: idle, launching (the icon bounces) and running.
 *
 * The bounce has to end as soon as the application shows a window, whether
 * or not its NSWorkspaceDidLaunchApplicationNotification ever reaches the
 * Dock, and every way of becoming "running" has to end it. Walks the whole
 * transition table of DockLaunchState.h, which is Foundation-only.
 *
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-2.0-or-later
 */

#import <Foundation/Foundation.h>
#import "Testing.h"
#import "DockLaunchState.h"

int
main(void)
{
  NSAutoreleasePool *arp = [NSAutoreleasePool new];
  DockLaunchState s;
  int st, ev;

  /* The Whisper case: a launch whose did-launch never arrives. */
  s = DockLaunchStateAfterEvent(DockLaunchIdle, DockLaunchEventRequested);
  PASS(s == DockLaunchLaunching && DockLaunchStateBounces(s),
       "a requested launch makes the icon bounce");
  s = DockLaunchStateAfterEvent(s, DockLaunchEventWindowSeen);
  PASS(s == DockLaunchRunning,
       "a window of the launching app ends the launch without any did-launch");
  PASS(DockLaunchStateBounces(s) == NO,
       "a running icon does not bounce");
  PASS(DockLaunchStateIsRunning(s), "and it shows as running");

  /* Every way into running stops the bounce. */
  PASS(DockLaunchStateAfterEvent(DockLaunchLaunching, DockLaunchEventDidLaunch)
       == DockLaunchRunning,
       "the did-launch notification ends the launch");
  PASS(DockLaunchStateAfterEvent(DockLaunchLaunching, DockLaunchEventEnded)
       == DockLaunchIdle,
       "a launch whose process is gone ends idle, not bouncing");

  /* A running app asked to launch again is only activated: no bounce. */
  PASS(DockLaunchStateAfterEvent(DockLaunchRunning, DockLaunchEventRequested)
       == DockLaunchRunning,
       "a launch request for a running app does not bounce its icon");

  /* A window seen for an idle icon (an app started before the Dock) marks
   * it running, as the window scan always did. */
  PASS(DockLaunchStateAfterEvent(DockLaunchIdle, DockLaunchEventWindowSeen)
       == DockLaunchRunning,
       "a window of an app the Dock did not launch marks it running");

  /* No state x event pair leaves the icon both running and bouncing, and
   * only the launching state bounces. */
  {
    BOOL consistent = YES;

    for (st = DockLaunchIdle; st <= DockLaunchRunning; st++)
      for (ev = DockLaunchEventRequested; ev <= DockLaunchEventEnded; ev++)
        {
          DockLaunchState n = DockLaunchStateAfterEvent((DockLaunchState)st,
                                                        (DockLaunchEvent)ev);
          if (n < DockLaunchIdle || n > DockLaunchRunning)
            consistent = NO;
          if (DockLaunchStateBounces(n) != (n == DockLaunchLaunching))
            consistent = NO;
          if (DockLaunchStateBounces(n) && DockLaunchStateIsRunning(n))
            consistent = NO;
          if ((ev == DockLaunchEventDidLaunch || ev == DockLaunchEventWindowSeen)
              && n != DockLaunchRunning)
            consistent = NO;
        }
    PASS(consistent,
         "every state x event pair is decided, and seeing the app (did-launch "
         "or a window) always leaves it running and not bouncing");
  }

  [arp release];
  return 0;
}
