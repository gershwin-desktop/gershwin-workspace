/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

#import <Foundation/Foundation.h>
#import "Testing.h"
#import "FSNode.h"
#import "FSNKindNames.h"
#include "../../Inspector/SummaryInfoModel.m"

/* Stands for Workspace: records what it was asked and labels like it does. */
@interface StubWriter : NSObject <SummaryInfoLabelWriter>
{
@public
  NSArray *paths;
  NSInteger label;
  id nodeView;
}
@end
@implementation StubWriter
- (NSUInteger)setLabelNumber:(NSInteger)l forPaths:(NSArray *)p nodeView:(id)v
{
  NSUInteger i, failures = 0;

  paths = [p retain];
  label = l;
  nodeView = v;
  for (i = 0; i < [p count]; i++)
    {
      FinderInfoModel *info = [FinderInfoModel modelForPath: [p objectAtIndex: i]];

      [info setLabelNumber: l];
      if (![info write: NULL])
        {
          failures++;
        }
    }
  return failures;
}
@end

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
  /* The kinds are the ones the list view's Kind column shows. */
  {
    NSString *txt = [[FSNode nodeWithPath: a] typeDescription];
    NSString *pdf = [[FSNode nodeWithPath: c] typeDescription];
    NSString *folder = [[FSNode nodeWithPath: dir] typeDescription];

    PASS([[[m kinds] objectForKey: txt] intValue] == 2
         && [[[m kinds] objectForKey: pdf] intValue] == 1
         && [[[m kinds] objectForKey: folder] intValue] == 1, "groups items by the list view kind");
    PASS([[[m kinds] objectForKey: txt] intValue] == 2 && ![txt hasSuffix: @" file"]
         , "a kind is a description, not EXT file");
    PASS_EQUAL(pdf, [FSNKindNames kindForExtension: @"pdf"], "a PDF is named from the kind table");
    PASS(![pdf hasPrefix: @"NS"], "a pasteboard type is not shown as the kind");
  }
  PASS([m commonLabel] == 0, "items without a label share the None label");
  PASS([m lockedState] == SummaryStateNone, "unlocked items report not locked");
  PASS([m finished], "finished after compute");

  /* One label for all items; Mixed when they differ. */
  StubWriter *writer = [StubWriter new];

  PASS([m applyLabel: 3 writer: writer] == 0, "label applied to every item without failure");
  PASS(writer->label == 3 && [writer->paths isEqual: sel] && writer->nodeView == nil,
       "the window hands the label and all paths to the one Workspace writer");
  PASS([m commonLabel] == 3, "model reports the label it applied");
  PASS([[FinderInfoModel modelForPath: a] labelNumber] == 3
       && [[FinderInfoModel modelForPath: dir] labelNumber] == 3, "label reaches each file and folder");
  [m release];
  {
    FinderInfoModel *one = [FinderInfoModel modelForPath: b];

    [one setLabelNumber: 1];
    [one write: NULL];
  }
  m = [[SummaryInfoModel alloc] initWithPaths: sel];
  [m compute];
  PASS([m commonLabel] == -1, "differing labels are Mixed");
  [m release];

  /* A file nobody ever labeled has no metadata at all; it is None, not absent. */
  {
    NSString *e = [root stringByAppendingPathComponent: @"e.txt"];

    writeBytes(e, 10);
    m = [[SummaryInfoModel alloc] initWithPaths: [NSArray arrayWithObjects: a, e, nil]];
    [m compute];
    PASS([m commonLabel] == -1, "a labeled and an unlabeled file are Mixed");
    [m release];
  }

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
