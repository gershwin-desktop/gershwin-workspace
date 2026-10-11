/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 */
#import <Foundation/Foundation.h>
#import "Testing.h"
#include <unistd.h>
#import "GSFileMetadata.h"
#import "GMDSFinderAttributes.h"

/* The values stored under one key, in order. */
static NSArray *
valuesFor(NSArray *rows, NSString *key)
{
  NSMutableArray *out = [NSMutableArray array];
  NSDictionary *row;

  for (row in rows) {
    if ([[row objectForKey: @"key"] isEqual: key]) {
      [out addObject: [row objectForKey: @"attribute"]];
    }
  }
  return out;
}

int main(void)
{
  NSAutoreleasePool *arp = [NSAutoreleasePool new];
  NSFileManager *fm = [NSFileManager defaultManager];
  NSString *dir = [NSTemporaryDirectory() stringByAppendingPathComponent:
                   [NSString stringWithFormat: @"t_FinderAttributes-%d",
                    (int)getpid()]];
  NSString *file = [dir stringByAppendingPathComponent: @"red.txt"];
  NSString *plain = [dir stringByAppendingPathComponent: @"plain.txt"];
  NSArray *rows;
  GSFileMetadata *md;
  NSArray *want;

  /* --- no metadata at all: label 0 is indexed (Spotlight reports 0), no tags */
  rows = [GMDSFinderAttributes attributesForMetadata: nil];
  want = [NSArray arrayWithObject: @"0"];
  PASS_EQUAL(valuesFor(rows, GMDSFSLabelKey), want,
             "no metadata gives label 0");
  PASS([valuesFor(rows, GMDSUserTagsKey) count] == 0, "no metadata gives no tags");

  /* --- the label is Finder's colour number, not the menu order (E24) */
  md = [[[GSFileMetadata alloc] init] autorelease];
  [md setLabelNumber: GSFileLabelRed];
  rows = [GMDSFinderAttributes attributesForMetadata: md];
  want = [NSArray arrayWithObject: @"6"];
  PASS_EQUAL(valuesFor(rows, GMDSFSLabelKey), want, "Red is Finder colour 6");

  md = [[[GSFileMetadata alloc] init] autorelease];
  [md setLabelNumber: GSFileLabelGrey];
  rows = [GMDSFinderAttributes attributesForMetadata: md];
  want = [NSArray arrayWithObject: @"1"];
  PASS_EQUAL(valuesFor(rows, GMDSFSLabelKey), want, "Grey is Finder colour 1");

  md = [[[GSFileMetadata alloc] init] autorelease];
  [md setLabelNumber: GSFileLabelOrange];
  rows = [GMDSFinderAttributes attributesForMetadata: md];
  want = [NSArray arrayWithObject: @"7"];
  PASS_EQUAL(valuesFor(rows, GMDSFSLabelKey), want,
             "Orange is Finder colour 7");

  /* --- tags: one row per tag, the colour number suffix of later Finders
   * is not part of the name, duplicates collapse */
  md = [[[GSFileMetadata alloc] init] autorelease];
  [md setUserTags: [NSArray arrayWithObjects: @"Project", @"Red\n6",
                    @"Project", @"Quarterly report", nil]];
  rows = [GMDSFinderAttributes attributesForMetadata: md];
  want = [NSArray arrayWithObjects: @"Project", @"Red", @"Quarterly report",
          nil];
  PASS_EQUAL(valuesFor(rows, GMDSUserTagsKey), want,
             "one row per distinct tag name");
  want = [NSArray arrayWithObject: @"6"];
  PASS_EQUAL(valuesFor(rows, GMDSFSLabelKey), want,
             "a colour tag alone sets the label");

  /* --- from the file system, through what Workspace writes */
  [fm removeFileAtPath: dir handler: nil];
  PASS([fm createDirectoryAtPath: dir attributes: nil], "temporary folder");
  PASS([fm createFileAtPath: file contents: [NSData data] attributes: nil],
       "file");
  PASS([fm createFileAtPath: plain contents: [NSData data] attributes: nil],
       "plain file");
  md = [[[GSFileMetadata alloc] init] autorelease];
  [md setLabelNumber: GSFileLabelRed];
  [md setUserTags: [NSArray arrayWithObjects: @"Red", @"Taxes", nil]];
  PASS([md writeToFileAtPath: file error: NULL], "metadata written");
  rows = [GMDSFinderAttributes attributesForPath: file];
  want = [NSArray arrayWithObject: @"6"];
  PASS_EQUAL(valuesFor(rows, GMDSFSLabelKey), want, "label read from the file");
  want = [NSArray arrayWithObjects: @"Red", @"Taxes", nil];
  PASS_EQUAL(valuesFor(rows, GMDSUserTagsKey), want, "tags read from the file");
  rows = [GMDSFinderAttributes attributesForPath: plain];
  want = [NSArray arrayWithObject: @"0"];
  PASS_EQUAL(valuesFor(rows, GMDSFSLabelKey), want, "unlabelled file is 0");

  /* The label changes later: reading again must show it (no stale cache). */
  md = [GSFileMetadata metadataForFileAtPath: file forceSidecar: NO];
  [md setLabelNumber: GSFileLabelGreen];
  [md setUserTags: nil];
  PASS([md writeToFileAtPath: file error: NULL], "label changed");
  rows = [GMDSFinderAttributes attributesForPath: file];
  want = [NSArray arrayWithObject: @"2"];
  PASS_EQUAL(valuesFor(rows, GMDSFSLabelKey), want,
             "a changed label is read again");

  [fm removeFileAtPath: dir handler: nil];
  [arp release];
  return 0;
}
