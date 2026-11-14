/* GWFileDataCopier.m
 *
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

#if defined(__linux__) && !defined(_GNU_SOURCE)
#define _GNU_SOURCE
#endif

#import "GWFileDataCopier.h"
#import <GNUstepBase/GNUstep.h>

#include <errno.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#if !defined(_WIN32)
#include <pthread.h>
#include <time.h>
#endif
#if defined(__linux__)
#include <sys/sendfile.h>
#endif
#if defined(__FreeBSD__)
#include <sys/param.h>
#endif

/* Each system call moves at most this much, so that a stop request and the
 * progress are noticed often enough even on a fast local disk. */
#define GW_COPY_CHUNK        (1ULL << 20)
#define GW_COPY_LOCAL_CHUNK  (8ULL << 20)

unsigned long long
GWCopyNextWindowSize(unsigned long long previous, double bytesPerSecond,
                     unsigned long long cap)
{
  unsigned long long size;

  if (previous == 0)
    {
      size = GW_COPY_INITIAL_WINDOW;
    }
  else if (bytesPerSecond <= 0.0)
    {
      /* Nothing measured yet: keep the size rather than guess. */
      size = previous;
    }
  else
    {
      double want = bytesPerSecond * GW_COPY_WINDOW_SECONDS;

      /* Growing slowly keeps a burst of cache-speed writes at the start of
       * a device from inflating the window far beyond what it sustains. */
      if (want > (double)previous * 2.0)
        {
          size = previous * 2;
        }
      else
        {
          size = (unsigned long long)want;
        }
    }
  if (size < GW_COPY_MINIMUM_WINDOW)
    {
      size = GW_COPY_MINIMUM_WINDOW;
    }
  if (cap > 0 && size > cap)
    {
      size = cap;
    }
  return size;
}

unsigned long long
GWCopyBoundedProgress(unsigned long long copied, unsigned long long written,
                      unsigned long long window, unsigned long long shown)
{
  unsigned long long limit = written + window;
  unsigned long long value = (copied < limit) ? copied : limit;

  return (value > shown) ? value : shown;
}

GWCopyMethod
GWCopyMethodAfterError(GWCopyMethod method, int err)
{
  switch (method)
    {
      case GWCopyMethodCopyFileRange:
        /* These say the kernel cannot copy between these two files at all
         * (another filesystem, an old kernel, a filesystem without
         * support); sendfile() can still move the data inside the kernel.
         * Anything else (EIO, ENOSPC) is worth one more try the plain way,
         * which reports the error itself if it persists. */
        if (err == EXDEV || err == ENOSYS || err == EINVAL
#ifdef EOPNOTSUPP
            || err == EOPNOTSUPP
#endif
#if defined(ENOTSUP) && (!defined(EOPNOTSUPP) || ENOTSUP != EOPNOTSUPP)
            || err == ENOTSUP
#endif
            )
          {
            return GWCopyMethodSendfile;
          }
        return GWCopyMethodReadWrite;
      case GWCopyMethodSendfile:
        return GWCopyMethodReadWrite;
      default:
        return GWCopyMethodFailed;
    }
}

#if !defined(_WIN32)

#if defined(__linux__) \
  || (defined(__FreeBSD__) && defined(__FreeBSD_version) \
      && __FreeBSD_version >= 1300000)
#define GW_HAVE_COPY_FILE_RANGE 1
static ssize_t
sysCopyFileRange(int in, off_t *inOffset, int out, size_t length)
{
  return copy_file_range(in, inOffset, out, NULL, length, 0);
}
#endif

#if defined(__linux__)
/* Only Linux sends from one file to another; the BSDs only to sockets. */
static ssize_t
sysSendFile(int out, int in, off_t *inOffset, size_t length)
{
  return sendfile(out, in, inOffset, length);
}
#endif

static ssize_t
sysReadAt(int fd, void *buffer, size_t length, off_t offset)
{
  ssize_t r;

  do
    {
      r = pread(fd, buffer, length, offset);
    }
  while (r < 0 && errno == EINTR);
  return r;
}

