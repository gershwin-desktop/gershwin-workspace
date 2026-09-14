/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

#import "GWProcessOwnership.h"

#include <ctype.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#if !defined(__linux__)
#include <sys/param.h>
#include <sys/sysctl.h>
#if defined(__FreeBSD__)
#include <sys/user.h>
#endif
#endif

NSString * const GWLaunchDisplayKey = @"GWLaunchDisplay";

/* Splits "[host]:display[.screen]".  The local socket may be written ":N" or
 * "unix:N"; any other host (including "localhost", which is TCP and commonly
 * an ssh forwarding) is a different server. */
static BOOL GWParseDisplay(NSString *name, NSString **host, long *display, long *screen)
{
  NSRange colon;
  const char *s;
  char *end;

  if ([name length] == 0)
    return NO;
  colon = [name rangeOfString: @":" options: NSBackwardsSearch];
  if (colon.location == NSNotFound)
    return NO;

  *host = [name substringToIndex: colon.location];
  if ([*host isEqualToString: @"unix"])
    *host = @"";

  s = [[name substringFromIndex: NSMaxRange(colon)] UTF8String];
  if (!isdigit((unsigned char)s[0]))
    return NO;
  *display = strtol(s, &end, 10);
  *screen = 0;
  if (*end == '\0')
    return YES;
  if (*end != '.' || !isdigit((unsigned char)end[1]))
    return NO;
  *screen = strtol(end + 1, &end, 10);
  return (*end == '\0');
}

/* Environments are NUL-separated "KEY=value" strings on Linux, FreeBSD and
 * NetBSD. */
static NSString *GWDisplayInEnvironmentBlock(const char *buf, size_t len)
{
  size_t i = 0;

  while (i < len)
    {
      const char *entry = buf + i;
      size_t n = strnlen(entry, len - i);

      if (n > 8 && strncmp(entry, "DISPLAY=", 8) == 0)
        return [[[NSString alloc] initWithBytes: entry + 8
                                         length: n - 8
                                       encoding: NSUTF8StringEncoding] autorelease];
      i += n + 1;
    }
  return nil;
}

#if defined(__linux__)

static BOOL GWProcessEffectiveUID(pid_t pid, uid_t *uid)
{
  char path[64];
  char line[256];
  FILE *f;
  BOOL found = NO;

  snprintf(path, sizeof(path), "/proc/%d/status", (int)pid);
  f = fopen(path, "r");
  if (f == NULL)
    return NO;
  while (fgets(line, sizeof(line), f) != NULL)
    {
      unsigned long ruid, euid;

      /* "Uid:" lists real, effective, saved and filesystem uid. */
      if (sscanf(line, "Uid: %lu %lu", &ruid, &euid) == 2)
        {
          *uid = (uid_t)euid;
          found = YES;
          break;
        }
    }
  fclose(f);
  return found;
}

static NSString *GWProcessDisplay(pid_t pid)
{
  char path[64];
  NSMutableData *env = [NSMutableData data];
  char chunk[4096];
  size_t n;
  FILE *f;

  snprintf(path, sizeof(path), "/proc/%d/environ", (int)pid);
  f = fopen(path, "r");
  if (f == NULL)
    return nil;
  /* procfs reports size 0, so read until EOF. */
  while ((n = fread(chunk, 1, sizeof(chunk), f)) > 0)
    [env appendBytes: chunk length: n];
  fclose(f);
  return GWDisplayInEnvironmentBlock([env bytes], [env length]);
}

#elif defined(__FreeBSD__) || defined(__NetBSD__) || defined(__OpenBSD__)

