/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 */

/* How the size column of the list view and the numbers of the icon view
 * write sizes: base 10 units of the space a file takes on the disk. */

#import <AppKit/AppKit.h>
#import <sys/stat.h>
#import <unistd.h>
#import "Testing.h"
#import "FSNFunctions.h"

int
main(void)
{
  NSAutoreleasePool *arp = [NSAutoreleasePool new];
  NSBundle *bundle = [NSBundle bundleForClass: NSClassFromString (@"FSNode")];
  NSFileManager *fm = [NSFileManager defaultManager];
  NSString *dir = [NSTemporaryDirectory () stringByAppendingPathComponent:
                                             [NSString stringWithFormat: @"fsnsize-%d", getpid ()]];
  NSString *file = [dir stringByAppendingPathComponent: @"f"];
  struct stat st;
  NSString *bytes999 = [NSString stringWithFormat:
    [bundle localizedStringForKey: @"%lu bytes" value: @"" table: nil], 999UL];

  PASS_EQUAL (FSNFinderSizeDescription (0, @"."), [bundle localizedStringForKey: @"Zero bytes" value: @"" table: nil],
              "MI-LST-84 [O:2026-10-11 E23] nothing is zero bytes");
  PASS_EQUAL (FSNFinderSizeDescription (1, @"."), [bundle localizedStringForKey: @"1 byte" value: @"" table: nil],
              "MI-LST-85 one byte");
  PASS_EQUAL (FSNFinderSizeDescription (999, @"."), bytes999,
              "MI-LST-86 below 1000 bytes counted in bytes");
  PASS_EQUAL (FSNFinderSizeDescription (4096, @"."), @"4 KB",
              "MI-LST-87 [O:2026-10-11 E23] a 4096 byte block is \"4 KB\" (base 10, no fraction)");
  PASS_EQUAL (FSNFinderSizeDescription (307200, @"."), @"307 KB",
              "MI-LST-88 [O:2026-10-11 E23] kilobytes have no fraction");
  PASS_EQUAL (FSNFinderSizeDescription (1000000, @"."), @"1 MB",
              "MI-LST-89 [O:2026-10-11 E23] 1000000 is \"1 MB\", no .0");
  PASS_EQUAL (FSNFinderSizeDescription (1048576, @"."), @"1 MB",
              "MI-LST-90 [O:2026-10-11 E23] 1048576 is \"1 MB\" too");
  PASS_EQUAL (FSNFinderSizeDescription (5500000, @"."), @"5.5 MB",
              "MI-LST-91 [O:2026-10-11 E23] one decimal below 10");
  PASS_EQUAL (FSNFinderSizeDescription (5500000, @","), @"5,5 MB",
              "MI-LST-92 [O:2026-10-11 E23] with the decimal separator of the language");
  PASS_EQUAL (FSNFinderSizeDescription (4316160, @"."), @"4.3 MB",
              "MI-LST-93 [O:2026-10-11 E23] 4216 KiB allocated is \"4.3 MB\"");
  PASS_EQUAL (FSNFinderSizeDescription (12500000, @"."), @"13 MB",
              "MI-LST-94 [G: from 10 on whole numbers] no decimal from 10 on");
  PASS_EQUAL (FSNFinderSizeDescription (3500000000ULL, @"."), @"3.5 GB",
              "MI-LST-95 [G: as megabytes] gigabytes follow the same rule");

  PASS_EQUAL (FSNGroupedInteger (2560, @"."), @"2.560",
              "MI-ICN-50 [O:2026-10-11 E23] thousands are grouped with the separator of the language");
  PASS_EQUAL (FSNGroupedInteger (640, @"."), @"640", "MI-ICN-51 no separator below 1000");
  PASS_EQUAL (FSNGroupedInteger (1234567, @","), @"1,234,567", "MI-ICN-52 and for millions");

  [fm createDirectoryAtPath: dir withIntermediateDirectories: YES attributes: nil error: NULL];
  [@"x" writeToFile: file atomically: NO encoding: NSUTF8StringEncoding error: NULL];
  stat ([file fileSystemRepresentation], &st);
  PASS (FSNAllocatedSizeOfPath (file) == (unsigned long long)st.st_blocks * 512ULL
        && FSNAllocatedSizeOfPath (file) >= 1,
        "MI-LST-96 [O:2026-10-11 E23] the size of a file is the space it takes, not its length");
  PASS (FSNAllocatedSizeOfPath (@"/nonexistent-fsn") == 0, "MI-LST-97 a missing file takes nothing");
  [fm removeItemAtPath: dir error: NULL];

  [arp release];
  return 0;
}
