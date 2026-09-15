/* t_FSNAliasCreate.m - ObjectTesting coverage for creating alias record
 * files on disk (issue #71 follow-up: Make Alias in menus and drags).
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */
#import <Foundation/Foundation.h>
#import "Testing.h"
#include "../../FSNode/FSNAlias.m"

static NSString *
tmpRoot(void)
{
  return [NSString stringWithFormat:@"%@/aliasc_t_%ld",
	    @"/tmp/opencode", (long)getpid()];
}

int
main(void)
{
  NSAutoreleasePool *arp = [NSAutoreleasePool new];
  NSFileManager *fm = [NSFileManager defaultManager];

  START_SET("alias file creation")
    {
      NSString *root = tmpRoot();
      [fm removeItemAtPath: root error: NULL];
      PASS([fm createDirectoryAtPath: root
	   withIntermediateDirectories: YES attributes: nil error: NULL],
	   "temp dir created");

      NSString *target = [root stringByAppendingPathComponent: @"notes.txt"];
      PASS([@"data" writeToFile: target atomically: YES], "target written");

      NSString *aliasPath = [FSNAlias writeAliasFileForPath: target
						inDirectory: root];
      PASS(aliasPath != nil, "alias file returned a path");
      PASS([aliasPath hasSuffix: @"notes alias.txt"],
	   "default name is \"<name> alias.<ext>\"");
      PASS([fm fileExistsAtPath: aliasPath], "alias file exists");

      /* The created file must itself be a resolvable alias record. */
      NSData *data = [NSData dataWithContentsOfFile: aliasPath];
      FSNAlias *parsed = [[FSNAlias alloc] initWithData: data];
      PASS(parsed != nil, "created file parses as alias record");
      PASS_EQUAL([parsed posixPath], target, "record points at target");
      PASS([FSNAlias isAliasData: data], "'alis' magic on disk");

      /* Second alias for the same target must not collide. */
      NSString *second = [FSNAlias writeAliasFileForPath: target
					     inDirectory: root];
      PASS(second != nil && [second hasSuffix: @"notes alias 2.txt"],
	   "collision gets numeric suffix");

      /* Aliasing a directory works the same way. */
      NSString *sub = [root stringByAppendingPathComponent: @"Folder"];
      [fm createDirectoryAtPath: sub withIntermediateDirectories: NO
		      attributes: nil error: NULL];
      NSString *dirAlias = [FSNAlias writeAliasFileForPath: sub
					       inDirectory: root];
      PASS(dirAlias != nil && [dirAlias hasSuffix: @"Folder alias"],
	   "directory alias named after folder");

      /* Non-existent targets are rejected. */
      NSString *bogus = [root stringByAppendingPathComponent: @"gone"];
      PASS([FSNAlias writeAliasFileForPath: bogus
			       inDirectory: root] == nil,
	   "non-existent target rejected");

      [fm removeItemAtPath: root error: NULL];
    }
  END_SET("alias file creation")

  [arp release];
  return 0;
}
