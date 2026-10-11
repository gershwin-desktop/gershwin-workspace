/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-2.0-or-later
 */

#ifndef GWSINGLEINSTANCE_H
#define GWSINGLEINSTANCE_H

#ifndef _WIN32

#include <sys/types.h>

/* Name of the per-screen selection a running Workspace owns.  Not WM_Sn:
 * that one belongs to the window manager. */
const char *GWSingleInstanceSelectionName(int screen);

/* The process a starting Workspace may replace, or 0.  ownerPID is the
 * _NET_WM_PID of the previous owner of the selection on OUR display (0 or
 * negative when there is none), so a Workspace on another display is never
 * a candidate. */
pid_t GWSingleInstanceVictim(pid_t ownerPID, pid_t ownPID);

/* Replaces the Workspace of this X display, if any, and becomes the owner of
 * the selection on every screen for the life of the process.  Returns NO
 * (with a message on stderr) when the display cannot be used. */
int GWSingleInstanceClaimDisplay(void);

#endif /* !_WIN32 */

#endif
