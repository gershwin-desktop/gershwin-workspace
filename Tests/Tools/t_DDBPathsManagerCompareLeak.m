/* t_DDBPathsManagerCompareLeak.m - ObjectTesting coverage for
 * DDBPathsManager's B-tree delegate leaking a retain on its dummy search
 * key on every comparison where that key is the first (akey) argument.
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */
#import <Foundation/Foundation.h>
#import "Testing.h"

#include <unistd.h>

#include "../../Tools/ddbd/DDBPathsManager.m"

/* DDBPathsManager.m calls these three ddbd.m globals (ddbd.h declares
 * them). ddbd.m itself is the DO server: it has its own main() and starts
 * threads, so it cannot be linked into a test tool; this test supplies
 * the same, trivial behavior directly instead. pathsep() is the only one
 * DDBPathsManager's init/addPath/removePath actually call. */
NSString *
pathsep(void)
{
  return @"/";
}

BOOL
subpath(NSString *p1, NSString *p2)
{
  return NO;
}

NSString *
removePrefix(NSString *path, NSString *prefix)
{
  return path;
}

/* dummyPaths[]/dummyOffsets[] are @protected ivars; a category's methods
 * have the same access as the class's own. Used to drive
 * -compareNodeKey:withKey: directly with the dummy key as the FIRST
 * (akey) argument: DBKBTreeNode's binary search (indexForKey:existing:,
 * insertKey:), the only caller today, always places the search key
 * second (bkey) - confirmed by instrumenting the unpatched method and
 * running a real -addPath: - so ordinary add/lookup/remove traffic never
 * actually reaches the leaking branch. -compareNodeKey:withKey: is
 * still a general two-key comparator (the DBKBTreeDelegate contract, and
 * the sibling DDBDirsManager.m's own implementation treats both argument
 * positions symmetrically), so this exercises the real, reachable-in-
 * principle defect directly rather than relying on today's one caller
 * continuing to favor bkey. */
@interface DDBPathsManager (SprintToolsTesting)
- (void)test_setDummyPath0:(DDBPath *)path;
- (void)test_setDummyPath1:(DDBPath *)path;
- (NSNumber *)test_dummyOffset0;
- (NSNumber *)test_dummyOffset1;
@end

@implementation DDBPathsManager (SprintToolsTesting)

- (void)test_setDummyPath0:(DDBPath *)path
{
  ASSIGN (dummyPaths[0], path);
}

- (void)test_setDummyPath1:(DDBPath *)path
{
  ASSIGN (dummyPaths[1], path);
}

- (NSNumber *)test_dummyOffset0
{
  return dummyOffsets[0];
}

- (NSNumber *)test_dummyOffset1
{
  return dummyOffsets[1];
}

@end

int
main(void)
{
  NSAutoreleasePool *arp = [NSAutoreleasePool new];
  NSFileManager *fm = [NSFileManager defaultManager];
  NSString *base = [NSTemporaryDirectory() stringByAppendingPathComponent:
    [NSString stringWithFormat: @"t_ddbpaths_%d", (int)getpid()]];
  DDBPathsManager *mgr;
  DDBPath *added;

  [fm removeItemAtPath: base error: NULL];
  PASS([fm createDirectoryAtPath: base withIntermediateDirectories: YES
             attributes: nil error: NULL],
       "database directory is created");

  mgr = [[DDBPathsManager alloc] initWithBasePath: base];
  PASS(mgr != nil, "DDBPathsManager initializes headless, with no display");

  /* Ordinary usage still works and does not crash; this does not by
   * itself discriminate the leak (see the comment above the category:
   * today's only caller never puts the dummy key in the akey position),
   * so it is a smoke check, not proof either way. */
  added = [mgr addPath: @"/one"];
  PASS(added != nil, "addPath: stores a path without raising");

  /* This is the assertion that actually distinguishes the bug: drive the
   * delegate method directly with the dummy key as akey. */
  {
    DDBPath *probe0 = [[DDBPath alloc] initForPath: @"/probe0"];
    DDBPath *probe1 = [[DDBPath alloc] initForPath: @"/probe1"];
    NSNumber *offset0 = [mgr test_dummyOffset0];
    NSNumber *offset1 = [mgr test_dummyOffset1];

    [mgr test_setDummyPath0: probe0];
    [mgr test_setDummyPath1: probe1];
    RELEASE (probe0);
    RELEASE (probe1);

    PASS([probe0 retainCount] == 1,
         "the probe installed as dummyPaths[0] starts out owned only by "
         "the manager's ivar");

    [mgr compareNodeKey: offset0 withKey: offset1];

    PASS([probe0 retainCount] == 1,
         "comparing with the dummy key as the first (akey) argument does "
         "not leave an extra retain on the path it stands for");
  }

  RELEASE (mgr);
  [fm removeItemAtPath: base error: NULL];

  RELEASE (arp);
  return 0;
}
