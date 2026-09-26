/*
 * GWWin32Process.m
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

#import "GWWin32Process.h"

#ifdef _WIN32

#define WIN32_LEAN_AND_MEAN
#include <windows.h>

#ifndef PROCESS_QUERY_LIMITED_INFORMATION
#define PROCESS_QUERY_LIMITED_INFORMATION 0x1000
#endif

BOOL GWWin32ProcessIsAlive(pid_t pid)
{
  HANDLE h;
  DWORD code = 0;
  BOOL alive = NO;

  if (pid <= 0)
    return NO;
  h = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, (DWORD)pid);
  if (h == NULL)
    return NO;
  if (GetExitCodeProcess(h, &code) && code == STILL_ACTIVE)
    alive = YES;
  CloseHandle(h);
  return alive;
}

BOOL GWWin32TerminateProcess(pid_t pid)
{
  HANDLE h;
  BOOL ok = NO;

  if (pid <= 0)
    return NO;
  h = OpenProcess(PROCESS_TERMINATE, FALSE, (DWORD)pid);
  if (h == NULL)
    return NO;
  if (TerminateProcess(h, 1))
    ok = YES;
  CloseHandle(h);
  return ok;
}

#endif /* _WIN32 */
