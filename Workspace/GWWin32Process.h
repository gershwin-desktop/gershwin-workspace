/*
 * GWWin32Process.h
 *
 * Process liveness and termination helpers for the Windows build, where
 * kill(2) is not available.  Compiled to nothing elsewhere.
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

#ifndef GW_WIN32_PROCESS_H
#define GW_WIN32_PROCESS_H

#ifdef _WIN32

#import <Foundation/Foundation.h>

/* YES if a process with this id exists and has not exited (the equivalent of
 * kill(pid, 0) == 0 || errno == EPERM). */
BOOL GWWin32ProcessIsAlive(pid_t pid);

/* Forcibly ends the process (the equivalent of kill(pid, SIGKILL)).
 * Returns YES if the termination request was accepted. */
BOOL GWWin32TerminateProcess(pid_t pid);

#endif /* _WIN32 */

#endif /* GW_WIN32_PROCESS_H */
