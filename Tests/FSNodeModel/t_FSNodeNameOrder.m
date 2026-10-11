/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-2.0-or-later
 */

/* Name order as Finder's "arrange by name" and name column (E20, E25). */

#import <AppKit/AppKit.h>
#import "Testing.h"
#import "FSNode.h"
#import "FSNFunctions.h"

static FSNode *
make(NSString *dir, NSString *name, BOOL isDir)
{
  NSString *p = [dir stringByAppendingPathComponent: name];

  if (isDir)
    [[NSFileManager defaultManager] createDirectoryAtPath: p attributes: nil];
  else
    [@"x" writeToFile: p atomically: YES];
  return [FSNode nodeWithPath: p];
}

static BOOL
before(FSNode *a, FSNode *b)
{
  return [a compareAccordingToName: b] == NSOrderedAscending
         && [b compareAccordingToName: a] == NSOrderedDescending;
}

int
main(void)
{
  NSAutoreleasePool *arp = [NSAutoreleasePool new];
  NSFileManager *fm = [NSFileManager defaultManager];
  NSString *dir = [NSTemporaryDirectory () stringByAppendingPathComponent:
                    [NSString stringWithFormat: @"t_FSNodeNameOrder_%d", (int)getpid ()]];
  FSNode *ds, *big, *dr, *mid, *small, *apple, *banana, *f2, *f10, *app, *foobar;

  [[NSUserDefaults standardUserDefaults] setInteger: GSFilenameExtensionHidePackageExtensions
                                             forKey: @"GSFilenameExtensionDisplayMode"];
  [fm removeFileAtPath: dir handler: nil];
  [fm createDirectoryAtPath: dir attributes: nil];
  ds = make (dir, @".DS_Store", NO);
  big = make (dir, @"big.bin", NO);
  dr = make (dir, @"dir", YES);
  mid = make (dir, @"mid.txt", NO);
  small = make (dir, @"small.rtf", NO);
  apple = make (dir, @"Apple", NO);
  banana = make (dir, @"banana", NO);
  f2 = make (dir, @"file2", NO);
  f10 = make (dir, @"file10", NO);
  app = make (dir, @"Foo.app", YES);
  foobar = make (dir, @"Foo Bar", NO);

  PASS (before (ds, big), "MI-FSN-80 [O:2026-10-11 E25] a dot file comes before the others");
  PASS (before (big, dr) && before (dr, mid) && before (mid, small),
        "MI-FSN-81 [O:2026-10-11 E25] folders are not sorted first, files and folders mix");
  PASS (before (apple, banana) && before (banana, make (dir, @"Cherry", NO)),
        "MI-FSN-82 [O:2026-10-11 E20] case does not decide the order");
  PASS (before (f2, f10), "MI-FSN-83 [G: Finder's standard compare] numbers compare by value");
  PASS_EQUAL ([app displayName], @"Foo", "MI-FSN-84 [O:2026-10-11 E22] an application shows without .app");
  PASS (before (app, foobar), "MI-FSN-85 [G: Finder orders by the shown name] an application sorts by its name without .app");

  [fm removeFileAtPath: dir handler: nil];
  [arp release];
  return 0;
}
