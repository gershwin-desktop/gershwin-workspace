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
#if defined(__linux__)
#include <fcntl.h>
#include <linux/fs.h>
#include <sys/ioctl.h>
#include <errno.h>
#endif

#if defined(__linux__)
/* Setting the immutable flag takes CAP_LINUX_IMMUTABLE, which root lacks in
 * an unprivileged container (the CI ones), and a file system that has the
 * flag at all; the success path can only be expected with both. */
static BOOL
mayLockFilesOn(NSString *file, NSString **reason)
{
  NSString *status = [NSString stringWithContentsOfFile: @"/proc/self/status"];
  NSEnumerator *e = [[status componentsSeparatedByString: @"\n"] objectEnumerator];
  NSString *line;
  unsigned long long caps = 0;
  int fd, flags;

  while ((line = [e nextObject]) != nil)
    if ([line hasPrefix: @"CapEff:"])
      caps = strtoull([[[line substringFromIndex: 7] stringByTrimmingCharactersInSet:
                         [NSCharacterSet whitespaceCharacterSet]] UTF8String], NULL, 16);
  if ((caps & (1ULL << 9)) == 0)
    {
      *reason = @"no CAP_LINUX_IMMUTABLE (unprivileged container)";
      return NO;
    }
  fd = open([file fileSystemRepresentation], O_RDONLY);
  if (fd < 0 || ioctl(fd, FS_IOC_GETFLAGS, &flags) != 0)
    {
      *reason = [NSString stringWithFormat: @"the file system of %@ has no file flags (%s)",
                          file, strerror(errno)];
      if (fd >= 0) close(fd);
      return NO;
    }
  close(fd);
  return YES;
}
#endif

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
    NSString *reason = nil;

    if (mayLockFilesOn(file, &reason)) {
      PASS(FinderInfoApplyImmutable(file, YES, (long)getuid(), &why), "MI-INS-13 root sets the flag");
      PASS(FinderInfoApplyImmutable(file, NO, (long)getuid(), &why), "MI-INS-13 root clears the flag");
    } else {
      NSLog(@"root cannot set the immutable flag here: %@; checking the refusal instead", reason);
      why = nil;
      PASS(!FinderInfoApplyImmutable(file, YES, (long)getuid(), &why) && why != nil,
           "MI-INS-13 root without the capability gets the kernel's refusal as a message");
    }
  } else {
    why = nil;
    PASS(!FinderInfoApplyImmutable(file, YES, (long)getuid(), &why) && why != nil,
         "MI-INS-13 unprivileged process gets the kernel's refusal as a message");
  }

  [fm removeFileAtPath: dir handler: nil];
  [arp release];
  return 0;
}
