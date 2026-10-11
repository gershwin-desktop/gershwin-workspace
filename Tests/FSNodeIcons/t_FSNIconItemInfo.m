/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 */

/* The second line Finder's "Show item info" puts under an icon name: an item
 * count for a folder, a size for a file, the pixel size for an image. */

#import <AppKit/AppKit.h>
#import "Testing.h"
#import "FSNIcon.h"

int
main(void)
{
  NSAutoreleasePool *arp = [NSAutoreleasePool new];
  /* The expected texts are English; the framework's strings follow the
   * language of whoever runs the suite.  Set before the first lookup. */
  [[NSUserDefaults standardUserDefaults]
    setObject: [NSArray arrayWithObject: @"English"] forKey: @"NSLanguages"];

  PASS_EQUAL([FSNIcon itemInfoForItemCount: 0], @"0 items",
             "MI-ICN-1 an empty folder reads \"0 items\"");
  PASS_EQUAL([FSNIcon itemInfoForItemCount: 1], @"1 item",
             "MI-ICN-2 a folder with one entry reads \"1 item\", singular");
  PASS_EQUAL([FSNIcon itemInfoForItemCount: 12], @"12 items",
             "MI-ICN-3 a folder with twelve entries reads \"12 items\"");

  PASS_EQUAL([FSNIcon itemInfoForByteSize: 0], @"Zero bytes",
             "MI-ICN-4 an empty file reads \"Zero bytes\"");
  PASS_EQUAL([FSNIcon itemInfoForByteSize: 1], @"1 byte",
             "MI-ICN-5 one byte is singular");
  PASS_EQUAL([FSNIcon itemInfoForByteSize: 999], @"999 bytes",
             "MI-ICN-6 sizes below 1000 are counted in bytes (decimal units)");
  PASS_EQUAL([FSNIcon itemInfoForByteSize: 4096], @"4 KB",
             "MI-ICN-7 kilobytes are decimal and shown without a fraction");
  PASS_EQUAL([FSNIcon itemInfoForByteSize: 1234567], @"1.2 MB",
             "MI-ICN-8 megabytes are decimal with one fraction digit");
  PASS_EQUAL([FSNIcon itemInfoForByteSize: 3500000000ULL], @"3.50 GB",
             "MI-ICN-9 gigabytes are decimal with two fraction digits");

  PASS_EQUAL([FSNIcon itemInfoForPixelWidth: 640 height: 480], @"640 x 480",
             "MI-ICN-10 an image reads \"width x height\" in pixels");

  [arp release];
  return 0;
}
