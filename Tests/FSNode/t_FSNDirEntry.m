/* t_FSNDirEntry.m - headless coverage for the readdir snapshot entry class.
 *
 * FSNDirEntry is a Foundation-only value class (name + d_type kind) used by
 * FSNodeRep's directory snapshots to give lazy-loading viewers directory
 * information without a per-file stat().
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

#import <Foundation/Foundation.h>
#import "Testing.h"
#include "../../FSNode/FSNDirEntry.m"

int
main(void)
{
  NSAutoreleasePool *arp = [NSAutoreleasePool new];

  START_SET("FSNDirEntry basics")
    {
      FSNDirEntry *dir = [[FSNDirEntry alloc] initWithName: @"Folder"
                                                      kind: FSNDirEntryKindDirectory];
      PASS([[dir name] isEqual: @"Folder"], "name is stored");
      PASS([dir kind] == FSNDirEntryKindDirectory, "directory kind is stored");
      PASS([dir hasUnknownKind] == NO, "directory kind is not unknown");
      [dir release];

      FSNDirEntry *plain = [[FSNDirEntry alloc] initWithName: @"file.txt"
                                                        kind: FSNDirEntryKindPlain];
      PASS([plain kind] == FSNDirEntryKindPlain, "plain kind is stored");
      PASS([plain hasUnknownKind] == NO, "plain kind is not unknown");
      [plain release];

      FSNDirEntry *link = [[FSNDirEntry alloc] initWithName: @"lnk"
                                                       kind: FSNDirEntryKindLink];
      PASS([link kind] == FSNDirEntryKindLink, "link kind is stored");
      [link release];

      FSNDirEntry *unknown = [[FSNDirEntry alloc] initWithName: @"weird"
                                                          kind: FSNDirEntryKindUnknown];
      PASS([unknown kind] == FSNDirEntryKindUnknown, "unknown kind is stored");
      PASS([unknown hasUnknownKind] == YES, "DT_UNKNOWN maps to hasUnknownKind");
      [unknown release];
    }
  END_SET("FSNDirEntry basics")

  START_SET("FSNDirEntry ordering")
    {
      FSNDirEntry *a = [[FSNDirEntry alloc] initWithName: @"apple"
                                                    kind: FSNDirEntryKindPlain];
      FSNDirEntry *b = [[FSNDirEntry alloc] initWithName: @"banana"
                                                    kind: FSNDirEntryKindDirectory];
      FSNDirEntry *a2 = [[FSNDirEntry alloc] initWithName: @"apple"
                                                     kind: FSNDirEntryKindLink];

      PASS([a compare: b] == NSOrderedAscending, "compare orders by name");
      PASS([b compare: a] == NSOrderedDescending, "compare is antisymmetric");
      PASS([a compare: a2] == NSOrderedSame, "same names compare equal");

      [a release];
      [b release];
      [a2 release];
    }
  END_SET("FSNDirEntry ordering")

  [arp release];
  return 0;
}
