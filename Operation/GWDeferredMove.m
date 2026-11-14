/* GWDeferredMove.m
 *
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

#import "GWDeferredMove.h"
#import <GNUstepBase/GNUstep.h>

#include <errno.h>
#include <string.h>
#include <unistd.h>

#if defined(__APPLE__)
#define GW_MTIME_NSEC(st) ((st)->st_mtimespec.tv_nsec)
#elif defined(_WIN32)
#define GW_MTIME_NSEC(st) 0
#else
#define GW_MTIME_NSEC(st) ((st)->st_mtim.tv_nsec)
#endif

/* The file system representation is UTF-16 on Windows, so only the
 * wide-character CRT calls reach every name; they set errno like their
 * POSIX counterparts. */
#if defined(_WIN32)
#include <wchar.h>
#define gw_rmdir(p) _wrmdir(p)
#define gw_unlink(p) _wunlink(p)
#else
#define gw_rmdir(p) rmdir(p)
#define gw_unlink(p) unlink(p)
#endif

typedef enum
{
  GWTreeGone = 0,
  GWTreeKept,
  GWTreeFailed
} GWTreeResult;

typedef enum
{
  GWItemMissing = 0,
  GWItemDirectory,
  GWItemFile,
  GWItemOther
} GWItemKind;

NSDictionary *
GWSourceSnapshotOfStat(const struct stat *st)
{
  return @{ @"size": [NSNumber numberWithUnsignedLongLong:
                        (unsigned long long)st->st_size],
            @"mtime": [NSNumber numberWithLongLong: (long long)st->st_mtime],
            @"mtimeNsec": [NSNumber numberWithLong: (long)GW_MTIME_NSEC(st)] };
}

GWSourceDecision
GWDecideSourceDeletion(NSDictionary *recorded, NSDictionary *current,
                       BOOL destinationPresent)
{
  if (recorded == nil || destinationPresent == NO)
    {
      return GWSourceKeepUncopied;
    }
  if (current == nil)
    {
      /* Gone already: nothing left to delete, nothing lost. */
      return GWSourceDelete;
    }
  if (![[recorded objectForKey: @"size"] isEqual: [current objectForKey: @"size"]]
      || ![[recorded objectForKey: @"mtime"]
            isEqual: [current objectForKey: @"mtime"]]
      || ![[recorded objectForKey: @"mtimeNsec"]
            isEqual: [current objectForKey: @"mtimeNsec"]])
    {
      return GWSourceKeepChanged;
    }
  return GWSourceDelete;
}

/* What is at path, without following a link, plus the snapshot of a
 * regular file to compare with the one taken when it was copied. */
static GWItemKind
itemAtPath(NSString *path, NSDictionary **snapshot)
{
#if defined(_WIN32)
  /* Windows has no links, and its narrow stat() cannot reach every name.
   * No copy there records a snapshot, so a file is always kept. */
  NSDictionary *a = [[NSFileManager defaultManager]
                      attributesOfItemAtPath: path error: NULL];
  NSString *type = [a fileType];

  if (a == nil)
    {
      return GWItemMissing;
    }
  if ([type isEqual: NSFileTypeDirectory])
    {
      return GWItemDirectory;
    }
  if ([type isEqual: NSFileTypeRegular])
    {
      if (snapshot != NULL)
        {
          *snapshot = @{ @"size": [NSNumber numberWithUnsignedLongLong:
                                    [a fileSize]],
                         @"mtime": [NSNumber numberWithLongLong: (long long)
                                     [[a fileModificationDate]
                                       timeIntervalSince1970]],
                         @"mtimeNsec": [NSNumber numberWithLong: 0] };
        }
      return GWItemFile;
    }
  return GWItemOther;
#else
  struct stat st;

  if (lstat([path fileSystemRepresentation], &st) != 0)
    {
      return GWItemMissing;
    }
  if (S_ISDIR(st.st_mode))
    {
      return GWItemDirectory;
    }
  if (S_ISREG(st.st_mode))
    {
      if (snapshot != NULL)
        {
          *snapshot = GWSourceSnapshotOfStat(&st);
        }
      return GWItemFile;
    }
  return GWItemOther;
#endif
}

static NSError *
deleteError(NSString *path, int code)
{
  return [NSError errorWithDomain: NSPOSIXErrorDomain
                             code: code
                         userInfo: @{ NSFilePathErrorKey: path,
                                      NSLocalizedDescriptionKey:
                                        [NSString stringWithUTF8String:
                                                    strerror(code)] }];
}

@implementation GWDeferredMove

- (instancetype)init
{
  self = [super init];
  if (self != nil)
    {
      _snapshots = [NSMutableDictionary new];
      _items = [NSMutableArray new];
      _lock = [NSLock new];
    }
  return self;
}

