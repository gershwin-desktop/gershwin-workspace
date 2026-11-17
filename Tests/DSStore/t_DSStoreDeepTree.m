/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

/* A folder with many commented files needs a B-tree of three or more
 * levels.  -save must hand every internal node of such a tree its own
 * count + 1 children; otherwise one leaf is referenced twice and another
 * not at all, and the records in it are lost on the next load. */
#import <Foundation/Foundation.h>
#import "Testing.h"
#import "DSStore.h"
#import "DSStoreEntry.h"

#include <unistd.h>

/* About 330 bytes per record, so 1000 records fill some 80 leaves of a
 * 4 KiB page, whose pivots in turn need several internal nodes: three
 * levels. */
enum { RecordCount = 1000 };

static NSString *
commentFor(int i)
{
  return [[@"" stringByPaddingToLength: 150 withString: @"comment " startingAtIndex: 0]
           stringByAppendingFormat: @" %d", i];
}

int
main(void)
{
  NSAutoreleasePool *arp = [NSAutoreleasePool new];
  NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:
                      [NSString stringWithFormat: @"t_DSStoreDeepTree-%d.DS_Store",
                                (int)getpid()]];
  DSStore *store = [DSStore createStoreAtPath: path withEntries: nil];
  DSStore *back;
  NSUInteger missing = 0;
  int i;

  for (i = 0; i < RecordCount; i++)
    {
      [store setEntry: [DSStoreEntry commentsEntryForFile:
                          [NSString stringWithFormat: @"f%05d", i]
                                                 comments: commentFor(i)]];
    }

  START_SET("a store of three levels")
    PASS([store save], "a store of 1000 commented files is written");
    back = [DSStore storeWithPath: path];
    PASS([back load], "and loads again");
    PASS([[back entries] count] == RecordCount, "with every record");
    for (i = 0; i < RecordCount; i++)
      {
        DSStoreEntry *e = [back entryForFilename:
                              [NSString stringWithFormat: @"f%05d", i]
                                            code: @"cmmt"];

        if (e == nil || ![[e value] isEqual: commentFor(i)])
          {
            missing++;
          }
      }
    PASS(missing == 0, "each under its own name with its own comment");
  END_SET("a store of three levels")

  [[NSFileManager defaultManager] removeFileAtPath: path handler: nil];
  [arp release];
  return 0;
}