static ssize_t
sysWriteAll(int fd, const void *buffer, size_t length)
{
  size_t done = 0;

  while (done < length)
    {
      ssize_t w = write(fd, (const char *)buffer + done, length - done);

      if (w < 0)
        {
          if (errno == EINTR)
            {
              continue;
            }
          return -1;
        }
      if (w == 0)
        {
          errno = EIO;
          return -1;
        }
      done += (size_t)w;
    }
  return (ssize_t)done;
}

static int
sysSyncRange(int fd, off_t offset, off_t length)
{
#if defined(__linux__)
  return sync_file_range(fd, offset, length,
                         SYNC_FILE_RANGE_WAIT_BEFORE
                         | SYNC_FILE_RANGE_WRITE
                         | SYNC_FILE_RANGE_WAIT_AFTER);
#elif defined(__OpenBSD__)
  /* No range sync on the BSDs; the whole file's dirty data is the nearest
   * thing, and the windows written before are clean already. */
  return fsync(fd);
#else
  return fdatasync(fd);
#endif
}

static void
sysDropCache(int fd, off_t offset, off_t length)
{
#ifdef POSIX_FADV_DONTNEED
  /* A copy of many gigabytes would otherwise push everything else the
   * user has open out of memory, for data nobody reads back soon. */
  posix_fadvise(fd, offset, length, POSIX_FADV_DONTNEED);
#endif
}

GWCopySyscalls
GWCopyDefaultSyscalls(void)
{
  GWCopySyscalls s;

  memset(&s, 0, sizeof(s));
#ifdef GW_HAVE_COPY_FILE_RANGE
  s.copyFileRange = sysCopyFileRange;
#endif
#if defined(__linux__)
  s.sendFile = sysSendFile;
#endif
  s.readAt = sysReadAt;
  s.writeAll = sysWriteAll;
  s.syncRange = sysSyncRange;
  s.dropCache = sysDropCache;
  return s;
}

/* The state shared with the thread that writes the windows out.  The copy
 * hands over one window at a time and waits only when the window before
 * is still being written. */
typedef struct
{
  pthread_mutex_t lock;
  pthread_cond_t cond;
  const GWCopySyscalls *sys;
  int fd;
  BOOL pending;
  BOOL busy;
  BOOL quit;
  off_t offset;
  off_t length;
  unsigned long long written;
  double bytesPerSecond;
  int error;
} GWWriteback;

/* Monotonic, so that a clock change in the middle of a window cannot make
 * up a speed. */
static double
nowSeconds(void)
{
  struct timespec ts;

  clock_gettime(CLOCK_MONOTONIC, &ts);
  return ts.tv_sec + ts.tv_nsec / 1e9;
}

static void *
writebackMain(void *arg)
{
  GWWriteback *wb = arg;

  pthread_mutex_lock(&wb->lock);
  while (1)
    {
      off_t offset;
      off_t length;
      double start;
      double elapsed;
      int r;

      while (wb->pending == NO && wb->quit == NO)
        {
          pthread_cond_wait(&wb->cond, &wb->lock);
        }
      if (wb->pending == NO)
        {
          break;
        }
      offset = wb->offset;
      length = wb->length;
      wb->busy = YES;
      wb->pending = NO;
      pthread_mutex_unlock(&wb->lock);

      start = nowSeconds();
      r = wb->sys->syncRange(wb->fd, offset, length);
      elapsed = nowSeconds() - start;
      if (r == 0 && wb->sys->dropCache != NULL)
        {
          wb->sys->dropCache(wb->fd, offset, length);
        }

      pthread_mutex_lock(&wb->lock);
      if (r != 0 && wb->error == 0)
        {
          wb->error = errno ? errno : EIO;
        }
      if (r == 0)
        {
          wb->written = (unsigned long long)(offset + length);
          if (elapsed > 0.0)
            {
              wb->bytesPerSecond = length / elapsed;
            }
        }
      wb->busy = NO;
      pthread_cond_broadcast(&wb->cond);
    }
  pthread_mutex_unlock(&wb->lock);
  return NULL;
}

#endif /* !_WIN32 */

@implementation GWFileDataCopier

- (instancetype)init
{
  return [self initWithSyscalls: NULL];
}

