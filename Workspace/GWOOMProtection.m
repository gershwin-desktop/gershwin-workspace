/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

#import "GWOOMProtection.h"
#import <objc/runtime.h>

#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static BOOL releasingChildren = NO;

BOOL GWOOMReleasingChildren(void)
{
  return releasingChildren;
}

BOOL GWOOMShouldReleaseChildren(int ownScoreAdj)
{
  /* At 0 or above the children inherit nothing they would have to give
   * back, and a raised value is a choice made above us. */
  return ownScoreAdj < 0;
}

#if defined(__linux__)

/* 0 is the kernel's default: a process is judged by its size alone. */
static const char releasedValue[] = "0";

BOOL GWOOMReadOwnScoreAdj(int *scoreAdj)
{
  FILE *fp = fopen("/proc/self/oom_score_adj", "r");
  int value;
  BOOL ok;

  if (fp == NULL)
    {
      return NO;
    }
  ok = (fscanf(fp, "%d", &value) == 1);
  fclose(fp);
  if (ok)
    {
      *scoreAdj = value;
    }
  return ok;
}

static int writeReleasedValue(const char *path)
{
  int fd = open(path, O_WRONLY);
  ssize_t len = (ssize_t)(sizeof(releasedValue) - 1);
  int saved;

  if (fd < 0)
    {
      return -1;
    }
  if (write(fd, releasedValue, (size_t)len) != len)
    {
      saved = errno;
      close(fd);
      errno = saved;
      return -1;
    }
  return close(fd);
}

BOOL GWOOMReleaseProcess(pid_t pid)
{
  char path[64];

  snprintf(path, sizeof(path), "/proc/%d/oom_score_adj", (int)pid);
  if (writeReleasedValue(path) == 0)
    {
      return YES;
    }
  /* A short-lived helper may have exited before we got to it; a process
   * that does not exist any more cannot hold memory either. */
  if (errno == ENOENT || errno == ESRCH)
    {
      return YES;
    }
  /* EACCES: the child runs a set-user-ID program (sudo), whose /proc files
   * belong to root, so it keeps the protection. */
  NSLog(@"Workspace: could not set oom_score_adj of child %d to 0: %s;"
        @" it keeps the desktop's OOM protection.", (int)pid, strerror(errno));
  return NO;
}

int GWOOMReleaseSelf(void)
{
  static const char msg[] = "Workspace: could not set oom_score_adj of a"
    " child to 0; it keeps the desktop's OOM protection.\n";

  if (writeReleasedValue("/proc/self/oom_score_adj") == 0)
    {
      return 0;
    }
  if (write(STDERR_FILENO, msg, sizeof(msg) - 1) < 0)
    {
      /* Nowhere left to report to. */
    }
  return -1;
}

static BOOL (*originalLaunch)(id, SEL, NSError **);

static BOOL releasingLaunch(id task, SEL cmd, NSError **error)
{
  BOOL launched = originalLaunch(task, cmd, error);

  /* posix_spawn returns once the child has run exec, so the value is set
   * on the program itself, before it can have grown. */
  if (launched)
    {
      GWOOMReleaseProcess([task processIdentifier]);
    }
  return launched;
}

void GWOOMReleaseLaunchedTasks(void)
{
  static BOOL installed = NO;
  NSTask *probe;
  Class concrete;
  Method m;

  if (installed)
    {
      return;
    }
  /* +[NSTask alloc] hands out a private concrete subclass that implements
   * the launch; -launch goes through -launchAndReturnError:. */
  probe = [[NSTask alloc] init];
  concrete = [probe class];
  [probe release];
  m = class_getInstanceMethod(concrete, @selector(launchAndReturnError:));
  if (m == NULL)
    {
      NSLog(@"Workspace: %@ has no -launchAndReturnError:; applications it"
            @" starts keep the desktop's OOM protection.",
            NSStringFromClass(concrete));
      return;
    }
  originalLaunch = (BOOL (*)(id, SEL, NSError **))method_getImplementation(m);
  if (class_addMethod(concrete, @selector(launchAndReturnError:),
                      (IMP)releasingLaunch, method_getTypeEncoding(m)) == NO)
    {
      /* The concrete class implements it itself: replace that. */
      method_setImplementation(m, (IMP)releasingLaunch);
    }
  installed = YES;
}

void GWOOMReleaseChildrenIfProtected(void)
{
  int own;

  if (GWOOMReadOwnScoreAdj(&own) == NO)
    {
      NSLog(@"Workspace: cannot read /proc/self/oom_score_adj: %s;"
            @" applications it starts are left as they are.", strerror(errno));
      return;
    }
  if (GWOOMShouldReleaseChildren(own) == NO)
    {
      return;
    }
  GWOOMReleaseLaunchedTasks();
  releasingChildren = YES;
  NSLog(@"Workspace: oom_score_adj is %d; applications and helpers it starts"
        @" get 0.", own);
}

#else

BOOL GWOOMReadOwnScoreAdj(int *scoreAdj)
{
  (void)scoreAdj;
  return NO;
}

BOOL GWOOMReleaseProcess(pid_t pid)
{
  (void)pid;
  return YES;
}

int GWOOMReleaseSelf(void)
{
  return 0;
}

void GWOOMReleaseLaunchedTasks(void)
{
}

void GWOOMReleaseChildrenIfProtected(void)
{
}

#endif
