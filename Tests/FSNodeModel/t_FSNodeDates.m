/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-2.0-or-later
 */

/* The dates a browser column or an icon's info line shows come from FSNode.
 * They read as the list view's do (Finder wording, E22), not as an English
 * "Jan 01 2020 12:00". */

#import <AppKit/AppKit.h>
#import "Testing.h"
#import "FSNode.h"
#import "FSNListView.h"

int
main(void)
{
  NSAutoreleasePool *arp = [NSAutoreleasePool new];

  /* The expected texts are English; set before the first string lookup. */
  [[NSUserDefaults standardUserDefaults]
    setObject: [NSArray arrayWithObject: @"English"] forKey: @"NSLanguages"];

  NSFileManager *fm = [NSFileManager defaultManager];
  NSString *dir = [NSTemporaryDirectory () stringByAppendingPathComponent:
                    [NSString stringWithFormat: @"t_FSNodeDates_%d", (int)getpid ()]];
  NSString *old = [dir stringByAppendingPathComponent: @"old.txt"];
  NSString *fresh = [dir stringByAppendingPathComponent: @"fresh.txt"];
  NSDate *then = [NSDate dateWithString: @"2020-01-01 12:00:00 +0000"];
  FSNode *node;
  NSString *expected, *legacy;

  [fm removeFileAtPath: dir handler: nil];
  [fm createDirectoryAtPath: dir attributes: nil];
  [@"x" writeToFile: old atomically: YES];
  [@"x" writeToFile: fresh atomically: YES];
  [fm changeFileAttributes: [NSDictionary dictionaryWithObject: then forKey: NSFileModificationDate]
                    atPath: old];

  node = [FSNode nodeWithPath: old];
  expected = [FSNListViewDataSource descriptionOfDate: [node modificationDate]
                                 relativeTo: [NSDate date]
                              relativeNames: YES];
  legacy = [[node modificationDate] descriptionWithCalendarFormat: @"%b %d %Y %H:%M"
                                                         timeZone: [NSTimeZone localTimeZone]
                                                           locale: nil];
  PASS_EQUAL ([node modDateDescription], expected,
              "MI-FSN-70 [O:2026-10-11 E22] the modification date reads as in the list view");
  PASS (![[node modDateDescription] isEqualToString: legacy],
        "MI-FSN-71 [O:2026-10-11 E22] the English month-name wording is gone");

  node = [FSNode nodeWithPath: fresh];
  PASS ([[node modDateDescription] hasPrefix: @"Today "],
        "MI-FSN-72 [O:2026-10-11 E22] a file changed today reads with the word for today");

  node = [FSNode nodeWithPath: old];
  expected = [FSNListViewDataSource descriptionOfDate: [node creationDate]
                                 relativeTo: [NSDate date]
                              relativeNames: YES];
  PASS_EQUAL ([node crDateDescription], expected,
              "MI-FSN-73 [O:2026-10-11 E22] the creation date reads the same way");

  [fm removeFileAtPath: dir handler: nil];
  [arp release];
  return 0;
}
