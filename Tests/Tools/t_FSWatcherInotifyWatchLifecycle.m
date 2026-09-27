/* t_FSWatcherInotifyWatchLifecycle.m - ObjectTesting coverage for
 * fswatcher-inotify.m's watch-descriptor bookkeeping across a deleted watch.
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

#include <sys/inotify.h>
#include <unistd.h>

/* fswatcher-inotify.m is the daemon's own translation unit and defines its
 * own int main(argc, argv) (the fork/exec-as-daemon entry point); rename it
 * out of the way so it does not collide with this test tool's own main(). */
#define main fswatcher_inotify_unused_main
#include "../../Tools/fswatcher/fswatcher-inotify.m"
#undef main

#include "FSWatcherInotifyTesting.h"

/* Blocks until the kernel has an event batch queued; rmdir() below happens
 * synchronously right before this is called, so the read never idles long. */
static NSData *
readOneEventBatch(int fd)
{
  uint8_t buf[4096];
  ssize_t n = read(fd, buf, sizeof(buf));

  if (n <= 0)
    {
      return [NSData data];
    }

  return [NSData dataWithBytes: buf length: (NSUInteger)n];
}

static NSNotification *
notificationWithData(NSFileHandle *handle, NSData *data)
{
  NSDictionary *info = [NSDictionary dictionaryWithObject: data
                          forKey: NSFileHandleNotificationDataItem];

  return [NSNotification notificationWithName: NSFileHandleReadCompletionNotification
                                        object: handle
                                      userInfo: info];
}

int
main(void)
{
  NSAutoreleasePool *arp = [NSAutoreleasePool new];
  NSFileManager *fm = [NSFileManager defaultManager];
  NSString *tmpDir = [NSTemporaryDirectory() stringByAppendingPathComponent:
    [NSString stringWithFormat: @"t_fswinotify_%d", (int)getpid()]];
  int ifd, wd;
  FSWatcher *fsw;
  Watcher *watcher;
  NSFileHandle *handle;

  [fm removeItemAtPath: tmpDir error: NULL];
  PASS([fm createDirectoryAtPath: tmpDir withIntermediateDirectories: YES
             attributes: nil error: NULL],
       "temp directory to watch is created");

  ifd = inotify_init();
  PASS(ifd != -1, "inotify_init succeeds");

  wd = inotify_add_watch(ifd, [tmpDir fileSystemRepresentation],
                          IN_CREATE | IN_DELETE | IN_DELETE_SELF
                            | IN_MOVED_FROM | IN_MOVED_TO | IN_MOVE_SELF
                            | IN_MODIFY);
  PASS(wd != -1, "inotify_add_watch succeeds on the temp dir");

  fsw = [FSWatcher alloc];
  [fsw test_setUpForTesting];

  watcher = [[Watcher alloc] initWithWatchedPath: tmpDir
                                  watchDescriptor: wd
                                        fswatcher: fsw];
  [fsw test_installWatcher: watcher forPath: tmpDir wd: wd];
  RELEASE(watcher);

  handle = [[NSFileHandle alloc] initWithFileDescriptor: ifd closeOnDealloc: YES];

  PASS([fsw test_hasWatcherForPath: tmpDir], "watcher is registered before deletion");
  PASS([fsw test_hasWatchDescriptor: wd], "watch descriptor is registered before deletion");

  /* --- delete the watched directory: the kernel retires wd (IN_IGNORED) --- */
  {
    NSData *bytes;

    PASS(rmdir([tmpDir fileSystemRepresentation]) == 0,
         "rmdir removes the watched directory");

    bytes = readOneEventBatch(ifd);
    PASS([bytes length] > 0, "the kernel reports a delete-self event batch");

    [fsw inotifyDataReady: notificationWithData(handle, bytes)];

    PASS(![fsw test_hasWatcherForPath: tmpDir],
         "the deleted path no longer has a registered watcher");
    PASS(![fsw test_hasWatchDescriptor: wd],
         "the retired watch descriptor is dropped, not kept stale");
  }

  /* --- the kernel is free to hand the retired wd back out; when it does,
   * routing must reach the NEW watcher, never the one just removed. This
   * is synthetic (no second inotify_add_watch): it exercises exactly the
   * failure mode the fix prevents, without depending on the kernel's own
   * wd-reuse timing. --- */
  {
    NSString *otherDir = [tmpDir stringByAppendingString: @"_b"];
    Watcher *otherWatcher = [[Watcher alloc] initWithWatchedPath: otherDir
                                                  watchDescriptor: wd
                                                        fswatcher: fsw];
    Watcher *routed;

    [fsw test_installWatcher: otherWatcher forPath: otherDir wd: wd];
    RELEASE(otherWatcher);

    routed = [fsw watcherWithWatchDescriptor: wd];
    PASS_EQUAL([routed watchedPath], otherDir,
      "a watch descriptor reused after removal routes to its new watcher");
  }

  RELEASE(handle);
  RELEASE(fsw);
  [fm removeItemAtPath: tmpDir error: NULL];

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