- (instancetype)initWithSyscalls:(const GWCopySyscalls *)syscalls
{
  self = [super init];
  if (self != nil)
    {
#if !defined(_WIN32)
      _sys = (syscalls != NULL) ? *syscalls : GWCopyDefaultSyscalls();
#else
      memset(&_sys, 0, sizeof(_sys));
#endif
      _windowCap = GW_COPY_WINDOW_CAP;
      _windowSizes = [NSMutableArray new];
      _lastMethod = GWCopyMethodFailed;
    }
  return self;
}

- (void)dealloc
{
  RELEASE(_shouldStop);
  RELEASE(_progress);
  RELEASE(_windowSizes);
  [super dealloc];
}

@synthesize windowed = _windowed;
@synthesize windowCap = _windowCap;
@synthesize shouldStop = _shouldStop;
@synthesize progress = _progress;
@synthesize lastMethod = _lastMethod;

- (NSArray *)windowSizes
{
  return [NSArray arrayWithArray: _windowSizes];
}

#if !defined(_WIN32)

/* Moves up to `length' bytes at *offset with `method'; returns the bytes
 * moved, 0 at the end of the source, -1 with errno set. */
- (ssize_t)_moveWith:(GWCopyMethod)method
                from:(int)inFD
                  to:(int)outFD
              offset:(off_t *)offset
              length:(size_t)length
              buffer:(char **)buffer
{
  ssize_t r;

  switch (method)
    {
      case GWCopyMethodCopyFileRange:
        if (_sys.copyFileRange == NULL)
          {
            errno = ENOSYS;
            return -1;
          }
        do
          {
            r = _sys.copyFileRange(inFD, offset, outFD, length);
          }
        while (r < 0 && errno == EINTR);
        return r;
      case GWCopyMethodSendfile:
        if (_sys.sendFile == NULL)
          {
            errno = ENOSYS;
            return -1;
          }
        do
          {
            r = _sys.sendFile(outFD, inFD, offset, length);
          }
        while (r < 0 && errno == EINTR);
        return r;
      case GWCopyMethodReadWrite:
        if (*buffer == NULL)
          {
            *buffer = malloc(GW_COPY_CHUNK);
            if (*buffer == NULL)
              {
                errno = ENOMEM;
                return -1;
              }
          }
        if (length > GW_COPY_CHUNK)
          {
            length = GW_COPY_CHUNK;
          }
        r = _sys.readAt(inFD, *buffer, length, *offset);
        if (r > 0)
          {
            if (_sys.writeAll(outFD, *buffer, (size_t)r) < 0)
              {
                return -1;
              }
            *offset += r;
          }
        return r;
      default:
        errno = EIO;
        return -1;
    }
}

