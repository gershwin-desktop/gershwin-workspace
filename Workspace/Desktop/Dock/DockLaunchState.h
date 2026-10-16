/* DockLaunchState.h
 *
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-2.0-or-later
 */

#ifndef DOCK_LAUNCH_STATE_H
#define DOCK_LAUNCH_STATE_H

#import <Foundation/Foundation.h>

/* What an application icon in the Dock shows about its application: nothing
 * (idle), a bounce (a launch was asked for and the app has not shown up yet)
 * or the running dot. One state rather than separate launched and bouncing
 * flags, because "running and still bouncing" is not a situation that
 * exists, yet every path that set the running flag without also stopping the
 * bounce produced it (an app whose did-launch notification is late or lost
 * bounced on with its window long on the screen).
 *
 * Transitions:
 *   Requested   idle -> launching; launching stays; running stays (the app
 *               is only activated, so there is nothing to wait for)
 *   DidLaunch   any -> running (the app's did-launch notification)
 *   WindowSeen  any -> running (a mapped window of the app: the user can
 *               see it, so waiting for its did-launch tells them nothing)
 *   Ended       any -> idle (process gone, launch failed, terminated)
 *
 * Foundation-only so the table can be walked headless (t_DockLaunchState). */

typedef enum DockLaunchState
{
  DockLaunchIdle = 0,
  DockLaunchLaunching = 1,
  DockLaunchRunning = 2
} DockLaunchState;

typedef enum DockLaunchEvent
{
  DockLaunchEventRequested = 0,
  DockLaunchEventDidLaunch = 1,
  DockLaunchEventWindowSeen = 2,
  DockLaunchEventEnded = 3
} DockLaunchEvent;

static inline DockLaunchState
DockLaunchStateAfterEvent(DockLaunchState state, DockLaunchEvent event)
{
  switch (event)
    {
      case DockLaunchEventRequested:
        return (state == DockLaunchRunning) ? DockLaunchRunning : DockLaunchLaunching;
      case DockLaunchEventDidLaunch:
        return DockLaunchRunning;
      case DockLaunchEventWindowSeen:
        return DockLaunchRunning;
      case DockLaunchEventEnded:
        return DockLaunchIdle;
    }
  return state;
}

static inline BOOL
DockLaunchStateBounces(DockLaunchState state)
{
  return state == DockLaunchLaunching;
}

static inline BOOL
DockLaunchStateIsRunning(DockLaunchState state)
{
  return state == DockLaunchRunning;
}

#endif
