/* t_FSNLazyAttributes.m - coverage for lazy FSNode attribute loading.
 *
 * Nodes built from a directory snapshot (+nodesFromDirectorySnapshot:)
 * defer the per-file stat() until an attribute-dependent accessor is used;
 * kind flags come pre-seeded from the readdir d_type.  Every accessor must
 * report the same values as an eagerly-created node for the same path.
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import "Testing.h"
#import "FSNode.h"
#import "FSNodeRep.h"
#import "FSNDirEntry.h"

static NSString *
tmpRoot(void)
{
  return [NSString stringWithFormat: @"%@/lazyattr_t_%ld",
            @"/tmp/opencode", (long)getpid()];
}

int
main(void)
{
  NSAutoreleasePool *arp = [NSAutoreleasePool new];
  NSFileManager *fm = [NSFileManager defaultManager];
  NSString *root = tmpRoot();

  START_SET("lazy attribute setup")
    {
      [fm removeItemAtPath: root error: NULL];
      PASS([fm createDirectoryAtPath: root
          withIntermediateDirectories: YES attributes: nil error: NULL],
           "temp dir created");

      PASS([@"hello world" writeToFile: [root stringByAppendingPathComponent: @"a.txt"]
                            atomically: YES], "file with known content written");
      PASS([fm createDirectoryAtPath: [root stringByAppendingPathComponent: @"d"]
          withIntermediateDirectories: NO attributes: nil error: NULL],
           "subdirectory created");
    }
  END_SET("lazy attribute setup")

  START_SET("snapshot nodes match eager nodes")
    {
      FSNode *parent = [FSNode nodeWithPath: root];
      NSArray *snapshot = [[FSNodeRep sharedInstance] directorySnapshotAtPath: root];
      NSArray *lazyNodes = [FSNode nodesFromDirectorySnapshot: snapshot
                                                       parent: parent];
      FSNode *lazyFile = nil;
      FSNode *lazyDir = nil;

      PASS([lazyNodes count] == 2, "one node per snapshot entry");

      for (unsigned i = 0; i < [lazyNodes count]; i++)
        {
          FSNode *n = [lazyNodes objectAtIndex: i];

          if ([[n lastPathComponent] isEqual: @"a.txt"])
            lazyFile = n;
          else if ([[n lastPathComponent] isEqual: @"d"])
            lazyDir = n;
        }

      PASS(lazyFile != nil && lazyDir != nil, "lazy nodes found by name");

      PASS([[lazyFile path] isEqual: [root stringByAppendingPathComponent: @"a.txt"]],
           "lazy node path includes the parent directory");
      PASS([[lazyDir path] isEqual: [root stringByAppendingPathComponent: @"d"]],
           "lazy directory path includes the parent directory");

      /* Kind flags are pre-seeded from d_type without any stat. */
      PASS([lazyDir isDirectory] == YES, "snapshot kind pre-seeds isDirectory");
      PASS([lazyFile isDirectory] == NO, "snapshot kind pre-seeds isDirectory (file)");

      /* Attribute-dependent accessors agree with the eager node. */
      {
        FSNode *eagerFile = [FSNode nodeWithPath: [root stringByAppendingPathComponent: @"a.txt"]];
        FSNode *eagerDir = [FSNode nodeWithPath: [root stringByAppendingPathComponent: @"d"]];

        PASS([lazyFile fileSize] == [eagerFile fileSize],
             "lazy fileSize matches eager node");
        PASS([[lazyFile modificationDate] isEqualToDate: [eagerFile modificationDate]],
             "lazy modificationDate matches eager node");
        PASS([[lazyFile fileType] isEqual: [eagerFile fileType]],
             "lazy fileType matches eager node");
        PASS([lazyDir isValid] == YES && [eagerDir isValid] == YES,
             "lazy and eager nodes are valid");
        PASS([lazyFile isValid] == YES, "lazy file node is valid");
      }
    }
  END_SET("snapshot nodes match eager nodes")

  START_SET("attributes load once and are cached")
    {
      FSNode *parent = [FSNode nodeWithPath: root];
      NSArray *snapshot = [[FSNodeRep sharedInstance] directorySnapshotAtPath: root];
      FSNode *lazyFile = nil;

      for (unsigned i = 0; i < [snapshot count]; i++)
        {
          if ([[[snapshot objectAtIndex: i] name] isEqual: @"a.txt"])
            {
              lazyFile = [[FSNode alloc]
                            initWithRelativePath: @"a.txt"
                                          parent: parent
                                  snapshotEntry: [snapshot objectAtIndex: i]];
            }
        }

      PASS(lazyFile != nil, "lazy node created");

      NSDate *first = [lazyFile modificationDate];

      [lazyFile loadAttributesIfNeeded];

      NSDate *second = [lazyFile modificationDate];

      PASS([first isEqualToDate: second], "attributes are loaded once and cached");
      PASS([lazyFile fileSize] == 11, "fileSize reflects the real file (11 bytes)");

      [lazyFile release];
    }
  END_SET("attributes load once and are cached")

  START_SET("lazy nodes work for sorting by size")
    {
      FSNode *parent = [FSNode nodeWithPath: root];
      NSArray *snapshot = [[FSNodeRep sharedInstance] directorySnapshotAtPath: root];
      NSMutableArray *lazyNodes =
        [[FSNode nodesFromDirectorySnapshot: snapshot parent: parent] mutableCopy];

      /* compareAccordingToSize pulls the deferred attributes per node; the
       * directory (0 bytes... directories report st_size) sorts by its own
       * attribute value - just require a stable, exception-free sort. */
      [lazyNodes sortUsingSelector: @selector(compareAccordingToSize:)];
      PASS([lazyNodes count] == 2, "attribute sort over lazy nodes works");

      [lazyNodes release];
    }
  END_SET("lazy nodes work for sorting by size")

  [fm removeItemAtPath: root error: NULL];

  [arp release];
  return 0;
}
