/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

#import "GWDetachedCommand.h"

#include <errno.h>
#include <fcntl.h>
#include <stdlib.h>
#include <sys/wait.h>
#include <unistd.h>

@implementation GWDetachedCommand

+ (BOOL)launchShellCommand:(NSString *)command
{
  /* Workspace is multithreaded: after fork() only async-signal-safe calls
   * are allowed, so everything the child needs is prepared here. */
  const char *shell = getenv("SHELL");
  const char *cmd = [command UTF8String];
  long maxfd = sysconf(_SC_OPEN_MAX);
  pid_t pid;
  int status;

  if (shell == NULL || *shell == '\0')
    {
      shell = "/bin/sh";
    }

  if (maxfd < 0)
    {
      return NO;
    }

  pid = fork();
  if (pid < 0)
    {
      return NO;
    }

  if (pid == 0)
    {
      int devnull;
      pid_t grandchild;

      setsid();

      devnull = open("/dev/null", O_RDWR);
      if (devnull < 0)
        {
          _exit(1);
        }
      dup2(devnull, STDIN_FILENO);
      dup2(devnull, STDOUT_FILENO);
      dup2(devnull, STDERR_FILENO);
      /* A plain loop because closefrom() is not available everywhere; this
       * also closes devnull. */
      for (long fd = STDERR_FILENO + 1; fd < maxfd; fd++)
        {
          close((int)fd);
        }

      /* The intermediate child exits at once so the command is reparented
       * to init and never becomes a zombie of Workspace. */
      grandchild = fork();
      if (grandchild == 0)
        {
          execl(shell, shell, "-c", cmd, (char *)NULL);
          _exit(127);
        }
      _exit(grandchild > 0 ? 0 : 1);
    }

  while (waitpid(pid, &status, 0) < 0)
    {
      if (errno == EINTR)
        {
          continue;
        }
      /* Someone else (NSTask's SIGCHLD handling) reaped it already. */
      return (errno == ECHILD);
    }

  return (WIFEXITED(status) && WEXITSTATUS(status) == 0);
}

@end
