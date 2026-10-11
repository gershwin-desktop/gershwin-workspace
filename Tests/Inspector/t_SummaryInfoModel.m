/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

#import <Foundation/Foundation.h>
#import "Testing.h"
#include "../../Inspector/SummaryInfoModel.m"

static void writeBytes(NSString *path, NSUInteger n)
{
  NSMutableData *d = [NSMutableData dataWithLength: n];

  [d writeToFile: path atomically: NO];
}

int main(void)
{
  NSAutoreleasePool *arp = [NSAutoreleasePool new];
  NSFileManager *fm = [NSFileManager defaultManager];
  NSString *root = [NSTemporaryDirectory() stringByAppendingPathComponent:
                      [NSString stringWithFormat: @"gwsummary-%d", (int)getpid()]];
  NSString *dir = [root stringByAppendingPathComponent: @"folder"];
  NSString *a = [root stringByAppendingPathComponent: @"a.txt"];
  NSString *b = [root stringByAppendingPathComponent: @"b.txt"];
  NSString *c = [root stringByAppendingPathComponent: @"c.pdf"];
  SummaryInfoModel *m;
  NSArray *sel;

  [fm removeFileAtPath: root handler: nil];
  [fm createDirectoryAtPath: dir withIntermediateDirectories: YES attributes: nil error: NULL];
  writeBytes(a, 100);
  writeBytes(b, 200);
  writeBytes(c, 1000);
  writeBytes([dir stringByAppendingPathComponent: @"inner.bin"], 5000);
  [fm createSymbolicLinkAtPath: [dir stringByAppendingPathComponent: @"link"]
           withDestinationPath: dir error: NULL];

  sel = [NSArray arrayWithObjects: a, b, c, dir, nil];
  m = [[SummaryInfoModel alloc] initWithPaths: sel];
  [m compute];
  PASS([m itemCount] == 4 && [m folderCount] == 1, "counts items and folders");
  PASS([m totalBytes] == 6300, "total size includes the content of folders, not links");
  PASS([[[m kinds] objectForKey: @"TXT file"] intValue] == 2
       && [[[m kinds] objectForKey: @"PDF file"] intValue] == 1
       && [[[m kinds] objectForKey: @"Folder"] intValue] == 1, "groups items by kind");
  PASS([m commonLabel] == 0, "items without a label share the None label");
  PASS([m lockedState] == SummaryStateNone, "unlocked items report not locked");
  PASS([m finished], "finished after compute");
  [m release];

  m = [[SummaryInfoModel alloc] initWithPaths: sel];
  [m cancel];
  [m compute];
  PASS([m finished] == NO && [m itemCount] == 0, "a cancelled run stops at once");
  [m release];

  PASS_EQUAL([SummaryInfoModel descriptionForByteCount: 12], @"12 bytes", "small size");
  /* the grouping separator follows the user's locale */
  {
    NSString *big = [SummaryInfoModel descriptionForByteCount: 1500000];

    PASS([big hasPrefix: @"1.5 MB ("] && [big hasSuffix: @" bytes)"], "large size");
  }

  [fm removeFileAtPath: root handler: nil];
  [arp release];
  return 0;
}
