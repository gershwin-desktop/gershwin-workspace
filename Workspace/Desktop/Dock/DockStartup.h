/* DockStartup.h
 *
 * When the Dock first appears.  It is put on the screen once, with every
 * item it starts with, instead of being mapped empty and filled while the
 * items are still being added.  What the Dock starts with is its saved
 * applications and folders, the Trash and the windows already minimized,
 * all of which exist when it is built, plus the applications that were
 * already running when Workspace started, which are restored a little
 * later.  Only those last sources are awaited, and never for longer than a
 * bound, so that one that never reports cannot keep the Dock off the screen.
 * Foundation-only inline code so that it can be tested headless.
 *
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

#ifndef DOCK_STARTUP_H
#define DOCK_STARTUP_H

#import <Foundation/Foundation.h>

/* The longest the Dock is held back, in seconds from when it is built. */
#define DOCK_STARTUP_MAX_WAIT 1.0

/* The sources of items that finish after the Dock is built; a set of bits. */
typedef NSUInteger DockStartupSources;

/* The applications that were running already, added as Workspace restores
 * them. */
#define DockStartupRunningApps ((DockStartupSources)1)

/* The running applications only their windows tell of (X11 applications),
 * adopted from a window scan. */
#define DockStartupX11Apps ((DockStartupSources)2)

#define DockStartupAwaitedSources (DockStartupRunningApps | DockStartupX11Apps)

static inline DockStartupSources
DockStartupSourceDone(DockStartupSources pending, DockStartupSources source)
{
  return pending & ~source;
}

/* Whether the Dock may appear: everything awaited has reported, or the bound
 * is over. */
static inline BOOL
DockStartupIsReady(DockStartupSources pending, NSTimeInterval elapsed)
{
  return pending == 0 || elapsed >= DOCK_STARTUP_MAX_WAIT;
}

/* How much of the bound is left, for the timer that enforces it. */
static inline NSTimeInterval
DockStartupRemainingWait(NSTimeInterval elapsed)
{
  if (elapsed < 0)
    elapsed = 0;
  return (elapsed >= DOCK_STARTUP_MAX_WAIT) ? 0.0
                                            : DOCK_STARTUP_MAX_WAIT - elapsed;
}

#endif
