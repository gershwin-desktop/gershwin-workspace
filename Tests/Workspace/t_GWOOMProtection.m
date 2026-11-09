/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */
/* t_GWOOMProtection.m - Workspace hands the processes it starts back to the
 * kernel's normal OOM choice.  Headless; on Linux it checks the real kernel
 * values of children it starts itself. */
#import <Foundation/Foundation.h>
#import "Testing.h"
#include <stdio.h>
#include <stdlib.h>
#include <sys/wait.h>
#include <unistd.h>
#import "GWOOMProtection.h"

static int scoreAdjOf(pid_t pid)
{
  char path[64];
  char buf[32] = { 0 };
  FILE *fp;

  snprintf(path, sizeof(path), "/proc/%d/oom_score_adj", (int)pid);
  fp = fopen(path, "r");
  if (fp == NULL)
    {
      return -9999;
    }
  if (fgets(buf, sizeof(buf), fp) == NULL)
    {
      buf[0] = '\0';
    }
  fclose(fp);
  return atoi(buf);
}

static BOOL setScoreAdj(pid_t pid, int value)
{
  char path[64];
  FILE *fp;
  BOOL ok;

  snprintf(path, sizeof(path), "/proc/%d/oom_score_adj", (int)pid);
  fp = fopen(path, "w");
  if (fp == NULL)
    {
      return NO;
    }
  ok = fprintf(fp, "%d", value) > 0;
  return (fclose(fp) == 0) && ok;
}

static NSTask *startSleeper(void)
{
  NSTask *task = [[[NSTask alloc] init] autorelease];

  [task setLaunchPath: @"/bin/sleep"];
  [task setArguments: [NSArray arrayWithObject: @"5"]];
  [task launch];
  return task;
}

int main(void)
{
  NSAutoreleasePool *arp = [NSAutoreleasePool new];

  START_SET("only a protected Workspace releases its children")
    PASS(GWOOMShouldReleaseChildren(-900), "a protected Workspace releases them");
    PASS(GWOOMShouldReleaseChildren(-1), "any lowered value releases them");
    PASS(!GWOOMShouldReleaseChildren(0), "an unprotected Workspace leaves them");
    PASS(!GWOOMShouldReleaseChildren(500), "a raised value is inherited unchanged");
  END_SET("only a protected Workspace releases its children")

#if defined(__linux__)
  START_SET("the real kernel values")
    int own = 12345;
    NSTask *sleeper;
    NSTask *hooked;
    pid_t pid;
    int status = 0;

    PASS(GWOOMReadOwnScoreAdj(&own) && own == scoreAdjOf(getpid()),
      "reads its own value");

    /* Raising needs no privilege; the children inherit 300 from here on,
     * which stands in for the session's protection (lowering it would
     * need root). */
    NEED(PASS(setScoreAdj(getpid(), 300), "the test process raises itself"));

    sleeper = startSleeper();
    NEED(PASS(scoreAdjOf([sleeper processIdentifier]) == 300,
      "a child inherits the parent's value"));
    PASS(GWOOMReleaseProcess([sleeper processIdentifier]),
      "releasing a running child succeeds");
    PASS(scoreAdjOf([sleeper processIdentifier]) == 0,
      "the released child is at 0");
    [sleeper terminate];
    [sleeper waitUntilExit];

    pid = fork();
    if (pid == 0)
      {
        _exit(0);
      }
    waitpid(pid, &status, 0);
    PASS(GWOOMReleaseProcess(pid), "a process that is gone needs nothing");

    pid = fork();
    if (pid == 0)
      {
        _exit(GWOOMReleaseSelf() == 0 ? scoreAdjOf(getpid()) : 99);
      }
    waitpid(pid, &status, 0);
    PASS(WIFEXITED(status) && WEXITSTATUS(status) == 0,
      "a forked child releases itself");

    GWOOMReleaseLaunchedTasks();
    hooked = startSleeper();
    PASS(scoreAdjOf([hooked processIdentifier]) == 0,
      "every NSTask launched after the hook is released");
    PASS(scoreAdjOf(getpid()) == 300, "the launcher keeps its own value");
    [hooked terminate];
    [hooked waitUntilExit];
  END_SET("the real kernel values")
#endif

  [arp release];
  return 0;
}
