/* GWFileManager.m
 *
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

#import "GWFileManager.h"
#import "GWFileDataCopier.h"
#import "GWDestinationClassifier.h"
#import "GWDeferredMove.h"
#import <GNUstepBase/GNUstep.h>

#include <errno.h>
#include <fcntl.h>
#include <string.h>
#include <unistd.h>
#include <sys/stat.h>

#ifndef O_BINARY
#define O_BINARY 0
#endif

/* NSFileManager's -copyPath:toPath:handler: sends this for every regular
 * file it copies, folder contents included; it is the one place where the
 * data of a file is copied.  t_GWFileManager checks that it still is. */
@interface NSFileManager (GWFileDataCopy)
- (BOOL)_copyFile:(NSString *)source
           toFile:(NSString *)destination
          handler:(id)handler;
@end

@implementation GWFileManager

- (instancetype)init
{
  self = [super init];
  if (self != nil)
    {
      _lastMethod = GWCopyMethodFailed;
    }
  return self;
}

- (void)dealloc
{
  RELEASE(_destination);
  RELEASE(_journal);
  [super dealloc];
}

@synthesize destination = _destination;
@synthesize observer = _observer;
@synthesize journal = _journal;
@synthesize lastMethod = _lastMethod;

#if !defined(_WIN32)

/* The same error dictionary NSFileManager gives its handler, so that the
 * handler cannot tell which of us copied. */
- (BOOL)_gwProceed:(id)handler
             error:(NSString *)message
              code:(int)code
            inPath:(NSString *)path
          fromPath:(NSString *)from
            toPath:(NSString *)to
{
  NSString *text = message;

  if (code != 0)
    {
      text = [NSString stringWithFormat: @"%@: %s", message, strerror(code)];
    }
  if ([handler respondsToSelector:
                 @selector(fileManager:shouldProceedAfterError:)])
    {
      NSDictionary *info = @{ NSFilePathErrorKey: path, @"Path": path,
                              @"FromPath": from, @"ToPath": to,
                              @"Error": text };

      return [handler fileManager: self shouldProceedAfterError: info];
    }
  return NO;
}

static BOOL
sameState(const struct stat *a, const struct stat *b)
{
  NSDictionary *sa = GWSourceSnapshotOfStat(a);
  NSDictionary *sb = GWSourceSnapshotOfStat(b);

  return [sa isEqual: sb];
}

- (BOOL)_copyFile:(NSString *)source
           toFile:(NSString *)destination
          handler:(id)handler
{
  GWFileDataCopier *copier;
  struct stat before;
  struct stat after;
  int in;
  int out;
  int err = 0;
  BOOL copied;
  BOOL removable = [_destination needsFinalFlush];
  __block unsigned long long shown = 0;
  id <GWFileCopyObserver> observer = _observer;

  in = open([source fileSystemRepresentation], O_RDONLY | O_BINARY);
  if (in < 0 || fstat(in, &before) != 0)
    {
      err = errno;
      if (in >= 0)
        {
          close(in);
        }
      return [self _gwProceed: handler
                        error: @"cannot open file for reading"
                         code: err
                       inPath: source
                     fromPath: source
                       toPath: destination];
    }
  out = open([destination fileSystemRepresentation],
             O_WRONLY | O_CREAT | O_TRUNC | O_BINARY, before.st_mode & 07777);
  if (out < 0)
    {
      err = errno;
      close(in);
      return [self _gwProceed: handler
                        error: @"cannot open file for writing"
                         code: err
                       inPath: destination
                     fromPath: source
                       toPath: destination];
    }

  copier = [GWFileDataCopier new];
  [copier setWindowed: [_destination usesWriteWindows]];
  if (_destination != nil)
    {
      [copier setWindowCap: [_destination windowCap]];
    }
  if (observer != nil)
    {
      [copier setShouldStop: ^BOOL (void) {
        return [observer fileCopyShouldStop];
      }];
      [copier setProgress: ^(unsigned long long bytes) {
        if (bytes > shown)
          {
            [observer fileCopyDidAdvanceBy: bytes - shown];
            shown = bytes;
          }
      }];
    }
  copied = [copier copyFromFileDescriptor: in
                         toFileDescriptor: out
                                   length: (unsigned long long)before.st_size
                                    error: &err];
  _lastMethod = [copier lastMethod];
  RELEASE(copier);

  /* A file bigger than any window is worth its own flush before it counts
   * as copied, and so is the folder entry naming it; the many small ones
   * wait for the one flush at the end of the operation. */
  if (copied && removable && (unsigned long long)before.st_size
                             > [_destination windowCap])
    {
      if (fsync(out) != 0)
        {
          err = errno;
          copied = NO;
        }
      else
        {
          int dir = open([[destination stringByDeletingLastPathComponent]
                           fileSystemRepresentation], O_RDONLY);

          if (dir < 0 || fsync(dir) != 0)
            {
              err = errno;
              copied = NO;
            }
          if (dir >= 0)
            {
              close(dir);
            }
        }
    }
  /* close() is where NFS reports a write that failed on the server. */
  if (close(out) != 0 && copied)
    {
      err = errno;
      copied = NO;
    }
  if (copied && fstat(in, &after) == 0 && !sameState(&before, &after))
    {
      close(in);
      return [self _gwProceed: handler
                        error: @"source modified during copy"
                         code: 0
                       inPath: destination
                     fromPath: source
                       toPath: destination];
    }
  close(in);

  if (!copied)
    {
      /* Half a file is worse than none: it looks like the real thing. */
      unlink([destination fileSystemRepresentation]);
      if (err == ECANCELED)
        {
          return NO;
        }
      return [self _gwProceed: handler
                        error: @"cannot write to file"
                         code: err
                       inPath: destination
                     fromPath: source
                       toPath: destination];
    }
  if (observer != nil && (unsigned long long)before.st_size > shown)
    {
      [observer fileCopyDidAdvanceBy: (unsigned long long)before.st_size - shown];
    }
  [_journal recordSourcePath: source snapshot: GWSourceSnapshotOfStat(&before)];
  return YES;
}

#endif /* !_WIN32: Windows copies through CopyFileW in NSFileManager */

@end
