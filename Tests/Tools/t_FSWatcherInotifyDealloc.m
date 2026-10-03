/* t_FSWatcherInotifyDealloc.m - ObjectTesting coverage for -[FSWatcher dealloc]
 * releasing a live, populated instance without crashing.
 *
 * Linux-only: inotify does not exist on the BSDs (fswatcher-kqueue.m covers
 * those). On any other platform this tool just records a stub pass so the
 * suite stays green there.
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */
#import <Foundation/Foundation.h>
#import "Testing.h"

#ifdef __linux__

#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>

/* fswatcher-inotify.m is the daemon's own translation unit and defines its
 * own int main(argc, argv) (the fork/exec-as-daemon entry point); rename it
 * out of the way so it does not collide with this test tool's own main(). */
#define main fswatcher_inotify_unused_main
#include "../../Tools/fswatcher/fswatcher-inotify.m"
#undef main

#include "FSWatcherInotifyTesting.h"

/* A heap corruption in -dealloc aborts the process (glibc "free(): invalid
 * pointer"), which no PASS macro can catch. The release therefore happens
 * in a forked child; the parent asserts on how the child ended. */
static int
releaseInChildAndReturnStatus(FSWatcher *fsw)
{
  int status = -1;
  pid_t pid = fork();

  if (pid == 0)
    {
      RELEASE(fsw);
      _exit(0);
    }
  if (pid < 0 || waitpid(pid, &status, 0) != pid)
    {
      return -1;
    }
  return status;
}

int
main(void)
{
  NSAutoreleasePool *arp = [NSAutoreleasePool new];
  NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:
    [NSString stringWithFormat: @"t_fswinotify_dealloc_%d", (int)getpid()]];
  FSWatcher *fsw = [FSWatcher alloc];
  Watcher *watcher;
  int status;

  [fsw test_setUpForTesting];

  /* Populate both map tables, as the daemon does for every watched path:
   * the bug only shows with real entries because NSFreeMapTable must
   * release them while NSZoneFree just frees the table pointer. */
  watcher = [[Watcher alloc] initWithWatchedPath: path
                                  watchDescriptor: 1
                                        fswatcher: fsw];
  [fsw test_installWatcher: watcher forPath: path wd: 1];
  RELEASE(watcher);

  status = releaseInChildAndReturnStatus(fsw);
  PASS(status != -1, "the child that releases the FSWatcher could be forked and waited for");
  PASS(WIFEXITED(status) && WEXITSTATUS(status) == 0,
       "releasing a populated FSWatcher deallocates cleanly instead of aborting");

  RELEASE(arp);
  return 0;
}

#else /* !__linux__ */

int
main(void)
{
  NSAutoreleasePool *arp = [NSAutoreleasePool new];

  PASS(1, "fswatcher-inotify.m is Linux-only (fswatcher-kqueue.m covers the BSDs)");

  RELEASE(arp);
  return 0;
}

#endif