static BOOL GWProcessEffectiveUID(pid_t pid, uid_t *uid)
{
#if defined(__FreeBSD__)
  int mib[4] = {CTL_KERN, KERN_PROC, KERN_PROC_PID, pid};
  struct kinfo_proc kp;
#elif defined(__OpenBSD__)
  int mib[6] = {CTL_KERN, KERN_PROC, KERN_PROC_PID, pid, sizeof(struct kinfo_proc), 1};
  struct kinfo_proc kp;
#else
  int mib[6] = {CTL_KERN, KERN_PROC2, KERN_PROC_PID, pid, sizeof(struct kinfo_proc2), 1};
  struct kinfo_proc2 kp;
#endif
  size_t len = sizeof(kp);

  /* A pid that does not exist yields success with no record. */
  if (sysctl(mib, sizeof(mib) / sizeof(mib[0]), &kp, &len, NULL, 0) != 0 || len != sizeof(kp))
    return NO;
#if defined(__FreeBSD__)
  *uid = kp.ki_uid;
#else
  *uid = kp.p_uid;
#endif
  return YES;
}

static NSString *GWProcessDisplay(pid_t pid)
{
#if defined(__FreeBSD__)
  int mib[4] = {CTL_KERN, KERN_PROC, KERN_PROC_ENV, pid};
#else
  int mib[4] = {CTL_KERN, KERN_PROC_ARGS, pid, KERN_PROC_ENV};
#endif
  size_t size = 16384;
  NSString *display = nil;
  char *buf = NULL;

  /* The environment can be larger than any fixed guess, and not every BSD
   * reports the needed size up front, so grow until it fits. */
  for (;;)
    {
      size_t len = size;
      char *grown = realloc(buf, size);

      if (grown == NULL)
        break;
      buf = grown;
      if (sysctl(mib, 4, buf, &len, NULL, 0) == 0)
        {
#if defined(__OpenBSD__)
          /* OpenBSD returns a NULL-terminated vector of pointers relocated
           * into buf, followed by the strings. */
          char **vec = (char **)(void *)buf;
          size_t i;

          for (i = 0; vec[i] != NULL; i++)
            {
              if (strncmp(vec[i], "DISPLAY=", 8) == 0)
                {
                  display = [NSString stringWithUTF8String: vec[i] + 8];
                  break;
                }
            }
#else
          display = GWDisplayInEnvironmentBlock(buf, len);
#endif
          break;
        }
      if (errno != ENOMEM || size >= 4 * 1024 * 1024)
        break;
      size *= 2;
    }
  free(buf);
  return display;
}

#else
#error "GWProcessOwnership: no process owner/environment lookup for this OS"
#endif

@implementation GWProcessOwnership

+ (NSString *)currentDisplay
{
  const char *display = getenv("DISPLAY");

  return (display != NULL) ? [NSString stringWithUTF8String: display] : nil;
}

+ (BOOL)display:(NSString *)display isSameAsDisplay:(NSString *)other
{
  NSString *hostA, *hostB;
  long displayA, displayB, screenA, screenB;

  if (!GWParseDisplay(display, &hostA, &displayA, &screenA)
      || !GWParseDisplay(other, &hostB, &displayB, &screenB))
    return NO;
  return [hostA isEqualToString: hostB] && displayA == displayB && screenA == screenB;
}

+ (BOOL)isProcessOwnedByCurrentUser:(pid_t)pid
{
  uid_t uid;

  if (pid <= 0)
    return NO;
  return GWProcessEffectiveUID(pid, &uid) && uid == getuid();
}

+ (NSString *)displayOfProcess:(pid_t)pid
{
  if (pid <= 0)
    return nil;
  return GWProcessDisplay(pid);
}

+ (BOOL)isProcessInCurrentSession:(pid_t)pid
{
  if ([self isProcessOwnedByCurrentUser: pid] == NO)
    return NO;
  return [self display: [self displayOfProcess: pid] isSameAsDisplay: [self currentDisplay]];
}

+ (BOOL)isNotificationInfoInCurrentSession:(NSDictionary *)info
{
  id ident = [info objectForKey: @"NSApplicationProcessIdentifier"];
  NSString *display;

  if (ident != nil)
    return [self isProcessInCurrentSession: (pid_t)[ident intValue]];

  display = [info objectForKey: GWLaunchDisplayKey];
  if (display != nil)
    return [self display: display isSameAsDisplay: [self currentDisplay]];

  return NO;
}

@end
