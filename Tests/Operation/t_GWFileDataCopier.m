/* t_GWFileDataCopier.m - window sizing, the progress bound, the order the
 * copy methods are tried in, and windowed writing with injected system
 * calls.  Headless.
 *
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

/* The unit below needs the GNU declarations, which must come before the
 * first system header. */
#if defined(__linux__) && !defined(_GNU_SOURCE)
#define _GNU_SOURCE
#endif
#import <Foundation/Foundation.h>
#import "Testing.h"
#include "../../Operation/GWFileDataCopier.m"

#include <fcntl.h>
#include <pthread.h>
#include <sys/stat.h>

#define MiB (1ULL << 20)

static GWCopySyscalls realCalls;
static int cfrErrno;
static int sendErrno;
static int writeErrno;
static int syncErrno;
static int cfrCalls;
static int sendCalls;
static int readCalls;
static BOOL cfrReturnsZero;
static pthread_mutex_t syncLock = PTHREAD_MUTEX_INITIALIZER;
static unsigned long long syncedEnd;
static unsigned long long syncedTotal;
static BOOL syncContiguous;
static int syncDelayMicros;

static ssize_t
fakeCopyFileRange(int in, off_t *off, int out, size_t len)
{
  cfrCalls++;
  if (cfrReturnsZero)
    {
      return 0;
    }
  if (cfrErrno)
    {
      errno = cfrErrno;
      return -1;
    }
  return realCalls.copyFileRange(in, off, out, len);
}

static ssize_t
fakeSendFile(int out, int in, off_t *off, size_t len)
{
  sendCalls++;
  if (sendErrno)
    {
      errno = sendErrno;
      return -1;
    }
  return realCalls.sendFile(out, in, off, len);
}

static ssize_t
fakeReadAt(int fd, void *buf, size_t len, off_t off)
{
  readCalls++;
  return realCalls.readAt(fd, buf, len, off);
}

static ssize_t
fakeWriteAll(int fd, const void *buf, size_t len)
{
  if (writeErrno)
    {
      errno = writeErrno;
      return -1;
    }
  return realCalls.writeAll(fd, buf, len);
}

static int
fakeSyncRange(int fd, off_t off, off_t len)
{
  if (syncDelayMicros)
    {
      usleep(syncDelayMicros);
    }
  if (syncErrno)
    {
      errno = syncErrno;
      return -1;
    }
  pthread_mutex_lock(&syncLock);
  if ((unsigned long long)off != syncedEnd)
    {
      syncContiguous = NO;
    }
  syncedEnd = (unsigned long long)(off + len);
  syncedTotal += (unsigned long long)len;
  pthread_mutex_unlock(&syncLock);
  return 0;
}

static void
resetFakes(void)
{
  cfrErrno = sendErrno = writeErrno = syncErrno = 0;
  cfrCalls = sendCalls = readCalls = 0;
  cfrReturnsZero = NO;
  syncedEnd = syncedTotal = 0;
  syncContiguous = YES;
  syncDelayMicros = 0;
}

static GWCopySyscalls
fakeCalls(void)
{
  GWCopySyscalls s = realCalls;

  s.copyFileRange = fakeCopyFileRange;
  s.sendFile = fakeSendFile;
  s.readAt = fakeReadAt;
  s.writeAll = fakeWriteAll;
  s.syncRange = fakeSyncRange;
  s.dropCache = NULL;
  return s;
}

static NSString *dir;

static NSString *
makeSource(NSString *name, unsigned long long size)
{
  NSString *p = [dir stringByAppendingPathComponent: name];
  NSMutableData *d = [NSMutableData dataWithLength: (NSUInteger)size];
  unsigned char *b = [d mutableBytes];
  unsigned long long i;

  for (i = 0; i < size; i++)
    {
      b[i] = (unsigned char)((i * 7 + i / 4096) & 0xff);
    }
  [d writeToFile: p atomically: NO];
  return p;
}

/* Copies src to a fresh file with `copier', returns whether it worked. */
static BOOL
runCopy(GWFileDataCopier *copier, NSString *src, NSString *dst, int *err)
{
  int in = open([src fileSystemRepresentation], O_RDONLY);
  int out = open([dst fileSystemRepresentation],
                 O_WRONLY | O_CREAT | O_TRUNC, 0644);
  struct stat st;
  BOOL ok;

  fstat(in, &st);
  ok = [copier copyFromFileDescriptor: in
                     toFileDescriptor: out
                               length: (unsigned long long)st.st_size
                                error: err];
  close(in);
  close(out);
  return ok;
}

static BOOL
sameContents(NSString *a, NSString *b)
{
  return [[NSData dataWithContentsOfFile: a]
           isEqual: [NSData dataWithContentsOfFile: b]];
}

