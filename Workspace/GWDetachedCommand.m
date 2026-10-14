/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

#import "GWDetachedCommand.h"
#import "GWScaleFactor.h"

#include <errno.h>
#include <fcntl.h>
#include <stdlib.h>
#ifndef _WIN32
#include <sys/wait.h>
#include <unistd.h>
#endif

@implementation GWDetachedCommand

+ (BOOL)launchShellCommand:(NSString *)command
{
#ifdef _WIN32
  const char *shell = getenv("COMSPEC");

  if (shell == NULL || *shell == '\0')
    {
      shell = "cmd.exe";
    }
  return [self launchArguments: [NSArray arrayWithObjects:
    [NSString stringWithUTF8String: shell], @"/c", command, nil]];
#else
  const char *shell = getenv("SHELL");

  if (shell == NULL || *shell == '\0')
    {
      shell = "/bin/sh";
    }
  return [self launchArguments: [NSArray arrayWithObjects:
    [NSString stringWithUTF8String: shell], @"-c", command, nil]];
#endif
}

+ (BOOL)launchArguments:(NSArray *)arguments
{
#ifdef _WIN32
  /* No fork() on Windows: NSTask starts the command detached from our
   * standard streams and does not wait for it. */
  NSUInteger count = [arguments count];
  NSFileHandle *null = [NSFileHandle fileHandleWithNullDevice];
  NSTask *task;

  if (count == 0)
    {
      return NO;
    }
  task = [[[NSTask alloc] init] autorelease];
  [task setLaunchPath: [arguments objectAtIndex: 0]];
  [task setArguments: [arguments subarrayWithRange: NSMakeRange(1, count - 1)]];
  [task setStandardInput: null];
  [task setStandardOutput: null];
  [task setStandardError: null];
  /* A Qt application learns the desktop's scale only from QT_SCALE_FACTOR. */
  [task setEnvironment: GWEnvironmentWithScaleFactor(nil)];
  @try
    {
      [task launch];
    }
  @catch (NSException *e)
    {
      NSLog(@"GWDetachedCommand: cannot launch %@: %@",
            [arguments objectAtIndex: 0], [e reason]);
      return NO;
    }
  return YES;
#else
  /* Workspace is multithreaded: after fork() only async-signal-safe calls
   * are allowed, so everything the child needs is prepared here. */
  NSUInteger count = [arguments count];
  long maxfd = sysconf(_SC_OPEN_MAX);
  NSDictionary *environment;
  NSEnumerator *keys;
  NSString *key;
  const char **argv;
  const char **envp;
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

  /* Our own environment plus QT_SCALE_FACTOR, which a Qt application
   * needs to come up at the desktop's scale; built before the fork for the
   * same reason as argv. */
  environment = GWEnvironmentWithScaleFactor(nil);
  envp = (const char **)calloc([environment count] + 1, sizeof(char *));
  if (envp == NULL)
    {
      free(argv);
      return NO;
    }
  keys = [environment keyEnumerator];
  i = 0;
  while ((key = [keys nextObject]) != nil)
    {
      envp[i++] = [[NSString stringWithFormat: @"%@=%@", key,
                     [environment objectForKey: key]] UTF8String];
    }

  pid = fork();
  if (pid < 0)
    {
      free(argv);
      free(envp);
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
          execve(argv[0], (char * const *)argv, (char * const *)envp);
          _exit(127);
        }
      _exit(grandchild > 0 ? 0 : 1);
    }

  free(argv);
  free(envp);
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
#endif
}

@end
