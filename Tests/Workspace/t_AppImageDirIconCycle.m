/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

/* t_AppImageDirIconCycle.m - ObjectTesting coverage for
 * AppImageReadFileDataFromInode() against a squashfs image whose .DirIcon
 * is a symlink pointing back at itself.
 *
 * .DirIcon may be a symlink; resolving it re-looks-up the target path and
 * recurses into AppImageReadFileDataFromInode() again with no depth limit
 * or cycle check. A ".DirIcon" symlink whose target is the literal string
 * ".DirIcon" resolves to the very same directory entry, so the lookup finds
 * itself again forever: a crafted or corrupt AppImage overflows the stack
 * just from being listed, not from anything the user opens.
 *
 * The fixture is a real squashfs image built with mksquashfs(1) (the same
 * tool that produces real AppImages), containing nothing but that one
 * self-referencing symlink at its root, fed to AppImageExtractIconData()
 * with offset 0 (the whole file IS the squashfs image - no ELF header or
 * magic-byte scan is involved in reaching the code under test).
 *
 * A stack overflow crashes the process, so the extraction runs in a forked
 * child, exactly like t_DSStoreCyclicBTree.m: the parent asserts the child
 * exited normally (no crash) and that extraction returned nil, rather than
 * asserting anything in-process that an actual overflow would never let
 * run.
 */

#import <Foundation/Foundation.h>
#import "Testing.h"

#include <stdlib.h>
#include <sys/wait.h>
#include <unistd.h>

#include "../../Workspace/AppImageIconProvider.m"

/* Builds a squashfs image at sqfsPath whose only entry is a ".DirIcon"
 * symlink targeting the literal string ".DirIcon" - a one-hop cycle back to
 * itself. Returns NO if mksquashfs is unavailable or fails, so the caller
 * can skip rather than fail the suite on a machine without it. */
static BOOL
buildCyclicDirIconFixture(NSString *sqfsPath)
{
  NSFileManager *fm = [NSFileManager defaultManager];
  NSString *srcDir = [NSTemporaryDirectory() stringByAppendingPathComponent:
    [NSString stringWithFormat: @"t_appimage_cycle_src_%d", (int)getpid()]];

  [fm removeFileAtPath: srcDir handler: nil];
  if (![fm createDirectoryAtPath: srcDir attributes: nil]) {
    return NO;
  }

  NSString *linkPath = [srcDir stringByAppendingPathComponent: @".DirIcon"];
  if (symlink(".DirIcon", [linkPath fileSystemRepresentation]) != 0) {
    [fm removeFileAtPath: srcDir handler: nil];
    return NO;
  }

  [fm removeFileAtPath: sqfsPath handler: nil];

  NSString *cmd = [NSString stringWithFormat:
    @"mksquashfs '%@' '%@' -no-progress >/dev/null 2>&1", srcDir, sqfsPath];
  int rc = system([cmd UTF8String]);

  [fm removeFileAtPath: srcDir handler: nil];

  return (rc == 0) && [fm fileExistsAtPath: sqfsPath];
}

int
main(void)
{
  NSAutoreleasePool *arp = [NSAutoreleasePool new];
  NSString *sqfsPath = [NSTemporaryDirectory() stringByAppendingPathComponent:
    [NSString stringWithFormat: @"t_appimage_cycle_%d.sqfs", (int)getpid()]];

  if (!buildCyclicDirIconFixture(sqfsPath)) {
    NSLog(@"mksquashfs unavailable or fixture build failed - skipping "
          @"cyclic .DirIcon coverage");
    [arp release];
    return 0;
  }

  PASS([[NSFileManager defaultManager] fileExistsAtPath: sqfsPath],
       "cyclic-.DirIcon squashfs fixture was built");

  pid_t pid = fork();
  if (pid == 0) {
    NSAutoreleasePool *childPool = [NSAutoreleasePool new];
    NSData *iconData = AppImageExtractIconData(sqfsPath, 0);
    [childPool release];
    _exit(iconData == nil ? 0 : 1);
  }

  int status = 0;
  PASS(waitpid(pid, &status, 0) == pid, "forked extraction child was reaped");

  BOOL crashed = WIFSIGNALED(status);
  if (crashed) {
    NSLog(@"child terminated by signal %d (unbounded recursion on the "
          @"self-referencing .DirIcon symlink)", WTERMSIG(status));
  }
  PASS(!crashed,
       "extracting from a self-referencing .DirIcon does not overflow the stack");
  PASS(WIFEXITED(status) && WEXITSTATUS(status) == 0,
       "extraction returns nil instead of recursing forever");

  [[NSFileManager defaultManager] removeFileAtPath: sqfsPath handler: nil];
  [arp release];
  return 0;
}
