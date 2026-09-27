/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

/* t_GWThumbnailerConcurrency.m - thumbsDict and pathsInProcessing used to be
 * mutated from one detached NSThread per makeThumbnails:/removeThumbnails:
 * call with no lock (dictLock only guarded the plist write); several
 * folders opened at once, or a make racing a remove, corrupted the
 * containers. Headless: registers a stub TMBProtocol thumbnailer (no real
 * image decoding, so this exercises the container locking, not the
 * per-format thumbnailer bundles), drives makeThumbnails:/removeThumbnails:
 * for 50 temp directories from 8 concurrent driver threads (5 "make" loops
 * racing 3 "remove" loops over an overlapping subset of the same paths),
 * and checks the shared state survives intact: no crash, pathsInProcessing
 * drains back to empty, and the 30 directories only ever touched by
 * "make" end up with exactly the right thumbnail count each - a make/remove
 * race on the other 20 makes their exact outcome scheduling-dependent, so
 * only the invariants (dict/file consistency, no leaked in-processing
 * marker) are asserted there.
 *
 * Isolation: this GNUstep install resolves NSHomeDirectory()/the user
 * Library path from the real passwd entry, not from $HOME or
 * $GNUSTEP_USER_ROOT, so a plain env-var override cannot redirect
 * Thumbnailer away from the real ~/Library/Thumbnails (confirmed empirically
 * while writing this test). Sharing the real thumbnailDir/thumbsDict/plist
 * across every run would race the developer's own real thumbnail cache and
 * accumulate garbage entries in it run after run. Instead, a test-only
 * category (below) resets thumbnailDir/dictPath/thumbsDict on the
 * singleton, right after construction, to a private scratch tree - the one
 * unavoidable touch of the real dictPath is +sharedThumbnailer's own -init,
 * which reads the real plist (if any) and immediately re-saves the same
 * content back unchanged before this test gets control. */

#import <Foundation/Foundation.h>
#import "Testing.h"

#include <unistd.h>

static void
mkdirp(NSFileManager *fm, NSString *path)
{
  NSArray *comps = [path pathComponents];
  NSString *partial = @"";
  NSUInteger i;

  for (i = 0; i < [comps count]; i++)
    {
      partial = [partial stringByAppendingPathComponent: [comps objectAtIndex: i]];
      if (![fm fileExistsAtPath: partial])
        {
          [fm createDirectoryAtPath: partial attributes: nil];
        }
    }
}

#include "../../Workspace/Thumbnailer/GWThumbnailer.m"

/* A category shares the class's ivar layout, so this can reach
 * thumbnailDir/dictPath/thumbsDict directly even though GWThumbnailer.h
 * declares them with no access specifier (the ObjC default, @protected). */
@interface Thumbnailer (ConcurrencyTestIsolation)
- (void)redirectForTestingToDir:(NSString *)dir;
@end

@implementation Thumbnailer (ConcurrencyTestIsolation)
- (void)redirectForTestingToDir:(NSString *)dir
{
  ASSIGN (thumbnailDir, dir);
  ASSIGN (dictPath, [dir stringByAppendingPathComponent: @"thumbnails.plist"]);
  RELEASE (thumbsDict);
  thumbsDict = [NSMutableDictionary new];
}
@end

/* Stands in for a real .thumb bundle: constant-cost, so the test exercises
 * the container locking under contention rather than image decoding time. */
@interface StubThumbnailer : NSObject <TMBProtocol>
@end

@implementation StubThumbnailer
- (BOOL)canProvideThumbnailForPath:(NSString *)path
{
  return YES;
}
- (NSData *)makeThumbnailForPath:(NSString *)path
{
  /* A few ms of "work" widens the interleaving window between the
   * concurrent worker threads instead of letting each call finish before
   * the next one even starts. */
  usleep(2000);
  return [@"stub-thumbnail-data" dataUsingEncoding: NSUTF8StringEncoding];
}
- (NSString *)fileNameExtension
{
  return @"stub";
}
- (NSString *)description
{
  return @"StubThumbnailer";
}
@end

#define NDIRS 50
#define NFILES 3
#define NMAKE_THREADS 5
#define NREMOVE_THREADS 3
#define NCONTESTED 20

static NSArray *dirPaths = nil;

