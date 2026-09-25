/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

/* t_GWDetachedCommand.m - a global-shortcut command must not inherit
 * Workspace's descriptors.  A long-lived command holding Workspace's
 * NSMessagePort socket to gdnc kept that connection open after Workspace
 * died; gdnc queued notifications into it until it crashed.  Headless. */

#import <Foundation/Foundation.h>
#import "Testing.h"
#include "../../Workspace/GWDetachedCommand.m"

#include <signal.h>
#include <stdio.h>
#include <string.h>

/* Stands in for any descriptor Workspace holds (X connection, DO socket);
 * the highest one plain sh redirections can name. */
#define MARKER_FD 9

static void hung(int sig)
{
  (void)sig;
  fprintf(stderr, "Failed test: t_GWDetachedCommand timed out\n");
  _exit(1);
}

int main(void)
{
  NSAutoreleasePool *arp = [NSAutoreleasePool new];
  NSString *ranFile = [NSString stringWithFormat: @"/tmp/t_GWDetachedCommand.%d",
    (int)getpid()];
  NSFileManager *fm = [NSFileManager defaultManager];
  int fds[2];
  char buf[16];
  ssize_t n;
  int i;

  signal(SIGALRM, hung);
  alarm(20);
  /* The command below uses sh syntax; the user's login shell may not. */
  setenv("SHELL", "/bin/sh", 1);
  [fm removeFileAtPath: ranFile handler: nil];

  START_SET("launched command inherits no descriptor above stderr")
    NEED(PASS(pipe(fds) == 0 && fds[0] != MARKER_FD && dup2(fds[1], MARKER_FD) == MARKER_FD,
      "marker descriptor set up"));
    close(fds[1]);

    /* The command writes into the marker descriptor if it has one, then
     * reports that it ran at all, so a command that never started cannot
     * pass for one that inherited nothing. */
    NSString *cmd = [NSString stringWithFormat:
      @"echo leaked >&%d; : > %@", MARKER_FD, ranFile];
    PASS([GWDetachedCommand launchShellCommand: cmd],
      "launchShellCommand: starts the command");

    /* Once our copy is closed only the command can keep the pipe open. */
    close(MARKER_FD);
    n = read(fds[0], buf, sizeof(buf) - 1);
    buf[n > 0 ? n : 0] = '\0';
    close(fds[0]);

    for (i = 0; i < 100 && ![fm fileExistsAtPath: ranFile]; i++)
      {
        usleep(50000);
      }
    PASS([fm fileExistsAtPath: ranFile], "the command ran");
    PASS(n == 0, "the command could not write to an inherited descriptor"
      " (read %d bytes: '%s')", (int)n, buf);
  END_SET("launched command inherits no descriptor above stderr")

  [fm removeFileAtPath: ranFile handler: nil];
  [arp release];
  return 0;
}