- (void)dealloc
{
  RELEASE(_snapshots);
  RELEASE(_items);
  RELEASE(_lock);
  [super dealloc];
}

- (void)recordSourcePath:(NSString *)path snapshot:(NSDictionary *)snapshot
{
  [_lock lock];
  [_snapshots setObject: snapshot forKey: path];
  [_lock unlock];
}

- (void)addItemFrom:(NSString *)source
                 to:(NSString *)destination
               name:(NSString *)name
{
  [_lock lock];
  [_items addObject: @{ @"source": source, @"destination": destination,
                        @"name": name }];
  [_lock unlock];
}

- (NSArray *)items
{
  NSArray *a;

  [_lock lock];
  a = [NSArray arrayWithArray: _items];
  [_lock unlock];
  return a;
}

- (NSArray *)destinationPaths
{
  return [[self items] valueForKey: @"destination"];
}

- (BOOL)isEmpty
{
  return [[self items] count] == 0;
}

- (int)removeSourceAtPath:(NSString *)path directory:(BOOL)isDirectory
{
  int r;

  if (isDirectory)
    {
      r = gw_rmdir([path fileSystemRepresentation]);
    }
  else
    {
      r = gw_unlink([path fileSystemRepresentation]);
    }
  return (r == 0) ? 0 : errno;
}

- (GWTreeResult)_deleteSource:(NSString *)src
                  destination:(NSString *)dst
                       report:(void (^)(NSString *))report
                      changed:(NSMutableArray *)changed
                        error:(NSError **)error
{
  NSDictionary *current = nil;
  GWItemKind kind = itemAtPath(src, &current);
  GWItemKind dstKind = itemAtPath(dst, NULL);
  BOOL dstPresent = (dstKind != GWItemMissing);
  int code;

  if (kind == GWItemMissing)
    {
      return GWTreeGone;
    }
  if (kind == GWItemDirectory)
    {
      NSArray *names = [[NSFileManager defaultManager]
                         directoryContentsAtPath: src];
      NSEnumerator *en = [names objectEnumerator];
      NSString *name;
      BOOL kept = NO;

      while ((name = [en nextObject]) != nil)
        {
          GWTreeResult r;

          r = [self _deleteSource: [src stringByAppendingPathComponent: name]
                      destination: [dst stringByAppendingPathComponent: name]
                           report: report
                          changed: changed
                            error: error];
          if (r == GWTreeFailed)
            {
              return GWTreeFailed;
            }
          if (r == GWTreeKept)
            {
              kept = YES;
            }
        }
      if (kept)
        {
          return GWTreeKept;
        }
      code = [self removeSourceAtPath: src directory: YES];
      if (code != 0)
        {
          if (code == ENOTEMPTY || code == EEXIST)
            {
              /* Something new appeared in it meanwhile. */
              return GWTreeKept;
            }
          if (error)
            {
              *error = deleteError(src, code);
            }
          return GWTreeFailed;
        }
      return GWTreeGone;
    }

  if (kind == GWItemFile)
    {
      NSDictionary *recorded;
      GWSourceDecision decision;

      [_lock lock];
      recorded = RETAIN([_snapshots objectForKey: src]);
      [_lock unlock];
      decision = GWDecideSourceDeletion(recorded, current,
                                        dstKind == GWItemFile);
      RELEASE(recorded);
      if (decision == GWSourceKeepChanged)
        {
          [changed addObject: src];
          return GWTreeKept;
        }
      if (decision == GWSourceKeepUncopied)
        {
          return GWTreeKept;
        }
    }
  else if (dstPresent == NO)
    {
      /* Links and special files were copied by recreating them; whatever
       * has no counterpart at the destination was not. */
      return GWTreeKept;
    }

  if (report != NULL)
    {
      report([src lastPathComponent]);
    }
  code = [self removeSourceAtPath: src directory: NO];
  if (code != 0 && code != ENOENT)
    {
      if (error)
        {
          *error = deleteError(src, code);
        }
      return GWTreeFailed;
    }
  return GWTreeGone;
}

- (BOOL)deleteSourcesReporting:(void (^)(NSString *name))report
                         moved:(NSMutableArray *)moved
                       changed:(NSMutableArray *)changed
                         error:(NSError **)error
{
  NSEnumerator *en = [[self items] objectEnumerator];
  NSDictionary *item;

  while ((item = [en nextObject]) != nil)
    {
      GWTreeResult r;

      r = [self _deleteSource: [item objectForKey: @"source"]
                  destination: [item objectForKey: @"destination"]
                       report: report
                      changed: changed
                        error: error];
      if (r == GWTreeFailed)
        {
          return NO;
        }
      if (r == GWTreeGone)
        {
          [moved addObject: item];
        }
    }
  return YES;
}

@end
