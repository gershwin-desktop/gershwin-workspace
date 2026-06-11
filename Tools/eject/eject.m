/*
 *  eject.m: CLI wrapper around the system eject command.
 *
 *  Posts a distributed notification to the Workspace app so the
 *  "Volume Removed Unexpectedly" dialog is suppressed, then
 *  executes the real eject(1) with the same arguments.
 *
 *  This program is free software; you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License as published by
 *  the Free Software Foundation; either version 2 of the License, or
 *  (at your option) any later version.
 *
 *  This program is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU General Public License for more details.
 *
 *  You should have received a copy of the GNU General Public License
 *  along with this program; if not, write to the Free Software
 *  Foundation, Inc., 31 Milk Street #960789 Boston, MA 02196 USA.
 */

#import <Foundation/Foundation.h>
#include <string.h>
#include <stdlib.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>

/* Notification name posted to notify Workspace of a user-initiated unmount. */
static NSString *GWWorkspaceWillUnmountNotification = @"GWWorkspaceWillUnmountNotification";
static NSString *GWUnmountPathKey = @"GWUnmountPath";

/* Resolve our own executable's directory so we can skip it
 * in the PATH search for the real command.  Portable across
 * Linux and BSD. */
static NSString *resolveOwnPath(const char *argv0, NSArray *pathDirs)
{
  NSString *selfPath = nil;
  NSFileManager *fm = [NSFileManager defaultManager];

  if (argv0[0] == '/') {
    selfPath = [NSString stringWithCString: argv0 encoding: NSUTF8StringEncoding];
  } else if (strchr(argv0, '/') != NULL) {
    char *resolved = realpath(argv0, NULL);
    if (resolved) {
      selfPath = [NSString stringWithCString: resolved encoding: NSUTF8StringEncoding];
      free(resolved);
    }
  }

  if (!selfPath) {
    NSString *name = [NSString stringWithCString: argv0 encoding: NSUTF8StringEncoding];
    for (NSString *dir in pathDirs) {
      NSString *candidate = [dir stringByAppendingPathComponent: name];
      if ([fm isExecutableFileAtPath: candidate]) {
        selfPath = candidate;
        break;
      }
    }
  }

  if (!selfPath) return nil;
  return selfPath;
}

/* Find the real system command on PATH.  Skips any candidate that is
 * the SAME FILE as ourselves (same device + inode), preventing infinite
 * recursion when multiple copies of this wrapper are on PATH. */
static NSString *findRealCommand(NSString *cmdName, NSArray *pathDirs,
                                 struct stat *selfStat)
{
  NSFileManager *fm = [NSFileManager defaultManager];

  for (NSString *dir in pathDirs) {
    NSString *candidate = [dir stringByAppendingPathComponent: cmdName];
    if (![fm isExecutableFileAtPath: candidate]) continue;

    if (selfStat) {
      struct stat candStat;
      if (stat([candidate fileSystemRepresentation], &candStat) == 0) {
        if (candStat.st_dev == selfStat->st_dev
            && candStat.st_ino == selfStat->st_ino) {
          continue;
        }
      }
    }

    return candidate;
  }

  return nil;
}

int main(int argc, char **argv, char **env)
{
  NSAutoreleasePool *pool = [NSAutoreleasePool new];
  NSFileManager *fm = [NSFileManager defaultManager];

  /* Parse PATH */
  const char *pathCStr = getenv("PATH");
  NSString *pathStr = (pathCStr != NULL)
    ? [NSString stringWithCString: pathCStr encoding: NSUTF8StringEncoding]
    : @"/bin:/usr/bin:/usr/local/bin";
  NSArray *pathDirs = [pathStr componentsSeparatedByString: @":"];

  /* Resolve our own path and stat ourselves so we can detect copies. */
  NSString *selfPath = resolveOwnPath(argv[0], pathDirs);
  struct stat selfStat;
  BOOL haveSelfStat = (selfPath
                       && stat([selfPath fileSystemRepresentation], &selfStat) == 0);

  /* Find the real eject on PATH, skipping copies of ourselves. */
  NSString *realEject = findRealCommand(@"eject", pathDirs,
                                         haveSelfStat ? &selfStat : NULL);

  if (!realEject) {
    NSArray *fallbacks = @[@"/bin/eject", @"/usr/bin/eject",
                           @"/sbin/eject", @"/usr/sbin/eject",
                           @"/usr/local/bin/eject"];
    for (NSString *p in fallbacks) {
      if ([fm isExecutableFileAtPath: p]) {
        realEject = p;
        break;
      }
    }
  }

  if (!realEject) {
    fprintf(stderr, "eject: command not found\n");
    [pool release];
    return 127;
  }

  /* Extract the target path from argv (first non-option argument) */
  NSString *target = nil;
  for (int i = 1; i < argc; i++) {
    if (argv[i][0] != '-') {
      target = [NSString stringWithCString: argv[i]
                                   encoding: NSUTF8StringEncoding];
      break;
    }
  }

  /* Write a flag file BEFORE ejecting so Workspace can discover this unmount. */
  if (target) {
    const char *flagPath = "/tmp/.gw-umount-flag";
    FILE *f = fopen(flagPath, "w");
    if (f) {
      fprintf(f, "%s\n", [target UTF8String]);
      fclose(f);
    }
  }

  /* Build argv for the real eject */
  const char **realArgv = malloc((argc + 1) * sizeof(char *));
  realArgv[0] = [realEject fileSystemRepresentation];
  for (int i = 1; i < argc; i++) {
    realArgv[i] = argv[i];
  }
  realArgv[argc] = NULL;

  /* Fork so we can do post-eject cleanup (remove empty mountpoint). */
  pid_t pid = fork();
  if (pid == 0) {
    execve([realEject fileSystemRepresentation],
           (char *const *)realArgv, env);
    _exit(127);
  } else if (pid > 0) {
    int status;
    waitpid(pid, &status, 0);
    int exitCode = WIFEXITED(status) ? WEXITSTATUS(status) : 1;

    if (exitCode == 0 && target) {
      BOOL isDir = NO;
      if ([fm fileExistsAtPath: target isDirectory: &isDir] && isDir) {
        NSArray *contents = [fm contentsOfDirectoryAtPath: target error: NULL];
        if (contents && [contents count] == 0) {
          rmdir([target fileSystemRepresentation]);
        }
      }
    }

    free(realArgv);
    [pool release];
    return exitCode;
  } else {
    fprintf(stderr, "eject: fork failed: %s\n", strerror(errno));
    free(realArgv);
    [pool release];
    return 1;
  }
}
