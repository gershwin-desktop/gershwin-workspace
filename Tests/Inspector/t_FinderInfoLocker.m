/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 *
 * The privileged action's refusals (MI-INS-13).  They need no privilege:
 * every refusal happens before the flag is touched.  The success path runs
 * only when this process may set the flag (root).
 */
#import <Foundation/Foundation.h>
#import "Testing.h"
#include "../../Inspector/FinderInfoLocker.h"
#include <unistd.h>

int main(void)
{
  NSAutoreleasePool *arp = [NSAutoreleasePool new];
  NSString *dir = [NSString stringWithFormat: @"%@/fil-%d", NSTemporaryDirectory(), (int)getpid()];
  NSString *file = [dir stringByAppendingPathComponent: @"f"];
  NSString *link = [dir stringByAppendingPathComponent: @"l"];
  NSString *why = nil;
  NSFileManager *fm = [NSFileManager defaultManager];

#if !defined(__linux__)
  NSLog(@"Linux-only helper action; nothing to test here");
  return 0;
#endif
  [fm removeFileAtPath: dir handler: nil];
  [fm createDirectoryAtPath: dir attributes: nil];
  [fm createFileAtPath: file contents: [NSData dataWithBytes: "x" length: 1] attributes: nil];
  symlink("f", [link fileSystemRepresentation]);

  why = nil;
  PASS(!FinderInfoApplyImmutable(@"relative/file", YES, -1, &why) && why != nil,
       "MI-INS-13 relative path refused");
  why = nil;
  PASS(!FinderInfoApplyImmutable(link, YES, -1, &why) && [why rangeOfString: @"symbolic"].length > 0,
       "MI-INS-13 symlink refused, not followed");
  why = nil;
  PASS(!FinderInfoApplyImmutable([dir stringByAppendingPathComponent: @"nope"], YES, -1, &why)
       && why != nil, "MI-INS-13 missing file refused");
  why = nil;
  PASS(!FinderInfoApplyImmutable(file, YES, (long)getuid() + 1, &why)
       && [why rangeOfString: @"another user"].length > 0,
       "MI-INS-13 file of another user refused");
  why = nil;
  PASS(!FinderInfoApplyImmutable(@"/dev/null", YES, -1, &why)
       && [why rangeOfString: @"regular"].length > 0, "MI-INS-13 device node refused");

  if (geteuid() == 0) {
    PASS(FinderInfoApplyImmutable(file, YES, (long)getuid(), &why), "MI-INS-13 root sets the flag");
    PASS(FinderInfoApplyImmutable(file, NO, (long)getuid(), &why), "MI-INS-13 root clears the flag");
  } else {
    why = nil;
    PASS(!FinderInfoApplyImmutable(file, YES, (long)getuid(), &why) && why != nil,
         "MI-INS-13 unprivileged process gets the kernel's refusal as a message");
  }

  [fm removeFileAtPath: dir handler: nil];
  [arp release];
  return 0;
}
