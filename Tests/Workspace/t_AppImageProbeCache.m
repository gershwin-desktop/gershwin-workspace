/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

/* t_AppImageProbeCache.m - the icon views ask AppImageNodeIsAppImage on
 * EVERY drawRect: (which fires on scroll, expose and refresh) and on every
 * -iconOfSize:forNode: lookup. Before the fix, the gate resolved symlinks
 * (an lstat per path component) for every regular file and, for anything
 * named like an AppImage, ran a fresh open+read+close magic-byte probe
 * every single time - a folder of files paid that I/O on every redraw.
 *
 * This drives the gate function directly, 200 times per fixture (standing
 * in for 200 draws of the same icon), and asserts:
 *   - a file that cannot be an AppImage by name costs no magic probe at all;
 *   - a real AppImage-magic file is probed exactly once across 200 calls,
 *     the rest served from the bounded per-path cache.
 *
 * Headless: real FSNode instances over real temp files, no display, no
 * FSNodeRep/FSNIcon instance ever created (their categories' +load runs as
 * a side effect of linking the framework, but this test never messages
 * FSNodeRep or FSNIcon themselves).
 */

#import <Foundation/Foundation.h>
#import "Testing.h"

#include <unistd.h>

#include "../../Workspace/AppImageIconProvider.m"

static void
writeAppImageMagicFixture(NSString *path)
{
  unsigned char header[16];
  memset(header, 0, sizeof(header));
  header[0] = 0x7f;
  header[1] = 'E';
  header[2] = 'L';
  header[3] = 'F';
  header[8] = 'A';
  header[9] = 'I';
  header[10] = 0x02;

  NSData *data = [NSData dataWithBytes: header length: sizeof(header)];
  [data writeToFile: path atomically: NO];
}

static void
writePlainTextFixture(NSString *path)
{
  NSData *data = [@"just an ordinary file, nowhere near an AppImage"
    dataUsingEncoding: NSUTF8StringEncoding];
  [data writeToFile: path atomically: NO];
}

int
main(void)
{
  NSAutoreleasePool *arp = [NSAutoreleasePool new];
  NSFileManager *fm = [NSFileManager defaultManager];

  NSString *dir = [NSTemporaryDirectory() stringByAppendingPathComponent:
    [NSString stringWithFormat: @"t_appimage_probe_%d", (int)getpid()]];
  [fm removeFileAtPath: dir handler: nil];
  PASS([fm createDirectoryAtPath: dir attributes: nil],
       "fixture directory was created");

  NSString *appImagePath = [dir stringByAppendingPathComponent: @"App.AppImage"];
  NSString *plainPath = [dir stringByAppendingPathComponent: @"readme.txt"];
  writeAppImageMagicFixture(appImagePath);
  writePlainTextFixture(plainPath);

  /* --- a plainly-named regular file is never even probed --- */
  {
    long before = appImageProbeCallCount;
    FSNode *plainNode = [FSNode nodeWithPath: plainPath];
    int i;
    BOOL allNo = YES;

    for (i = 0; i < 200; i++) {
      if (AppImageNodeIsAppImage(plainNode, NULL)) {
        allNo = NO;
      }
    }

    PASS(allNo, "a plainly-named regular file is never treated as an AppImage");
    PASS(appImageProbeCallCount == before,
         "a file that cannot be an AppImage by name is never magic-probed");
  }

  /* --- a real AppImage is probed once, then served from the cache --- */
  {
    long before = appImageProbeCallCount;
    FSNode *node = [FSNode nodeWithPath: appImagePath];
    NSString *realPath = nil;
    int i;
    BOOL allYes = YES;

    for (i = 0; i < 200; i++) {
      realPath = nil;
      if (!AppImageNodeIsAppImage(node, &realPath)) {
        allYes = NO;
      }
    }

    PASS(allYes, "a real AppImage-magic file is recognized on every call");
    PASS_EQUAL(realPath, appImagePath,
               "the resolved path is reported back to the caller");
    PASS(appImageProbeCallCount - before == 1,
         "200 lookups of the same unchanged file perform exactly one magic probe");
  }

  [fm removeFileAtPath: dir handler: nil];
  [arp release];
  return 0;
}