int
main(void)
{
  NSAutoreleasePool *arp = [NSAutoreleasePool new];
  NSFileManager *fm = [NSFileManager defaultManager];

  realCalls = GWCopyDefaultSyscalls();
  dir = [NSTemporaryDirectory() stringByAppendingPathComponent:
          [NSString stringWithFormat: @"t_GWFileDataCopier-%d", getpid()]];
  [fm removeFileAtPath: dir handler: nil];
  [fm createDirectoryAtPath: dir attributes: nil];

  START_SET("window sizing")
    PASS(GWCopyNextWindowSize(0, 0, GW_COPY_WINDOW_CAP) == 1 * MiB,
         "the first window is 1 MiB");
    PASS(GWCopyNextWindowSize(1 * MiB, 100e6, GW_COPY_WINDOW_CAP) == 2 * MiB,
         "a window at most doubles even when the device is much faster");
    PASS(GWCopyNextWindowSize(8 * MiB, 10e6, GW_COPY_WINDOW_CAP) == 2000000,
         "a window is about 200 ms at the speed of the one before");
    PASS(GWCopyNextWindowSize(4 * MiB, 0, GW_COPY_WINDOW_CAP) == 4 * MiB,
         "an unmeasured window keeps the size");
    PASS(GWCopyNextWindowSize(1 * MiB, 1000, GW_COPY_WINDOW_CAP)
         == GW_COPY_MINIMUM_WINDOW,
         "a crawling device still gets the minimum window");
    PASS(GWCopyNextWindowSize(16 * MiB, 1e9, GW_COPY_WINDOW_CAP) == 16 * MiB,
         "windows stop at 16 MiB");
    PASS(GWCopyNextWindowSize(16 * MiB, 1e9, GW_COPY_CIFS_WINDOW_CAP)
         == 32 * MiB, "CIFS windows grow past 16 MiB");
    PASS(GWCopyNextWindowSize(128 * MiB, 1e10, GW_COPY_CIFS_WINDOW_CAP)
         == 128 * MiB, "CIFS windows stop at 128 MiB");
  END_SET("window sizing")

  START_SET("progress bound")
    PASS(GWCopyBoundedProgress(10, 2, 4, 0) == 6,
         "progress runs at most one window ahead of what is written");
    PASS(GWCopyBoundedProgress(5, 2, 4, 0) == 5,
         "progress never exceeds what was copied");
    PASS(GWCopyBoundedProgress(5, 0, 1, 3) == 3,
         "progress never goes backwards");
  END_SET("progress bound")

  START_SET("fallback order")
    PASS(GWCopyMethodAfterError(GWCopyMethodCopyFileRange, EXDEV)
         == GWCopyMethodSendfile, "EXDEV goes on with sendfile");
    PASS(GWCopyMethodAfterError(GWCopyMethodCopyFileRange, ENOSYS)
         == GWCopyMethodSendfile, "ENOSYS goes on with sendfile");
    PASS(GWCopyMethodAfterError(GWCopyMethodCopyFileRange, EOPNOTSUPP)
         == GWCopyMethodSendfile, "EOPNOTSUPP goes on with sendfile");
    PASS(GWCopyMethodAfterError(GWCopyMethodCopyFileRange, EINVAL)
         == GWCopyMethodSendfile, "EINVAL goes on with sendfile");
    PASS(GWCopyMethodAfterError(GWCopyMethodCopyFileRange, EIO)
         == GWCopyMethodReadWrite, "EIO goes straight to read/write");
    PASS(GWCopyMethodAfterError(GWCopyMethodCopyFileRange, ENOSPC)
         == GWCopyMethodReadWrite, "ENOSPC goes straight to read/write");
    PASS(GWCopyMethodAfterError(GWCopyMethodSendfile, EINVAL)
         == GWCopyMethodReadWrite, "a failed sendfile goes on with read/write");
    PASS(GWCopyMethodAfterError(GWCopyMethodReadWrite, EIO)
         == GWCopyMethodFailed, "a failed read/write fails the copy");
  END_SET("fallback order")

  START_SET("injected errors")
    GWCopySyscalls s = fakeCalls();
    GWFileDataCopier *c = [[GWFileDataCopier alloc] initWithSyscalls: &s];
    NSString *src = makeSource(@"src3m", 3 * MiB + 123);
    NSString *dst = [dir stringByAppendingPathComponent: @"dst"];
    int err = 0;

    resetFakes();
    PASS(runCopy(c, src, dst, &err) && sameContents(src, dst)
         && [c lastMethod] == GWCopyMethodCopyFileRange && sendCalls == 0,
         "copy_file_range copies when it works");

    resetFakes();
    cfrErrno = EXDEV;
    PASS(runCopy(c, src, dst, &err) && sameContents(src, dst)
         && [c lastMethod] == GWCopyMethodSendfile && readCalls == 0,
         "EXDEV from copy_file_range: the copy is done by sendfile");

    resetFakes();
    cfrErrno = EXDEV;
    sendErrno = EINVAL;
    PASS(runCopy(c, src, dst, &err) && sameContents(src, dst)
         && [c lastMethod] == GWCopyMethodReadWrite && sendCalls == 1,
         "sendfile failing too: read/write copies");

    resetFakes();
    cfrErrno = EIO;
    PASS(runCopy(c, src, dst, &err) && sameContents(src, dst)
         && [c lastMethod] == GWCopyMethodReadWrite && sendCalls == 0,
         "EIO from copy_file_range skips sendfile");

    resetFakes();
    cfrReturnsZero = YES;
    PASS(runCopy(c, src, dst, &err) && sameContents(src, dst)
         && [c lastMethod] == GWCopyMethodSendfile,
         "nothing from copy_file_range for a non-empty file: next method");

    resetFakes();
    cfrErrno = EXDEV;
    sendErrno = EXDEV;
    writeErrno = ENOSPC;
    err = 0;
    PASS(!runCopy(c, src, dst, &err) && err == ENOSPC,
         "the last method's error is the copy's error");
    RELEASE(c);
  END_SET("injected errors")

  START_SET("windowed writing")
    GWCopySyscalls s = fakeCalls();
    GWFileDataCopier *c = [[GWFileDataCopier alloc] initWithSyscalls: &s];
    NSString *src = makeSource(@"src9m", 9 * MiB + 77);
    NSString *dst = [dir stringByAppendingPathComponent: @"dstw"];
    __block BOOL bounded = YES;
    __block BOOL rising = YES;
    __block unsigned long long last = 0;
    int err = 0;
    NSArray *sizes;

    resetFakes();
    syncDelayMicros = 20000;
    [c setWindowed: YES];
    [c setWindowCap: 1 * MiB];
    [c setProgress: ^(unsigned long long bytes) {
      unsigned long long synced;

      pthread_mutex_lock(&syncLock);
      synced = syncedEnd;
      pthread_mutex_unlock(&syncLock);
      if (bytes > synced + 1 * MiB)
        {
          bounded = NO;
        }
      if (bytes < last)
        {
          rising = NO;
        }
      last = bytes;
    }];
    PASS(runCopy(c, src, dst, &err) && sameContents(src, dst),
         "a windowed copy copies the data");
    PASS(syncedTotal == 9 * MiB + 77 && syncContiguous,
         "every byte is written out by the windows, in order");
    PASS(bounded, "progress stays within one window of what is written");
    PASS(rising && last == 9 * MiB + 77, "progress rises to the file size");
    sizes = [c windowSizes];
    PASS([sizes count] == 10
         && [[sizes objectAtIndex: 0] unsignedLongLongValue] == 1 * MiB,
         "1 MiB windows, the last one short");

    resetFakes();
    /* 1 MiB in 1 ms: a device far faster than doubling allows for. */
    syncDelayMicros = 1000;
    [c setWindowCap: GW_COPY_WINDOW_CAP];
    [c setProgress: nil];
    PASS(runCopy(c, src, dst, &err)
         && [[[c windowSizes] objectAtIndex: 0] unsignedLongLongValue] == 1 * MiB
         && [[[c windowSizes] objectAtIndex: 1] unsignedLongLongValue] == 1 * MiB
         && [[[c windowSizes] objectAtIndex: 2] unsignedLongLongValue] == 2 * MiB,
         "windows start at 1 MiB and double once a fast window was measured (%s)",
         [[[c windowSizes] description] UTF8String]);

    resetFakes();
    syncErrno = EIO;
    err = 0;
    PASS(!runCopy(c, src, dst, &err) && err == EIO,
         "a window that cannot be written fails the copy");

    resetFakes();
    {
      __block int asked = 0;

      [c setShouldStop: ^BOOL (void) {
        return ++asked > 2;
      }];
      err = 0;
      PASS(!runCopy(c, src, dst, &err) && err == ECANCELED,
           "a stop request ends the copy between chunks");
      [c setShouldStop: nil];
    }

    resetFakes();
    {
      NSString *small = makeSource(@"small", 500 * 1024);

      PASS(runCopy(c, small, dst, &err) && sameContents(small, dst)
           && syncedTotal == 0 && [[c windowSizes] count] == 0,
           "a file smaller than a window is left to the final flush");
    }

    resetFakes();
    {
      NSString *medium = makeSource(@"medium", 1 * MiB + 4096);

      PASS(runCopy(c, medium, dst, &err) && syncedTotal == 1 * MiB + 4096,
           "the tail of a file that filled a window is written out too");
    }

    resetFakes();
    [c setWindowed: NO];
    PASS(runCopy(c, src, dst, &err) && syncedTotal == 0,
         "a copy without windows writes nothing out itself");
    RELEASE(c);
  END_SET("windowed writing")

  [fm removeFileAtPath: dir handler: nil];
  [arp release];
  return 0;
}
