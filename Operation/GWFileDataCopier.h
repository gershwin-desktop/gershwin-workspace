/* GWFileDataCopier.h
 *
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

#ifndef GW_FILE_DATA_COPIER_H
#define GW_FILE_DATA_COPIER_H

#import <Foundation/Foundation.h>
#include <sys/types.h>

/* write() returns as soon as the data is in the page cache, so on a slow
 * USB stick or a network share a copy would look done long before the data
 * is there.  For such destinations the data is written in windows: a helper
 * thread writes each full window out and waits for it while the copy fills
 * the next one, so the copy never runs more than two windows ahead of the
 * device and the progress shown never more than one. */

#define GW_COPY_INITIAL_WINDOW   (1ULL << 20)
#define GW_COPY_MINIMUM_WINDOW   (128ULL << 10)
#define GW_COPY_WINDOW_CAP       (16ULL << 20)
#define GW_COPY_CIFS_WINDOW_CAP  (128ULL << 20)
/* A window should take about this long to write, short enough that the
 * progress stays close to the device and long enough that the waits do not
 * cost throughput. */
#define GW_COPY_WINDOW_SECONDS   0.2

typedef enum
{
  GWCopyMethodCopyFileRange = 0,
  GWCopyMethodSendfile,
  GWCopyMethodReadWrite,
  GWCopyMethodFailed
} GWCopyMethod;

/* The size of the next window, from the one before and the speed it was
 * written at (0 when not measured yet). */
unsigned long long GWCopyNextWindowSize(unsigned long long previous,
                                        double bytesPerSecond,
                                        unsigned long long cap);

/* What may be shown as copied: never more than one window ahead of what is
 * written, never more than was copied, never less than shown before. */
unsigned long long GWCopyBoundedProgress(unsigned long long copied,
                                         unsigned long long written,
                                         unsigned long long window,
                                         unsigned long long shown);

/* Which way to copy on after `method' failed with `err'. */
GWCopyMethod GWCopyMethodAfterError(GWCopyMethod method, int err);

/* The system calls the copier uses, replaceable so that tests can inject
 * failures.  A member that the platform lacks is NULL. */
typedef struct
{
  ssize_t (*copyFileRange)(int in, off_t *inOffset, int out, size_t length);
  ssize_t (*sendFile)(int out, int in, off_t *inOffset, size_t length);
  ssize_t (*readAt)(int fd, void *buffer, size_t length, off_t offset);
  ssize_t (*writeAll)(int fd, const void *buffer, size_t length);
  /* Writes the range out and waits until it is on the device. */
  int (*syncRange)(int fd, off_t offset, off_t length);
  /* Drops the written range from the page cache. */
  void (*dropCache)(int fd, off_t offset, off_t length);
} GWCopySyscalls;

GWCopySyscalls GWCopyDefaultSyscalls(void);

@interface GWFileDataCopier : NSObject
{
  GWCopySyscalls _sys;
  BOOL _windowed;
  unsigned long long _windowCap;
  BOOL (^_shouldStop)(void);
  void (^_progress)(unsigned long long);
  GWCopyMethod _lastMethod;
  NSMutableArray *_windowSizes;
}

- (instancetype)init;
- (instancetype)initWithSyscalls:(const GWCopySyscalls *)syscalls;

/* Write in windows that are waited for (removable and network targets). */
@property (nonatomic, assign) BOOL windowed;
@property (nonatomic, assign) unsigned long long windowCap;
/* Asked between chunks; YES ends the copy with ECANCELED. */
@property (nonatomic, copy) BOOL (^shouldStop)(void);
/* Bytes of this file that may be shown as copied, rising. */
@property (nonatomic, copy) void (^progress)(unsigned long long bytes);

/* The method the last copy ended with. */
@property (nonatomic, readonly) GWCopyMethod lastMethod;
/* The windows the last copy handed to the writer, as NSNumbers. */
@property (nonatomic, readonly) NSArray *windowSizes;

/* Copies `length' bytes from the start of `inFD' to the current position
 * of `outFD'.  On failure *error is the errno (ECANCELED when stopped). */
- (BOOL)copyFromFileDescriptor:(int)inFD
              toFileDescriptor:(int)outFD
                        length:(unsigned long long)length
                         error:(int *)error;

@end

#endif
