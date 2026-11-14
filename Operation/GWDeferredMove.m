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

/* Windows has no links, and no lstat(). */
#if defined(_WIN32)
#define lstat(p, st) stat((p), (st))
#endif

typedef enum
{
  GWTreeGone = 0,
  GWTreeKept,
  GWTreeFailed
} GWTreeResult;

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

- (GWTreeResult)_deleteSource:(NSString *)src
                  destination:(NSString *)dst
                       report:(void (^)(NSString *))report
                      changed:(NSMutableArray *)changed
                        error:(NSError **)error
{
  struct stat st;
  struct stat dstSt;
  const char *path = [src fileSystemRepresentation];
  BOOL dstPresent = (lstat([dst fileSystemRepresentation], &dstSt) == 0);

  if (lstat(path, &st) != 0)
    {
      return GWTreeGone;
    }
  if (S_ISDIR(st.st_mode))
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
      if (rmdir(path) != 0)
        {
          if (errno == ENOTEMPTY || errno == EEXIST)
            {
              /* Something new appeared in it meanwhile. */
              return GWTreeKept;
            }
          if (error)
            {
              *error = deleteError(src, errno);
            }
          return GWTreeFailed;
        }
      return GWTreeGone;
    }

  if (S_ISREG(st.st_mode))
    {
      NSDictionary *recorded;
      GWSourceDecision decision;

      [_lock lock];
      recorded = RETAIN([_snapshots objectForKey: src]);
      [_lock unlock];
      decision = GWDecideSourceDeletion(recorded, GWSourceSnapshotOfStat(&st),
                                        dstPresent && S_ISREG(dstSt.st_mode));
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
  if (unlink(path) != 0 && errno != ENOENT)
    {
      if (error)
        {
          *error = deleteError(src, errno);
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
