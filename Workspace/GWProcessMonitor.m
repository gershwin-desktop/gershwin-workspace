/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#define _GNU_SOURCE
#import "GWProcessMonitor.h"
#import <unistd.h>
#import <poll.h>
#import <signal.h>
#import <pthread.h>
#import <sys/syscall.h>

/* ------------------------------------------------------------------ */
/* Platform detection                                                 */
/* ------------------------------------------------------------------ */

#if defined(__linux__)
#define HAVE_PIDFD 1
#include <linux/types.h>
#include <sys/syscall.h>
#ifndef __NR_pidfd_open
#define __NR_pidfd_open 434
#endif
#else
#define HAVE_PIDFD 0
#endif

#if defined(__FreeBSD__) || defined(__OpenBSD__) || defined(__NetBSD__) || defined(__APPLE__)
#define HAVE_KQUEUE 1
#include <sys/event.h>
#include <sys/time.h>
#else
#define HAVE_KQUEUE 0
#endif

#define GW_PMON_MAX_PIDS 256

/* ------------------------------------------------------------------ */
/* Internal helper — wraps a callback invocation for main-thread dispatch */
/* ------------------------------------------------------------------ */

@interface _GWPMonCallback : NSObject
{
  void (^_block)(pid_t, id);
  pid_t _pid;
  id _token;
}
- (instancetype)initWithBlock:(void (^)(pid_t, id))block pid:(pid_t)pid token:(id)token;
- (void)invoke;
@end

@implementation _GWPMonCallback
- (instancetype)initWithBlock:(void (^)(pid_t, id))block pid:(pid_t)pid token:(id)token
{
  self = [super init];
  if (self)
    {
      _block = [block copy];
      _pid = pid;
      _token = [token retain];
    }
  return self;
}
- (void)dealloc
{
  [_block release];
  [_token release];
  [super dealloc];
}
- (void)invoke
{
  _block(_pid, _token);
}
@end

/* ------------------------------------------------------------------ */
/* Internal state                                                      */
/* ------------------------------------------------------------------ */

@interface GWProcessMonitor ()
{
  int _wakeupPipe[2];
  NSThread *_monitorThread;
  BOOL _running;
  pthread_mutex_t _mutex;

  struct {
    pid_t pid;
    int    fd;
    id     token;
    void  (^callback)(pid_t, id);
  } _entries[GW_PMON_MAX_PIDS];
  NSUInteger _count;
}
@end

@implementation GWProcessMonitor

/* ------------------------------------------------------------------ */
/* Singleton                                                           */
/* ------------------------------------------------------------------ */

+ (instancetype)sharedMonitor
{
  static GWProcessMonitor *shared = nil;
  if (shared == nil)
    {
      shared = [[self alloc] _init];
    }
  return shared;
}

- (instancetype)_init
{
  self = [super init];
  if (self)
    {
      _wakeupPipe[0] = -1;
      _wakeupPipe[1] = -1;
      _count = 0;
      pthread_mutex_init(&_mutex, NULL);

      if (pipe(_wakeupPipe) != 0)
        {
          [self release];
          return nil;
        }

      _running = YES;
      _monitorThread = [[NSThread alloc] initWithTarget:self
                                               selector:@selector(_monitorThreadMain)
                                                 object:nil];
      [_monitorThread setName:@"GWProcessMonitor"];
      [_monitorThread start];
    }
  return self;
}

- (void)dealloc
{
  _running = NO;

  if (_wakeupPipe[1] >= 0)
    {
      char c = 0;
      write(_wakeupPipe[1], &c, 1);
    }

  while (_monitorThread && ![_monitorThread isFinished])
    [NSThread sleepForTimeInterval:0.01];

  for (NSUInteger i = 0; i < _count; i++)
    {
      if (_entries[i].fd >= 0)
        close(_entries[i].fd);
      [_entries[i].token release];
      [_entries[i].callback release];
    }

  if (_wakeupPipe[0] >= 0) close(_wakeupPipe[0]);
  if (_wakeupPipe[1] >= 0) close(_wakeupPipe[1]);

  pthread_mutex_destroy(&_mutex);
  [super dealloc];
}

