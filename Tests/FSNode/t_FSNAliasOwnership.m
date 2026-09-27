/* t_FSNAliasOwnership.m - the alias factories must own the strings they
 * keep: an alias built from autoreleased path components has to survive
 * the pool those components came from.
 *
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */
#import <Foundation/Foundation.h>
#import "Testing.h"
#include "../../FSNode/FSNAlias.m"
#include <unistd.h>
#include <fcntl.h>

/* A freed string is only caught for sure when it is a zombie: without the
 * zombies the freed memory usually still holds the old bytes and the test
 * would pass by luck. */
static void
ensureZombies(int argc, char **argv)
{
  if (getenv("NSZombieEnabled") == NULL)
    {
      setenv("NSZombieEnabled", "YES", 1);
      execv("/proc/self/exe", argv);
      execv(argv[0], argv);
    }
}

int
main(int argc, char **argv)
{
  ensureZombies(argc, argv);
  NSAutoreleasePool *arp = [NSAutoreleasePool new];
  NSFileManager *fm = [NSFileManager defaultManager];
  NSString *root = [NSString stringWithFormat: @"%@/aliaso_t_%ld",
			     NSTemporaryDirectory(), (long)getpid()];
  NSString *target = [root stringByAppendingPathComponent: @"notes.txt"];
  NSString *log = [root stringByAppendingPathComponent: @"stderr.log"];

  START_SET("alias factories own their strings")
    {
      [fm createDirectoryAtPath: root withIntermediateDirectories: YES
		     attributes: nil error: NULL];
      PASS([@"data" writeToFile: target atomically: YES], "target written");

      FSNAlias *fromPath;
      FSNAlias *fromTarget;
      {
	NSAutoreleasePool *inner = [NSAutoreleasePool new];
	NSString *path = [NSString stringWithFormat: @"%@", target];

	fromPath = [[FSNAlias aliasWithPath: path] retain];
	fromTarget = [[FSNAlias aliasWithTargetPath: path
					 volumeName: [NSString stringWithFormat: @"%@", @"Vol"]] retain];
	[inner release];
      }

      /* Zombies log to stderr; catch that instead of a crash. */
      int saved = dup(2);
      int fd = open([log fileSystemRepresentation], O_WRONLY | O_CREAT | O_TRUNC, 0600);
      dup2(fd, 2);
      close(fd);
      NSString *n1 = [[fromPath targetName] copy];
      NSString *p1 = [[fromPath posixPath] copy];
      NSString *v1 = [[fromPath volumeMountPoint] copy];
      NSString *n2 = [[fromTarget targetName] copy];
      NSString *p2 = [[fromTarget posixPath] copy];
      NSString *v2 = [[fromTarget volumeName] copy];
      [fromPath release];
      [fromTarget release];
      fflush(stderr);
      dup2(saved, 2);
      close(saved);

      NSString *captured = [NSString stringWithContentsOfFile: log];
      PASS([captured rangeOfString: @"deallocated"].location == NSNotFound,
	   "no message reached a deallocated string (%s)", [captured UTF8String]);
      PASS_EQUAL(n1, @"notes.txt", "target name survives the pool");
      PASS_EQUAL(p1, target, "posix path survives the pool");
      PASS(v1 != nil, "mount point survives the pool");
      PASS_EQUAL(n2, @"notes.txt", "target name survives the pool (volume factory)");
      PASS_EQUAL(p2, target, "posix path survives the pool (volume factory)");
      PASS_EQUAL(v2, @"Vol", "volume name survives the pool (volume factory)");
      [n1 release]; [p1 release]; [v1 release];
      [n2 release]; [p2 release]; [v2 release];
      [fm removeItemAtPath: root error: NULL];
    }
  END_SET("alias factories own their strings")

  [arp release];
  return 0;
}
