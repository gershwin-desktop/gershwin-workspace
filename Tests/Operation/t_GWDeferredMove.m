/* t_GWDeferredMove.m - which sources a move to a removable device deletes
 * once the data is on the device, and which it keeps.  Headless.
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
#include "../../Operation/GWDeferredMove.m"

static NSString *base;

static NSString *
put(NSString *rel, NSString *text)
{
  NSString *p = [base stringByAppendingPathComponent: rel];

  [[NSFileManager defaultManager]
    createDirectoryAtPath: [p stringByDeletingLastPathComponent]
    withIntermediateDirectories: YES attributes: nil error: NULL];
  [text writeToFile: p atomically: NO];
  return p;
}

static BOOL
exists(NSString *rel)
{
  struct stat st;

  return lstat([[base stringByAppendingPathComponent: rel]
                 fileSystemRepresentation], &st) == 0;
}

/* Records every regular file below `src' as copied now. */
static void
journalTree(GWDeferredMove *mv, NSString *src)
{
  NSFileManager *fm = [NSFileManager defaultManager];
  NSDirectoryEnumerator *en = [fm enumeratorAtPath: src];
  NSMutableArray *paths = [NSMutableArray arrayWithObject: src];
  NSString *rel;
  NSEnumerator *pe;
  NSString *p;

  while ((rel = [en nextObject]) != nil)
    {
      [paths addObject: [src stringByAppendingPathComponent: rel]];
    }
  pe = [paths objectEnumerator];
  while ((p = [pe nextObject]) != nil)
    {
      struct stat st;

      if (lstat([p fileSystemRepresentation], &st) == 0 && S_ISREG(st.st_mode))
        {
          [mv recordSourcePath: p snapshot: GWSourceSnapshotOfStat(&st)];
        }
    }
}

int
main(void)
{
  NSAutoreleasePool *arp = [NSAutoreleasePool new];
  NSFileManager *fm = [NSFileManager defaultManager];
  NSDictionary *rec = @{ @"size": @10, @"mtime": @100, @"mtimeNsec": @5 };

  base = [NSTemporaryDirectory() stringByAppendingPathComponent:
           [NSString stringWithFormat: @"t_GWDeferredMove-%d", getpid()]];
  [fm removeFileAtPath: base handler: nil];

  START_SET("decision")
    NSDictionary *same = @{ @"size": @10, @"mtime": @100, @"mtimeNsec": @5 };
    NSDictionary *bigger = @{ @"size": @11, @"mtime": @100, @"mtimeNsec": @5 };
    NSDictionary *touched = @{ @"size": @10, @"mtime": @100, @"mtimeNsec": @6 };

    PASS(GWDecideSourceDeletion(rec, same, YES) == GWSourceDelete,
         "an unchanged, copied source is deleted");
    PASS(GWDecideSourceDeletion(rec, bigger, YES) == GWSourceKeepChanged,
         "a source whose size changed is kept");
    PASS(GWDecideSourceDeletion(rec, touched, YES) == GWSourceKeepChanged,
         "a source whose mtime changed is kept");
    PASS(GWDecideSourceDeletion(nil, same, YES) == GWSourceKeepUncopied,
         "a source never copied is kept");
    PASS(GWDecideSourceDeletion(rec, same, NO) == GWSourceKeepUncopied,
         "a source whose copy is gone is kept");
  END_SET("decision")

  START_SET("deleting the sources")
    GWDeferredMove *mv = AUTORELEASE([GWDeferredMove new]);
    NSMutableArray *moved = [NSMutableArray array];
    NSMutableArray *changed = [NSMutableArray array];
    NSMutableArray *reported = [NSMutableArray array];
    NSString *srcA = [base stringByAppendingPathComponent: @"src/A"];
    NSString *dstA = [base stringByAppendingPathComponent: @"dst/A"];
    NSString *srcB = [base stringByAppendingPathComponent: @"src/B"];
    NSString *dstB = [base stringByAppendingPathComponent: @"dst/B"];
    NSString *f2;
    NSError *err = nil;
    BOOL ok;

    put(@"src/A/f1", @"one");
    f2 = put(@"src/A/f2", @"two");
    put(@"src/A/sub/f3", @"three");
    symlink("f1", [[srcA stringByAppendingPathComponent: @"link"]
                    fileSystemRepresentation]);
    put(@"src/B", @"bee");
    [fm createDirectoryAtPath: [base stringByAppendingPathComponent: @"dst"]
                   attributes: nil];
    [fm copyPath: srcA toPath: dstA handler: nil];
    [fm copyPath: srcB toPath: dstB handler: nil];
    journalTree(mv, srcA);
    journalTree(mv, srcB);
    [mv addItemFrom: srcA to: dstA name: @"A"];
    [mv addItemFrom: srcB to: dstB name: @"B"];

    /* Written to while the copy was being flushed. */
    sleep(1);
    [@"two, edited" writeToFile: f2 atomically: NO];
    put(@"src/A/new", @"appeared later");

    ok = [mv deleteSourcesReporting: ^(NSString *name) {
      [reported addObject: name];
    }
                              moved: moved
                            changed: changed
                              error: &err];
    PASS(ok, "deleting succeeds");
    PASS(!exists(@"src/A/f1") && !exists(@"src/A/sub") && !exists(@"src/A/link"),
         "unchanged files, links and emptied folders are gone");
    PASS(exists(@"src/A/f2") && exists(@"src/A/new") && exists(@"src/A"),
         "the changed file, the new file and their folder stay");
    PASS([changed count] == 1 && [[changed objectAtIndex: 0] isEqual: f2],
         "the changed file is named for the warning");
    PASS(!exists(@"src/B"), "an unchanged item is moved entirely");
    PASS([moved count] == 1
         && [[[moved objectAtIndex: 0] objectForKey: @"name"] isEqual: @"B"],
         "only the item whose source is gone counts as moved");
    PASS([reported containsObject: @"f1"] && ![reported containsObject: @"f2"],
         "each deleted name is reported for the progress window");
    PASS(exists(@"dst/A/f2") && exists(@"dst/B"), "the copies are untouched");
  END_SET("deleting the sources")

  START_SET("a failing delete")
    GWDeferredMove *mv = AUTORELEASE([GWDeferredMove new]);
    NSMutableArray *moved = [NSMutableArray array];
    NSMutableArray *changed = [NSMutableArray array];
    NSString *srcC = [base stringByAppendingPathComponent: @"src2/C"];
    NSString *srcD = [base stringByAppendingPathComponent: @"src2/D"];
    NSError *err = nil;

    put(@"src2/C/x", @"x");
    put(@"src2/D", @"d");
    put(@"dst2/C/x", @"x");
    put(@"dst2/D", @"d");
    journalTree(mv, srcC);
    journalTree(mv, srcD);
    [mv addItemFrom: srcC to: [base stringByAppendingPathComponent: @"dst2/C"]
               name: @"C"];
    [mv addItemFrom: srcD to: [base stringByAppendingPathComponent: @"dst2/D"]
               name: @"D"];
    chmod([srcC fileSystemRepresentation], 0555);
    PASS(![mv deleteSourcesReporting: NULL moved: moved changed: changed
                               error: &err]
         && err != nil, "a delete that fails is reported");
    PASS(exists(@"src2/C/x") && exists(@"src2/D") && [moved count] == 0,
         "and everything not deleted yet stays");
    chmod([srcC fileSystemRepresentation], 0755);
  END_SET("a failing delete")

  [fm removeFileAtPath: base handler: nil];
  [arp release];
  return 0;
}
