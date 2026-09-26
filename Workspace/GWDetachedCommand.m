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
  const char *shell = getenv("SHELL");

  if (shell == NULL || *shell == '\0')
    {
      shell = "/bin/sh";
    }
  return [self launchArguments: [NSArray arrayWithObjects:
    [NSString stringWithUTF8String: shell], @"-c", command, nil]];
}

+ (BOOL)launchArguments:(NSArray *)arguments
{
  /* Workspace is multithreaded: after fork() only async-signal-safe calls
   * are allowed, so everything the child needs is prepared here. */
  NSUInteger count = [arguments count];
  long maxfd = sysconf(_SC_OPEN_MAX);
  const char **argv;
  NSUInteger i;
  pid_t pid;
  int status;

  if (count == 0 || [[arguments objectAtIndex: 0] isAbsolutePath] == NO
      || maxfd < 0)
    {
      return NO;
    }

  /* The strings stay valid while the autorelease pool that owns them
   * lives, which outlasts the fork below. */
  argv = (const char **)calloc(count + 1, sizeof(char *));
  if (argv == NULL)
    {
      return NO;
    }
  for (i = 0; i < count; i++)
    {
      argv[i] = [[arguments objectAtIndex: i] UTF8String];
    }

  pid = fork();
  if (pid < 0)
    {
      free(argv);
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
          execv(argv[0], (char * const *)argv);
          _exit(127);
        }
      _exit(grandchild > 0 ? 0 : 1);
    }

  free(argv);
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
