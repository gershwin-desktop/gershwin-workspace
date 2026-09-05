/* t_FSNDirectorySnapshot.m - coverage for FSNodeRep directory snapshots.
 *
 * -directorySnapshotAtPath: is the one-readdir-pass listing (name + d_type
 * kind) that lazy-loading viewers use to lay out cells without a per-file
 * stat().  It must return exactly the same filtered name set as the classic
 * -directoryContentsAtPath:, plus reliable dir/plain/link kinds.
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import "Testing.h"
#import "FSNodeRep.h"
#import "FSNDirEntry.h"

static NSString *
tmpRoot(void)
{
  return [NSString stringWithFormat: @"%@/snapshot_t_%ld",
            @"/tmp/opencode", (long)getpid()];
}

int
main(void)
{
  NSAutoreleasePool *arp = [NSAutoreleasePool new];
  NSFileManager *fm = [NSFileManager defaultManager];
  FSNodeRep *rep = [FSNodeRep sharedInstance];
  NSString *root = tmpRoot();

  START_SET("snapshot setup")
    {
      [fm removeItemAtPath: root error: NULL];
      PASS([fm createDirectoryAtPath: root
          withIntermediateDirectories: YES attributes: nil error: NULL],
           "temp dir created");

      PASS([@"data" writeToFile: [root stringByAppendingPathComponent: @"zfile.txt"]
                     atomically: YES], "plain file written");
      PASS([fm createDirectoryAtPath: [root stringByAppendingPathComponent: @"adir"]
          withIntermediateDirectories: NO attributes: nil error: NULL],
           "subdirectory created");
      PASS([fm createSymbolicLinkAtPath: [root stringByAppendingPathComponent: @"alink"]
                     withDestinationPath: @"zfile.txt" error: NULL],
           "symlink created");
      PASS([@"x" writeToFile: [root stringByAppendingPathComponent: @"._hidden"]
                  atomically: YES], "internal metadata file written");
      PASS([@"x" writeToFile: [root stringByAppendingPathComponent: @".DS_Store"]
                  atomically: YES], ".DS_Store written");
    }
  END_SET("snapshot setup")

  START_SET("snapshot matches directoryContentsAtPath")
    {
      NSArray *names = [rep directoryContentsAtPath: root];
      NSArray *snapshot = [rep directorySnapshotAtPath: root];
      NSMutableArray *snapNames = [NSMutableArray array];

      for (unsigned i = 0; i < [snapshot count]; i++)
        {
          [snapNames addObject: [[snapshot objectAtIndex: i] name]];
        }

      PASS([snapshot count] == [names count],
           "snapshot and listing have the same entry count");

      PASS([snapNames containsObject: @"zfile.txt"]
           && [snapNames containsObject: @"adir"]
           && [snapNames containsObject: @"alink"],
           "visible entries are in the snapshot");

      PASS([snapNames containsObject: @"._hidden"] == NO,
           "._* files are filtered from the snapshot");
      PASS([snapNames containsObject: @".DS_Store"] == NO,
           ".DS_Store is filtered from the snapshot");

      PASS([names count] == 3, "filtering matches the classic listing");
    }
  END_SET("snapshot matches directoryContentsAtPath")

  START_SET("snapshot kinds from d_type")
    {
      NSArray *snapshot = [rep directorySnapshotAtPath: root];
      FSNDirEntry *dirEntry = nil;
      FSNDirEntry *plainEntry = nil;
      FSNDirEntry *linkEntry = nil;

      for (unsigned i = 0; i < [snapshot count]; i++)
        {
          FSNDirEntry *e = [snapshot objectAtIndex: i];

          if ([[e name] isEqual: @"adir"])
            dirEntry = e;
          else if ([[e name] isEqual: @"zfile.txt"])
            plainEntry = e;
          else if ([[e name] isEqual: @"alink"])
            linkEntry = e;
        }

      PASS(dirEntry != nil && [dirEntry kind] == FSNDirEntryKindDirectory,
           "subdirectory has the directory kind");
      PASS(plainEntry != nil && [plainEntry kind] == FSNDirEntryKindPlain,
           "regular file has the plain kind");
      PASS(linkEntry != nil && [linkEntry kind] == FSNDirEntryKindLink,
           "symlink has the link kind");
    }
  END_SET("snapshot kinds from d_type")

  START_SET("snapshot of missing directory")
    {
      NSArray *snapshot = [rep directorySnapshotAtPath:
                                    [root stringByAppendingPathComponent: @"nope"]];

      PASS([snapshot count] == 0, "missing directory yields an empty snapshot");
    }
  END_SET("snapshot of missing directory")

  [fm removeItemAtPath: root error: NULL];

  [arp release];
  return 0;
}
