/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-2.0-or-later
 */

/* The strings the list and icon views look up in the framework's own
 * Localizable.strings: every language that ships has all of them, and apart
 * from the few that are the same word in that language, translated. */

#import <Foundation/Foundation.h>
#import "Testing.h"

int
main(void)
{
  NSAutoreleasePool *arp = [NSAutoreleasePool new];
  NSString *resources = @"../../FSNode/Resources";
  NSFileManager *fm = [NSFileManager defaultManager];
  NSArray *keys = [NSArray arrayWithObjects:
                     @"Today", @"Yesterday", @"%@ at %@", @"Date format", @"Time format", @"Date Created",
                     @"Date Last Opened", @"Label", @"Version", @"Comments",
                     @"Zero items", @"%@ x %@", @"1 item", @"%lu items", @"Zero bytes", @"1 byte",
                     @"%lu bytes", nil];
  /* The same word in that language. */
  NSArray *sameOk = [NSArray arrayWithObjects:
                       @"French:Version", @"German:Version", @"Spanish:1 byte",
                       @"Spanish:%lu bytes", @"Italian:1 byte", nil];
  NSArray *langs = [fm directoryContentsAtPath: resources];
  NSUInteger i, j, found = 0;

  for (i = 0; i < [langs count]; i++)
    {
      NSString *lang = [[langs objectAtIndex: i] stringByDeletingPathExtension];
      NSString *file = [[resources stringByAppendingPathComponent: [langs objectAtIndex: i]]
                         stringByAppendingPathComponent: @"Localizable.strings"];
      NSDictionary *table;

      if ([[[langs objectAtIndex: i] pathExtension] isEqualToString: @"lproj"] == NO)
        {
          continue;
        }
      found++;
      table = [NSDictionary dictionaryWithContentsOfFile: file];
      PASS (table != nil, "%s Localizable.strings parses", [lang UTF8String]);
      for (j = 0; j < [keys count]; j++)
        {
          NSString *key = [keys objectAtIndex: j];
          NSString *value = [table objectForKey: key];
          NSString *tag = [NSString stringWithFormat: @"%@:%@", lang, key];

          PASS (value != nil, "%s has \"%s\"", [lang UTF8String], [key UTF8String]);
          if ([lang isEqualToString: @"English"] == NO && value != nil
              && [sameOk containsObject: tag] == NO)
            {
              PASS ([value isEqualToString: key] == NO,
                    "%s translates \"%s\"", [lang UTF8String], [key UTF8String]);
            }
          if (value != nil && [key rangeOfString: @"%"].location != NSNotFound)
            {
              /* A translation that drops or reorders a conversion crashes
               * the formatted string. */
              PASS ([[value componentsSeparatedByString: @"%"] count]
                    == [[key componentsSeparatedByString: @"%"] count],
                    "%s keeps the conversions of \"%s\"", [lang UTF8String], [key UTF8String]);
            }
        }
    }
  PASS (found == 5, "five languages ship");

  [arp release];
  return 0;
}
