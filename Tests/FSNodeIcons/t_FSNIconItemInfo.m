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

  PASS_EQUAL([FSNIcon itemInfoForItemCount: 0], @"Zero items",
             "MI-ICN-1 [O:2026-10-11 E23, German \"Keine Objekte\"] an empty folder reads \"Zero items\" [G: English]");
  PASS_EQUAL([FSNIcon itemInfoForItemCount: 1], @"1 item",
             "MI-ICN-2 [O:2026-10-11 E23] a folder with one entry reads \"1 item\", singular");
  PASS_EQUAL([FSNIcon itemInfoForItemCount: 12], @"12 items",
             "MI-ICN-3 [O:2026-10-11 E23] a folder with twelve entries reads \"12 items\"");

  PASS_EQUAL([FSNIcon itemInfoForPixelWidth: 640 height: 480 groupingSeparator: @"."],
             @"640 \u00D7 480",
             "MI-ICN-10 [O:2026-10-11 E23] an image reads \"width x height\" in pixels with the multiplication sign");
  PASS_EQUAL([FSNIcon itemInfoForPixelWidth: 2560 height: 1600 groupingSeparator: @"."],
             @"2.560 \u00D7 1.600",
             "MI-ICN-53 [O:2026-10-11 E23] the pixel counts have the thousands separator of the language");

  [arp release];
  return 0;
}