- (BOOL)copyFromFileDescriptor:(int)inFD
              toFileDescriptor:(int)outFD
                        length:(unsigned long long)length
                         error:(int *)error
{
  GWCopyMethod method = GWCopyMethodCopyFileRange;
  GWWriteback wb;
  pthread_t writer;
  BOOL writerRunning = NO;
  char *buffer = NULL;
  off_t offset = 0;
  /* The destination position the copy started at; the windows are file
   * ranges, and the copy may append to a file that has data already. */
  off_t base = lseek(outFD, 0, SEEK_CUR);
  unsigned long long window = 0;
  unsigned long long windowStart = 0;
  unsigned long long shown = 0;
  int failure = 0;

  [_windowSizes removeAllObjects];
  if (base < 0)
    {
      base = 0;
    }
  memset(&wb, 0, sizeof(wb));
  wb.sys = &_sys;
  wb.fd = outFD;
  if (_windowed)
    {
      window = GWCopyNextWindowSize(0, 0.0, _windowCap);
      pthread_mutex_init(&wb.lock, NULL);
      pthread_cond_init(&wb.cond, NULL);
    }

  while ((unsigned long long)offset < length)
    {
      unsigned long long want = length - (unsigned long long)offset;
      unsigned long long chunk = _windowed ? GW_COPY_CHUNK
                                           : GW_COPY_LOCAL_CHUNK;
      ssize_t moved;

      if (_shouldStop != NULL && _shouldStop())
        {
          failure = ECANCELED;
          break;
        }
      if (_windowed)
        {
          unsigned long long room = windowStart + window
                                    - (unsigned long long)offset;

          if (room < chunk)
            {
              chunk = room;
            }
        }
      if (want > chunk)
        {
          want = chunk;
        }

      moved = [self _moveWith: method
                         from: inFD
                           to: outFD
                       offset: &offset
                       length: (size_t)want
                       buffer: &buffer];
      if (moved == 0 && offset == 0 && method != GWCopyMethodReadWrite)
        {
          /* procfs and sysfs files claim a size but give nothing to the
           * in-kernel copies; read() still sees their contents. */
          moved = -1;
          errno = EINVAL;
        }
      if (moved < 0)
        {
          GWCopyMethod next = GWCopyMethodAfterError(method, errno);

          if (next == GWCopyMethodFailed)
            {
              failure = errno ? errno : EIO;
              break;
            }
          method = next;
          continue;
        }
      if (moved == 0)
        {
          /* The source shrank under us; the size check after the copy
           * reports that. */
          break;
        }

      /* Full windows go to the writer; so does the tail of a file that
       * had full windows, which then is on the device as a whole.  A file
       * smaller than one window is left to the flush at the end of the
       * operation: syncing every small file made thousands of them crawl. */
      if (_windowed
          && ((unsigned long long)offset == windowStart + window
              || ((unsigned long long)offset >= length && writerRunning)))
        {
          unsigned long long thisLength = (unsigned long long)offset
                                          - windowStart;

          if (writerRunning == NO)
            {
              if (pthread_create(&writer, NULL, writebackMain, &wb) != 0)
                {
                  failure = errno ? errno : EAGAIN;
                  break;
                }
              writerRunning = YES;
            }
          pthread_mutex_lock(&wb.lock);
          /* The copy may be one window ahead, not two. */
          while ((wb.pending || wb.busy) && wb.error == 0)
            {
              pthread_cond_wait(&wb.cond, &wb.lock);
            }
          if (wb.error != 0)
            {
              failure = wb.error;
              pthread_mutex_unlock(&wb.lock);
              break;
            }
          wb.offset = base + (off_t)windowStart;
          wb.length = (off_t)thisLength;
          wb.pending = YES;
          [_windowSizes addObject:
            [NSNumber numberWithUnsignedLongLong: thisLength]];
          window = GWCopyNextWindowSize(window, wb.bytesPerSecond, _windowCap);
          pthread_cond_broadcast(&wb.cond);
          pthread_mutex_unlock(&wb.lock);
          windowStart = (unsigned long long)offset;
        }

      if (_progress != NULL)
        {
          unsigned long long written;

          if (_windowed)
            {
              pthread_mutex_lock(&wb.lock);
              written = wb.written > (unsigned long long)base
                        ? wb.written - (unsigned long long)base : 0;
              pthread_mutex_unlock(&wb.lock);
              shown = GWCopyBoundedProgress((unsigned long long)offset,
                                            written, window, shown);
            }
          else
            {
              shown = (unsigned long long)offset;
            }
          _progress(shown);
        }
    }

  if (writerRunning)
    {
      /* A file is done only when its last window is on the device too; on
       * failure the writer is still waited for, since it uses our fd. */
      pthread_mutex_lock(&wb.lock);
      while ((wb.pending || wb.busy) && wb.error == 0)
        {
          pthread_cond_wait(&wb.cond, &wb.lock);
        }
      if (failure == 0 && wb.error != 0)
        {
          failure = wb.error;
        }
      wb.pending = NO;
      wb.quit = YES;
      pthread_cond_broadcast(&wb.cond);
      pthread_mutex_unlock(&wb.lock);
      pthread_join(writer, NULL);
      if (failure == 0 && _progress != NULL)
        {
          _progress((unsigned long long)offset);
        }
    }
  if (_windowed)
    {
      pthread_cond_destroy(&wb.cond);
      pthread_mutex_destroy(&wb.lock);
    }
  free(buffer);
  _lastMethod = (failure == 0) ? method : GWCopyMethodFailed;
  if (failure != 0 && error != NULL)
    {
      *error = failure;
    }
  return failure == 0;
}

#else /* _WIN32 */

- (BOOL)copyFromFileDescriptor:(int)inFD
              toFileDescriptor:(int)outFD
                        length:(unsigned long long)length
                         error:(int *)error
{
  /* Windows copies through CopyFileW in NSFileManager; never called. */
  if (error != NULL)
    {
      *error = ENOSYS;
    }
  return NO;
}

#endif

@end