/* Counts driver threads that have issued every call they are going to
 * issue - a SEPARATE lock from dictLock (the one under test), so this
 * bookkeeping never masks a locking bug in the code under test. Reading
 * pathsInProcessing hitting zero is not by itself proof the run has
 * settled: a driver can be between two loop iterations, with nothing
 * in flight for an instant, while it still has directories left to
 * hand to makeThumbnails:/removeThumbnails:. The final-state assertions
 * below are only meaningful once every driver has finished handing out
 * work AND every worker it started has drained. */
static NSLock *doneLock = nil;
static NSUInteger doneCount = 0;

@interface MakeDriver : NSObject
+ (void)run:(id)ignored;
@end
@implementation MakeDriver
+ (void)run:(id)ignored
{
  NSAutoreleasePool *arp = [NSAutoreleasePool new];
  NSUInteger i;

  for (i = 0; i < [dirPaths count]; i++)
    {
      [[Thumbnailer sharedThumbnailer] makeThumbnails: [dirPaths objectAtIndex: i]];
      usleep(200);
    }
  [doneLock lock];
  doneCount++;
  [doneLock unlock];
  [arp release];
}
@end

@interface RemoveDriver : NSObject
+ (void)run:(id)ignored;
@end
@implementation RemoveDriver
+ (void)run:(id)ignored
{
  NSAutoreleasePool *arp = [NSAutoreleasePool new];
  NSUInteger i;

  /* Only the contested prefix: these are the paths a concurrent "make"
   * driver may also be regenerating right now. */
  for (i = 0; i < NCONTESTED; i++)
    {
      [[Thumbnailer sharedThumbnailer] removeThumbnails: [dirPaths objectAtIndex: i]];
      usleep(300);
    }
  [doneLock lock];
  doneCount++;
  [doneLock unlock];
  [arp release];
}
@end

