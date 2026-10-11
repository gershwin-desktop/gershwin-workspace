/* t_FSWatcherInotifyAttrib.m - ObjectTesting coverage for fswatcher-inotify.m
 * reporting attribute-only changes (an xattr write, a chmod) as a modification
 * of the file, because a Finder label or tag is stored in an xattr and changes
 * neither the file's content nor its modification date.
 *
 * The events are the kernel's own: the watches are made with the masks the
 * daemon uses and the bytes read from the inotify descriptor are handed to
 * the handler.
 *
 * Linux-only; on other platforms this tool records a stub pass
 * (fswatcher-kqueue.m watches NOTE_ATTRIB there).
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */
#import <Foundation/Foundation.h>
#import "Testing.h"

#ifdef __linux__

#include <sys/inotify.h>
#include <sys/xattr.h>
#include <sys/stat.h>
#include <unistd.h>
#include <fcntl.h>
#include <poll.h>
#include <objc/runtime.h>

#define main fswatcher_inotify_unused_main
#include "../../Tools/fswatcher/fswatcher-inotify.m"
#undef main

#include "FSWatcherInotifyTesting.h"

static NSMutableArray *clientEvents;
static NSMutableArray *globalEvents;

static void
recordClient(id self, SEL _cmd, NSDictionary *info)
{
  [clientEvents addObject: info];
}

static void
recordGlobal(id self, SEL _cmd, NSDictionary *info)
{
  [globalEvents addObject: info];
}

@interface FSWatcher (AttribTesting)
- (void)test_includePath:(NSString *)path;
@end

@implementation FSWatcher (AttribTesting)
- (void)test_includePath:(NSString *)path
{
  insertComponentsOfPath(path, includePathsTree);
}
@end

/* Everything the kernel has queued so far. */
static NSData *
queuedEvents(int fd)
{
  NSMutableData *all = [NSMutableData data];
  struct pollfd p = { fd, POLLIN, 0 };

  while (poll(&p, 1, 200) > 0)
    {
      uint8_t buf[4096];
      ssize_t n = read(fd, buf, sizeof(buf));

      if (n <= 0)
        {
          break;
        }
      [all appendBytes: buf length: (NSUInteger)n];
    }
  return all;
}

static void
deliver(FSWatcher *fsw, NSFileHandle *handle, NSData *bytes)
{
  NSDictionary *info = [NSDictionary dictionaryWithObject: bytes
                          forKey: NSFileHandleNotificationDataItem];

  [fsw inotifyDataReady: [NSNotification
    notificationWithName: NSFileHandleReadCompletionNotification
                  object: handle userInfo: info]];
}

static BOOL
hasModified(NSArray *events, NSString *path)
{
  NSDictionary *d;

  for (d in events)
    {
      if ([[d objectForKey: @"path"] isEqual: path]
          && [[d objectForKey: @"event"] isEqual: GWWatchedFileModified])
        {
          return YES;
        }
    }
  return NO;
}

int
main(void)
{
  NSAutoreleasePool *arp = [NSAutoreleasePool new];
  NSFileManager *fm = [NSFileManager defaultManager];
  NSString *dir = [NSTemporaryDirectory() stringByAppendingPathComponent:
    [NSString stringWithFormat: @"t_fswattrib_%d", (int)getpid()]];
  NSString *file = [dir stringByAppendingPathComponent: @"labelled.txt"];
  const char *cfile;
  int ifd, wd;
  FSWatcher *fsw;
  Watcher *watcher;
  NSFileHandle *handle;
  NSData *bytes;

  clientEvents = [NSMutableArray new];
  globalEvents = [NSMutableArray new];
  class_replaceMethod([FSWatcher class], @selector(notifyClients:),
                      (IMP)recordClient, "v@:@");
  class_replaceMethod([FSWatcher class], @selector(notifyGlobalWatchingClients:),
                      (IMP)recordGlobal, "v@:@");

  [fm removeItemAtPath: dir error: NULL];
  PASS([fm createDirectoryAtPath: dir withIntermediateDirectories: YES
             attributes: nil error: NULL], "temp directory");
  PASS([fm createFileAtPath: file contents: [NSData data] attributes: nil],
       "temp file");
  cfile = [file fileSystemRepresentation];

  ifd = inotify_init();
  fsw = [FSWatcher alloc];
  [fsw test_setUpForTesting];
  [fsw test_includePath: dir];
  handle = [[NSFileHandle alloc] initWithFileDescriptor: ifd
                                         closeOnDealloc: YES];

  /* --- a watch on the file itself, as a Workspace viewer makes --- */
  wd = inotify_add_watch(ifd, cfile, GW_INOTIFY_FILEMASK);
  PASS(wd != -1, "file watch");
  watcher = [[Watcher alloc] initWithWatchedPath: file watchDescriptor: wd
                                       fswatcher: fsw];
  [fsw test_installWatcher: watcher forPath: file wd: wd];
  RELEASE(watcher);

  if (setxattr(cfile, "user.t_fswattrib", "x", 1, 0) != 0)
    {
      printf("note: no user xattrs here, using chmod as the attribute change\n");
      chmod(cfile, 0600);
    }
  bytes = queuedEvents(ifd);
  deliver(fsw, handle, bytes);
  PASS(hasModified(clientEvents, file),
       "an attribute-only change of a watched file is reported as modified");

  /* The viewer itself rewrites the same attribute: it is one event per
   * write, no more, so a viewer that reloads on it cannot feed itself. */
  [clientEvents removeAllObjects];
  setxattr(cfile, "user.t_fswattrib", "y", 1, 0);
  deliver(fsw, handle, queuedEvents(ifd));
  PASS([clientEvents count] == 1,
       "one write gives one event, not a cascade");

  /* Reading and listing the file must stay silent. */
  [clientEvents removeAllObjects];
  (void)[NSData dataWithContentsOfFile: file];
  (void)[fm fileAttributesAtPath: file traverseLink: NO];
  deliver(fsw, handle, queuedEvents(ifd));
  PASS([clientEvents count] == 0, "reading the file raises no event");

  /* --- the global watch (mdextractor) on the folder --- */
  inotify_rm_watch(ifd, wd);
  [globalEvents removeAllObjects];
  wd = inotify_add_watch(ifd, [dir fileSystemRepresentation],
                         GW_INOTIFY_DIRMASK);
  PASS(wd != -1, "folder watch");
  watcher = [[Watcher alloc] initWithWatchedPath: dir watchDescriptor: wd
                                       fswatcher: fsw];
  [fsw test_installWatcher: watcher forPath: dir wd: wd];
  RELEASE(watcher);
  queuedEvents(ifd);

  if (setxattr(cfile, "user.t_fswattrib", "z", 1, 0) != 0)
    {
      chmod(cfile, 0640);
    }
  deliver(fsw, handle, queuedEvents(ifd));
  PASS(hasModified(globalEvents, file),
       "the global watch sees an attribute change of a file in the folder");

  [globalEvents removeAllObjects];
  (void)[NSData dataWithContentsOfFile: file];
  deliver(fsw, handle, queuedEvents(ifd));
  PASS([globalEvents count] == 0, "reading raises no global event");

  RELEASE(handle);
  RELEASE(fsw);
  [fm removeItemAtPath: dir error: NULL];
  RELEASE(arp);
  return 0;
}

#else

int
main(void)
{
  NSAutoreleasePool *arp = [NSAutoreleasePool new];

  PASS(1, "fswatcher-inotify.m is Linux-only (fswatcher-kqueue.m watches NOTE_ATTRIB)");
  RELEASE(arp);
  return 0;
}

#endif
