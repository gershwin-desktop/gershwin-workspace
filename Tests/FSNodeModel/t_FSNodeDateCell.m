/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-2.0-or-later
 */

/* A date cell too narrow for the Finder date wording (E22) drops the time
 * first and then falls back to a numeric short date. */

#import <AppKit/AppKit.h>
#import "Testing.h"
#import "FSNTextCell.h"

static CGFloat
wide(FSNTextCell *cell, NSString *s)
{
  return [s sizeWithAttributes: [NSDictionary dictionaryWithObject: [cell font]
                                                            forKey: NSFontAttributeName]].width;
}

int
main(void)
{
  NSAutoreleasePool *arp = [NSAutoreleasePool new];
  FSNTextCell *cell;

  [NSApplication sharedApplication];
  cell = [[FSNTextCell alloc] init];
  [cell setDateCell: YES];

  PASS_EQUAL ([cell cutDateTitle: @"08.10.2026 09:30" toFitWidth: wide (cell, @"08.10.2026") + 1],
              @"08.10.2026", "MI-FSN-90 [O:2026-10-11 E22] the time goes first");
  PASS_EQUAL ([cell cutDateTitle: @"1/9/26 9:30 AM" toFitWidth: wide (cell, @"1/9/26") + 1],
              @"1/9/26", "MI-FSN-91 [O:2026-10-11 E22] a 12 hour time with AM goes as a whole");
  PASS_EQUAL ([cell cutDateTitle: @"Today 9:30 AM" toFitWidth: wide (cell, @"Today") + 1],
              @"Today", "MI-FSN-92 [O:2026-10-11 E22] the day word stays when the time goes");
  PASS_EQUAL ([cell cutDateTitle: @"Heute, 09:51" toFitWidth: wide (cell, @"Heute") + 1],
              @"Heute", "MI-FSN-93 [O:2026-10-11 E22] the comma after the day word goes with the time");
  PASS_EQUAL ([cell cutDateTitle: @"08.10.2026 09:30" toFitWidth: wide (cell, @"08.10.26") + 1],
              @"08.10.26", "MI-FSN-94 [G: Finder shrinks the year] then the year is shortened");
  PASS_EQUAL ([cell cutDateTitle: @"08.10.2026 09:30" toFitWidth: wide (cell, @"0...6") ],
              @"0...6", "MI-FSN-95 [G: own fallback] too narrow even for that, the middle is dotted");

  [cell release];
  [arp release];
  return 0;
}