int
main(void)
{
  NSAutoreleasePool *arp;
  NSFileManager *fm;
  NSString *scratchRoot;
  NSString *scratchThumbDir;
  Thumbnailer *t;
  NSUInteger i, j;
  NSMutableArray *paths;
  BOOL drained;

  arp = [NSAutoreleasePool new];
  fm = [NSFileManager defaultManager];

  scratchRoot = [NSTemporaryDirectory() stringByAppendingPathComponent:
    [NSString stringWithFormat: @"t_GWThumbnailerConcurrency_%d", (int)getpid()]];
  [fm removeFileAtPath: scratchRoot handler: nil];

  scratchThumbDir = [scratchRoot stringByAppendingPathComponent: @"Thumbnails"];
  mkdirp(fm, scratchThumbDir);

  paths = [NSMutableArray array];
  for (i = 0; i < NDIRS; i++)
    {
      NSString *d = [scratchRoot stringByAppendingPathComponent:
        [NSString stringWithFormat: @"dir%lu", (unsigned long)i]];

      [fm createDirectoryAtPath: d attributes: nil];
      for (j = 0; j < NFILES; j++)
        {
          NSString *f = [d stringByAppendingPathComponent:
            [NSString stringWithFormat: @"f%lu.txt", (unsigned long)j]];
          [@"x" writeToFile: f atomically: YES];
        }
      [paths addObject: d];
    }
  dirPaths = [paths retain];

  t = [Thumbnailer sharedThumbnailer];
  /* From here on nothing touches the real ~/Library/Thumbnails again. */
  [t redirectForTestingToDir: scratchThumbDir];
  [t addThumbnailer: [[[StubThumbnailer alloc] init] autorelease]];
  doneLock = [[NSLock alloc] init];

  /* NSDistributedNotificationCenter's own DO connection is set up lazily
   * on first use and is not what this test is about (thumbsDict/
   * pathsInProcessing are) - establish it here, single-threaded, so the
   * concurrent make/remove workers below (each of which posts on this
   * center once it registers or deletes a thumbnail) only ever reuse an
   * already-live connection instead of racing its first-time setup. */
  [[NSDistributedNotificationCenter defaultCenter]
    postNotificationName: @"GWThumbnailerConcurrencyTestWarmup"
                  object: nil];

  /* Prime the contested prefix once, single-threaded, so the concurrent
   * "remove" drivers below have something real to race the "make"
   * drivers over instead of racing against an always-empty dict. */
  for (i = 0; i < NCONTESTED; i++)
    {
      [t makeThumbnails: [dirPaths objectAtIndex: i]];
    }
  drained = NO;
  for (i = 0; i < 500 && !drained; i++)
    {
      usleep(10000);
      drained = ([[t valueForKey: @"pathsInProcessing"] count] == 0);
    }
  PASS(drained, "priming pass for the contested directories finishes before the stress run starts");

  /* --- the stress run: 5 make drivers race 3 remove drivers --- */
  for (i = 0; i < NMAKE_THREADS; i++)
    {
      [NSThread detachNewThreadSelector: @selector(run:) toTarget: [MakeDriver class] withObject: nil];
    }
  for (i = 0; i < NREMOVE_THREADS; i++)
    {
      [NSThread detachNewThreadSelector: @selector(run:) toTarget: [RemoveDriver class] withObject: nil];
    }

  /* First wait for every driver to have issued its whole call sequence -
   * otherwise a driver merely between two iterations (nothing in flight
   * for an instant, more directories still to come) can make the
   * pathsInProcessing-based drain check below fire early. */
  {
    BOOL allDriversDone = NO;

    for (i = 0; i < 2000 && !allDriversDone; i++)
      {
        usleep(10000);
        [doneLock lock];
        allDriversDone = (doneCount == (NMAKE_THREADS + NREMOVE_THREADS));
        [doneLock unlock];
      }
    PASS(allDriversDone, "all 8 driver threads finish handing out their make/remove calls");
  }

  /* Now pathsInProcessing draining back to empty is a real signal that
   * every detached worker (make or remove) this run touched has finished
   * and removed its own marker - the exact bug in _removeThumbnails:
   * fixed alongside the locking (an early return skipped that removal). */
  drained = NO;
  for (i = 0; i < 2000 && !drained; i++)
    {
      usleep(10000);
      drained = ([[t valueForKey: @"pathsInProcessing"] count] == 0);
    }

  PASS(drained, "pathsInProcessing drains back to empty once every make/remove worker finishes "
                "(no leaked in-processing marker, no NSMutableArray corruption)");

  {
    NSDictionary *finalDict = [t valueForKey: @"thumbsDict"];
    NSUInteger uncontestedEntries = 0;

    PASS(finalDict != nil, "thumbsDict is still a valid dictionary after the concurrent run "
                            "(no crash, no corrupted container)");

    /* Directories NCONTESTED..NDIRS-1 were only ever touched by the make
     * drivers (never raced by a remove driver), so their outcome is
     * deterministic: every file must have a registered thumbnail whose
     * file actually exists on disk. */
    for (i = NCONTESTED; i < NDIRS; i++)
      {
        NSString *d = [dirPaths objectAtIndex: i];

        for (j = 0; j < NFILES; j++)
          {
            NSString *f = [d stringByAppendingPathComponent:
              [NSString stringWithFormat: @"f%lu.txt", (unsigned long)j]];
            NSString *tname = [finalDict objectForKey: f];

            if (tname != nil
                && [fm fileExistsAtPath: [scratchThumbDir stringByAppendingPathComponent: tname]])
              {
                uncontestedEntries++;
              }
          }
      }

    PASS(uncontestedEntries == (NDIRS - NCONTESTED) * NFILES,
         "every uncontested directory's files (%lu expected) has a thumbnail entry whose "
         "file really exists - no lost or dangling registration",
         (unsigned long)((NDIRS - NCONTESTED) * NFILES));

    /* Every entry that does exist in the dict, contested or not, must
     * point at a real file - a corrupted/half-written dict would leave
     * dangling entries here. */
    {
      NSEnumerator *en = [finalDict keyEnumerator];
      NSString *key;
      BOOL allConsistent = YES;

      while ((key = [en nextObject]) != nil)
        {
          NSString *tname = [finalDict objectForKey: key];
          NSString *tpath = [scratchThumbDir stringByAppendingPathComponent: tname];

          if (![fm fileExistsAtPath: tpath])
            {
              allConsistent = NO;
              break;
            }
        }

      PASS(allConsistent, "every remaining thumbsDict entry points at a thumbnail file that exists");
    }
  }

  [fm removeFileAtPath: scratchRoot handler: nil];
  [arp release];
  return 0;
}