/* ------------------------------------------------------------------ */
/* Public API                                                          */
/* ------------------------------------------------------------------ */

- (void)addPID:(pid_t)pid
         token:(id)token
      callback:(void (^)(pid_t pid, id token))block
{
  if (pid <= 0 || block == nil)
    return;

  pthread_mutex_lock(&_mutex);

  for (NSUInteger i = 0; i < _count; i++)
    {
      if (_entries[i].pid == pid)
        {
          if (_entries[i].token != token)
            {
              [_entries[i].token release];
              _entries[i].token = [token retain];
            }
          if (_entries[i].callback != block)
            {
              [_entries[i].callback release];
              _entries[i].callback = [block copy];
            }
          pthread_mutex_unlock(&_mutex);
          [self _wakeup];
          return;
        }
    }

  if (_count >= GW_PMON_MAX_PIDS)
    {
      pthread_mutex_unlock(&_mutex);
      return;
    }

  int fd = -1;

#if HAVE_PIDFD
  fd = (int)syscall(__NR_pidfd_open, pid, 0);
#elif HAVE_KQUEUE
  {
    int kq = kqueue();
    if (kq >= 0)
      {
        struct kevent ev;
        EV_SET(&ev, pid, EVFILT_PROC, EV_ADD, NOTE_EXIT, 0, NULL);
        if (kevent(kq, &ev, 1, NULL, 0, NULL) == 0)
          fd = kq;
        else
          close(kq);
      }
  }
#endif

  _entries[_count].pid = pid;
  _entries[_count].fd = fd;
  _entries[_count].token = [token retain];
  _entries[_count].callback = [block copy];
  _count++;

  pthread_mutex_unlock(&_mutex);
  [self _wakeup];
}

- (void)removePID:(pid_t)pid
{
  if (pid <= 0)
    return;

  pthread_mutex_lock(&_mutex);

  for (NSUInteger i = 0; i < _count; i++)
    {
      if (_entries[i].pid == pid)
        {
          if (_entries[i].fd >= 0)
            close(_entries[i].fd);
          [_entries[i].token release];
          [_entries[i].callback release];

          _count--;
          if (i < _count)
            _entries[i] = _entries[_count];

          pthread_mutex_unlock(&_mutex);
          [self _wakeup];
          return;
        }
    }

  pthread_mutex_unlock(&_mutex);
}

/* ------------------------------------------------------------------ */
/* Internal helpers                                                    */
/* ------------------------------------------------------------------ */

- (void)_wakeup
{
  if (_wakeupPipe[1] >= 0)
    {
      char c = 0;
      write(_wakeupPipe[1], &c, 1);
    }
}

/* ------------------------------------------------------------------ */
/* Monitor thread                                                      */
/* ------------------------------------------------------------------ */

- (void)_monitorThreadMain
{
  @autoreleasepool
    {
      while (_running)
        {
          @autoreleasepool
            {
              [self _monitorTick];
            }

          if (!_running) break;

          /* Brief sleep when no kernel fds are available, so the
           * kill() fallback doesn't busy-wait. */
          usleep(500000);
        }
    }
}

