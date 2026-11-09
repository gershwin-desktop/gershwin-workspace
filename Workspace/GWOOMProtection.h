/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */
/*
 * Workspace is part of the desktop's core: on Linux the session inherits a
 * low oom_score_adj from LoginWindow.sh, so the kernel's OOM killer spares
 * it.  The value is inherited by every process Workspace starts, but an
 * application or helper is not core and must stay killable, so that under
 * memory pressure the biggest ordinary app is the one that goes.  These
 * functions hand Workspace's children back to the kernel's normal choice
 * (oom_score_adj 0), which needs no privilege.  On other systems they do
 * nothing.
 */
#import <Foundation/Foundation.h>
#include <sys/types.h>

/* Whether Workspace's children have to be released at all: only when
 * Workspace itself runs with a lowered value. */
BOOL GWOOMShouldReleaseChildren(int ownScoreAdj);

/* The calling process's oom_score_adj; NO when it cannot be read. */
BOOL GWOOMReadOwnScoreAdj(int *scoreAdj);

/* Sets the oom_score_adj of process pid to 0.  YES when it was set, or the
 * process is already gone; logs and returns NO otherwise. */
BOOL GWOOMReleaseProcess(pid_t pid);

/* Sets the calling process's oom_score_adj to 0.  Async-signal-safe, for a
 * child between fork and exec; reports a failure on stderr.  Returns 0 or
 * -1. */
int GWOOMReleaseSelf(void);

/* From now on every NSTask this process launches is released at once.
 * NSTask starts its child with posix_spawn on Linux, which leaves no hook
 * between fork and exec, and Workspace and the bundles it loads start
 * tasks from dozens of places; this is the one place that sees them all. */
void GWOOMReleaseLaunchedTasks(void);

/* Called once at startup: when Workspace runs with a lowered value,
 * releases every NSTask it launches from now on and remembers to release
 * the children it forks itself.  Logs which of the two applies. */
void GWOOMReleaseChildrenIfProtected(void);

/* Whether GWOOMReleaseChildrenIfProtected() found Workspace protected, so
 * a child forked by hand has to call GWOOMReleaseSelf(). */
BOOL GWOOMReleasingChildren(void);
