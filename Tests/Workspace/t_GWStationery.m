/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-2.0-or-later
 */

/* FEATURES.md "Stationery pad": opening a pad opens a new copy of it.  The
 * copy is named like the Finder's, carries the pad's Finder information
 * except the stationery flag, and the pad stays a pad. */

#import <Foundation/Foundation.h>
#import "Testing.h"
#include "../../Workspace/GWStationery.m"

#include <unistd.h>

#define CODE(a, b, c, d) (((uint32_t)(a) << 24) | ((uint32_t)(b) << 16) \
                          | ((uint32_t)(c) << 8) | (uint32_t)(d))

int
main(void)
{
  NSAutoreleasePool *arp = [NSAutoreleasePool new];
  NSFileManager *fm = [NSFileManager defaultManager];
  NSString *dir = [NSTemporaryDirectory() stringByAppendingPathComponent:
                    [NSString stringWithFormat: @"t_GWStationery_%d", (int)getpid()]];
  NSString *pad = [dir stringByAppendingPathComponent: @"Letter.txt"];
  NSString *bare = [dir stringByAppendingPathComponent: @"Memo"];
  NSData *body = [@"Dear" dataUsingEncoding: NSUTF8StringEncoding];
  GSFileMetadata *md;
  NSString *copy;
  NSError *error = nil;

  [fm removeFileAtPath: dir handler: nil];
  [fm createDirectoryAtPath: dir attributes: nil];
  [fm createFileAtPath: pad contents: body attributes: nil];
  [fm createFileAtPath: bare contents: body attributes: nil];

  /* --- names --- */
  PASS_EQUAL([[GWStationery copyPathForStationeryAtPath: pad] lastPathComponent],
             @"Letter copy.txt", "the copy is named \"name copy.ext\"");
  PASS_EQUAL([[GWStationery copyPathForStationeryAtPath: bare] lastPathComponent],
             @"Memo copy", "without an extension it is \"name copy\"");
  [fm createFileAtPath: [dir stringByAppendingPathComponent: @"Letter copy.txt"]
              contents: body attributes: nil];
  PASS_EQUAL([[GWStationery copyPathForStationeryAtPath: pad] lastPathComponent],
             @"Letter copy 2.txt", "an existing copy is not overwritten: \"name copy 2.ext\"");
  [fm removeFileAtPath: [dir stringByAppendingPathComponent: @"Letter copy.txt"] handler: nil];

  /* --- the copy --- */
  md = [[GSFileMetadata new] autorelease];
  [md setTypeCode: CODE('T','E','X','T')];
  [md setCreatorCode: CODE('t','t','x','t')];
  [md setStationery: YES];
  [md setFinderComment: @"template"];
  PASS([md writeToFileAtPath: pad error: &error], "the pad's Finder information is written");
  [GSFileMetadata invalidateAllCachedMetadata];

  copy = [GWStationery makeCopyOfStationeryAtPath: pad error: &error];
  PASS_EQUAL([copy lastPathComponent], @"Letter copy.txt", "a copy is made next to the pad");
  PASS_EQUAL([NSData dataWithContentsOfFile: copy], body, "the copy has the pad's contents");
  [GSFileMetadata invalidateAllCachedMetadata];
  md = [GSFileMetadata metadataForFileAtPath: copy];
  PASS(md != nil && ![md isStationery], "the copy is not a stationery pad");
  PASS(md != nil && [md creatorCode] == CODE('t','t','x','t')
       && [md typeCode] == CODE('T','E','X','T'),
       "the copy keeps type and creator, so it opens in the pad's application");
  PASS_EQUAL([md finderComment], @"template", "the copy keeps the comment");
  PASS([[GSFileMetadata metadataForFileAtPath: pad] isStationery], "the pad stays a pad");

  /* --- failure is reported, not hidden --- */
  error = nil;
  PASS([GWStationery makeCopyOfStationeryAtPath:
          [dir stringByAppendingPathComponent: @"missing"] error: &error] == nil
       && error != nil,
       "a pad that cannot be copied gives nil and an error");

  [fm removeFileAtPath: dir handler: nil];
  [arp release];
  return 0;
}
