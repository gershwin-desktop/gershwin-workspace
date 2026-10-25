/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-2.0-or-later
 */

/*
 * The primary monitor, as every desktop component (Menu, the Workspace
 * desktop and its Dock) has to agree on it.
 *
 * Kept as an identical copy in gershwin-components (Menu/PrimaryMonitor.[hm])
 * and gershwin-workspace (Workspace/Desktop/PrimaryMonitor.[hm]): the two
 * repositories share no library, and the menu bar, the desktop icons and the
 * Dock must land on the same monitor.  Change both copies together;
 * gershwin-components Menu/Tests/check-primary-monitor-sync.sh compares them.
 *
 * The rule:
 *   1. the RandR primary output's CRTC rectangle, when a primary is set and
 *      that output is lit;
 *   2. otherwise the lit monitor that contains the root origin (0,0);
 *   3. otherwise the first lit monitor in RandR output order;
 *   4. with no lit output, or no RandR at all, the whole X screen - the same
 *      single monitor the GNUstep X11 backend reports then.
 *
 * Rule 1 is what puts a monitor at index 0 of +[NSScreen screens]; rules 2
 * and 3 make the choice stable when nobody has set a primary, where
 * screens[0] would merely be whichever output comes first.
 */

#ifndef PRIMARY_MONITOR_H
#define PRIMARY_MONITOR_H

#import <Foundation/Foundation.h>
#include <X11/Xlib.h>

/* Which root edge a panel window is attached to, for the strut. */
typedef enum {
  PrimaryMonitorEdgeTop,
  PrimaryMonitorEdgeBottom,
  PrimaryMonitorEdgeLeft,
  PrimaryMonitorEdgeRight
} PrimaryMonitorEdge;

/* Index into xRects (lit monitors, X root coordinates: origin top-left,
 * y down) of the primary monitor by rules 1-3 above.  primaryIndex is the
 * index of the RandR primary output among xRects, or -1 when none is set or
 * it is not lit.  Returns -1 only for count == 0. */
NSInteger PrimaryMonitorChooseIndex(const NSRect *xRects, NSUInteger count,
                                    NSInteger primaryIndex);

/* Converts a rectangle between X root coordinates (origin top-left, y down)
 * and GNUstep screen coordinates (origin bottom-left, y up).  The mapping is
 * its own inverse, so it serves both directions. */
NSRect PrimaryMonitorFlipRect(NSRect rect, CGFloat rootHeight);

/* The current size of the X screen (device pixels), asked of the server.
 * DisplayWidth()/DisplayHeight() are cached per Xlib connection and only
 * change when that connection processes RandR events itself, which a
 * connection opened just for queries never does. */
NSSize PrimaryMonitorRootSize(Display *dpy);

/* Asks the X server for the primary monitor.  xRect receives its rectangle
 * in X root coordinates, rootSize the size of the X screen (both device
 * pixels).  Either pointer may be NULL.  Returns NO only when dpy is NULL. */
BOOL PrimaryMonitorQuery(Display *dpy, NSRect *xRect, NSSize *rootSize);

/* The primary monitor's frame in GNUstep screen coordinates (device pixels,
 * like -[NSScreen frame]).  Returns NSZeroRect only when dpy is NULL. */
NSRect PrimaryMonitorScreenFrame(Display *dpy);

/* _NET_WM_STRUT_PARTIAL values (12 cardinals) for a panel whose window
 * occupies barXRect (X root coordinates) along the given edge of the
 * monitor it sits on; the start/end range is the panel's own extent.  The
 * first four values are _NET_WM_STRUT.
 *
 * EWMH measures struts from the edges of the root window.  A panel whose
 * outer side is not on that root edge (its monitor is below, beside or
 * shorter than another one) gets no strut at all: reserving from the root
 * edge would take the same depth off every monitor for window managers
 * that ignore the start/end range, as gershwin-windowmanager does today,
 * and only the panel's own monitor is meant to give the room up.  Panels
 * such as tint2 follow the same rule. */
void PrimaryMonitorStrutForPanel(NSRect barXRect, NSSize rootSize,
                                 PrimaryMonitorEdge edge,
                                 unsigned long strut[12]);

#endif
