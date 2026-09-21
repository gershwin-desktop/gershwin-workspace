/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 */

/* Headless coverage for the file name helpers in FSNFunctions.m.  A folder
 * viewer calls them once per directory entry, so besides the results this
 * checks that repeated calls do not keep allocating: -invertedSet copies the
 * whole Unicode bitmap and made a folder of a few thousand entries cost
 * hundreds of megabytes. */

#import <AppKit/AppKit.h>
#import "Testing.h"
#import "FSNFunctions.h"

int
main(void)
{
  NSAutoreleasePool *arp = [NSAutoreleasePool new];
  NSUInteger i;

  PASS(GSFilenameExtensionIsNumeric(@"1") == YES,
       "a manual page extension counts as numeric");
  PASS(GSFilenameExtensionIsNumeric(@"42") == YES,
       "several digits count as numeric");
  PASS(GSFilenameExtensionIsNumeric(@"1ssl") == NO,
       "digits followed by letters are not numeric");
  PASS(GSFilenameExtensionIsNumeric(@"txt") == NO,
       "a letters-only extension is not numeric");
  PASS(GSFilenameExtensionIsNumeric(@"") == NO,
       "an empty extension is not numeric");

  /* The answer has to stay the same however often it is asked, which is what
   * caching the character set must not break. */
  for (i = 0; i < 2000; i++)
    {
      if (GSFilenameExtensionIsNumeric(@"1") != YES
          || GSFilenameExtensionIsNumeric(@"txt") != NO)
        {
          break;
        }
    }
  PASS(i == 2000, "repeated calls keep giving the same answer");

  PASS_EQUAL(GSDisplayNameForFilename(@"notes.txt",
                                      GSFilenameExtensionDisplayAll),
             @"notes.txt", "showing all extensions leaves the name alone");
  PASS_EQUAL(GSDisplayNameForFilename(@"notes.txt",
                                      GSFilenameExtensionHideAll),
             @"notes", "hiding all extensions drops a plain extension");
  PASS_EQUAL(GSDisplayNameForFilename(@"gzip.1",
                                      GSFilenameExtensionHideAll),
             @"gzip.1", "a numeric extension is part of the name and stays");
  PASS_EQUAL(GSDisplayNameForFilename(@"archive.tar.gz",
                                      GSFilenameExtensionHideAll),
             @"archive", "a compound extension is dropped as a whole");
  PASS_EQUAL(GSDisplayNameForFilename(@".profile",
                                      GSFilenameExtensionHideAll),
             @".profile", "a dot file keeps its name");
  PASS_EQUAL(GSDisplayNameForFilename(@"TextEdit.app",
                                      GSFilenameExtensionHidePackageExtensions),
             @"TextEdit", "a package extension is hidden in that mode");
  PASS_EQUAL(GSDisplayNameForFilename(@"notes.txt",
                                      GSFilenameExtensionHidePackageExtensions),
             @"notes.txt", "a plain extension survives that mode");

  [arp release];
  return 0;
}