- (void)_monitorTick
{
  pid_t pids[GW_PMON_MAX_PIDS];
  int    fds[GW_PMON_MAX_PIDS];
  NSUInteger count;

  pthread_mutex_lock(&_mutex);
  count = _count;
  for (NSUInteger i = 0; i < count; i++)
    {
      pids[i] = _entries[i].pid;
      fds[i]  = _entries[i].fd;
    }
  pthread_mutex_unlock(&_mutex);

  if (count == 0)
    return;

#if HAVE_PIDFD || HAVE_KQUEUE
  {
    struct pollfd pfds[GW_PMON_MAX_PIDS + 1];
    nfds_t npfd = 0;

    for (NSUInteger i = 0; i < count; i++)
      {
        if (fds[i] >= 0)
          {
            pfds[npfd].fd = fds[i];
            pfds[npfd].events = POLLIN;
            pfds[npfd].revents = 0;
            npfd++;
          }
      }

    /* Wakeup pipe so we can interrupt poll() when the PID list changes */
    if (_wakeupPipe[0] >= 0)
      {
        pfds[npfd].fd = _wakeupPipe[0];
        pfds[npfd].events = POLLIN;
        pfds[npfd].revents = 0;
        npfd++;
      }

    if (npfd > 0)
      {
        int ret = poll(pfds, npfd, -1);

        if (_running == NO) return;

        /* Drain wakeup pipe */
        if (ret > 0 && _wakeupPipe[0] >= 0)
          {
            for (nfds_t j = 0; j < npfd; j++)
              {
                if (pfds[j].fd == _wakeupPipe[0] && (pfds[j].revents & POLLIN))
                  {
                    char buf[64];
                    while (read(_wakeupPipe[0], buf, sizeof(buf)) > 0) {}
                    break;
                  }
              }
          }

        /* Check which kernel fds fired */
        for (NSUInteger i = 0; i < count; i++)
          {
            if (fds[i] < 0) continue;

            int revents = 0;
            for (nfds_t j = 0; j < npfd; j++)
              {
                if (pfds[j].fd == fds[i])
                  {
                    revents = pfds[j].revents;
                    break;
                  }
              }

            if (revents & (POLLIN | POLLERR | POLLHUP))
              {
                /* Snapshot and remove entry under the lock */
                id token = nil;
                void (^cb)(pid_t, id) = nil;

                pthread_mutex_lock(&_mutex);
                for (NSUInteger ei = 0; ei < _count; ei++)
                  {
                    if (_entries[ei].pid == pids[i])
                      {
                        token = [_entries[ei].token retain];
                        cb = [_entries[ei].callback retain];
                        if (_entries[ei].fd >= 0) close(_entries[ei].fd);
                        [_entries[ei].token release];
                        [_entries[ei].callback release];
                        _count--;
                        if (ei < _count)
                          _entries[ei] = _entries[_count];
                        break;
                      }
                  }
                pthread_mutex_unlock(&_mutex);

                if (cb)
                  {
                    _GWPMonCallback *wrapper;
                    wrapper = [[_GWPMonCallback alloc] initWithBlock:cb pid:pids[i] token:token];
                    [wrapper performSelectorOnMainThread:@selector(invoke)
                                              withObject:nil
                                           waitUntilDone:NO];
                    [wrapper release];
                    [cb release];
                    [token release];
                  }
              }
          }

        return;
      }
  }
#endif /* HAVE_PIDFD || HAVE_KQUEUE */

  /* ---- Fallback: periodic kill() polling ---- */
  for (NSUInteger i = 0; i < count; i++)
    {
      int result = kill(pids[i], 0);
      if ((result != 0) && (errno != EPERM))
        {
          id token = nil;
          void (^cb)(pid_t, id) = nil;

          pthread_mutex_lock(&_mutex);
          for (NSUInteger ei = 0; ei < _count; ei++)
            {
              if (_entries[ei].pid == pids[i])
                {
                  token = [_entries[ei].token retain];
                  cb = [_entries[ei].callback retain];
                  if (_entries[ei].fd >= 0) close(_entries[ei].fd);
                  [_entries[ei].token release];
                  [_entries[ei].callback release];
                  _count--;
                  if (ei < _count)
                    _entries[ei] = _entries[_count];
                  break;
                }
            }
          pthread_mutex_unlock(&_mutex);

          if (cb)
            {
              _GWPMonCallback *wrapper;
              wrapper = [[_GWPMonCallback alloc] initWithBlock:cb pid:pids[i] token:token];
              [wrapper performSelectorOnMainThread:@selector(invoke)
                                        withObject:nil
                                     waitUntilDone:NO];
              [wrapper release];
              [cb release];
              [token release];
            }
        }
    }
}

@end
