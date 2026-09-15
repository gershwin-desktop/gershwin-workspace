/* gw-alias-writer.m - write a Gershwin-style (FSNAlias) alias for a path.
  *
  * Used by Tools/mac-alias-interop/verify-alias-reverse.sh: it produces a
  * real Mac alias on Linux (via FSNAlias) - an empty data fork plus a "._"
  * AppleDouble sidecar carrying the resource fork and Finder Info - ships it
  * to a Mac, and the Mac resolves it.  This proves Gershwin's alias format is
  * understood by macOS without any template blobs.
  *
  * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
  */

#import <Foundation/Foundation.h>
#import "FSNAlias.h"

int
main(int argc, char **argv)
{
  NSAutoreleasePool *pool = [NSAutoreleasePool new];
  if (argc < 3)
    {
      fprintf(stderr, "usage: %s <targetPath> <outDir> [volumeName]\n", argv[0]);
      [pool release];
      return 1;
    }

  NSString *target = [NSString stringWithUTF8String: argv[1]];
  NSString *outDir = [NSString stringWithUTF8String: argv[2]];
  NSString *volName = (argc >= 4)
    ? [NSString stringWithUTF8String: argv[3]] : @"Macintosh HD";

  NSString *aliasPath = [FSNAlias writeAliasFileForTargetPath: target
						  inDirectory: outDir
						    volumeName: volName];
  if (aliasPath == nil)
    {
      fprintf(stderr, "gw-alias-writer: failed to write alias for %s\n",
              argv[1]);
      [pool release];
      return 2;
    }

  printf("%s\n", [aliasPath UTF8String]);
  [pool release];
  return 0;
}
