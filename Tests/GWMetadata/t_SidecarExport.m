/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 */

/* A `._` sidecar exported for a file whose FinderInfo and fork live in xattrs
 * must be one 10.6 can unpack: entry 9 (32 bytes) first, then entry 2, in the
 * compact tar layout (evidence E15, E17 e/f, E28).  The expected bytes are the
 * hand-fixed sidecars that 10.6 accepted (E28 fixed-sidecars). */

#import <Foundation/Foundation.h>
#import "Testing.h"
#import "GSAppleDouble.h"
#import "GSFileMetadata.h"
#import "GWMetaXattr.h"
#include <unistd.h>

static NSString * const kFixedDir =
  @"interop/fixtures/finder106/E28-p-links2/fixed-sidecars";

static NSString *
scratchDir(void)
{
  NSString *d = [NSTemporaryDirectory() stringByAppendingPathComponent:
    [NSString stringWithFormat: @"t_SidecarExport-%d", (int)getpid()]];
  NSFileManager *fm = [NSFileManager defaultManager];
  [fm removeFileAtPath: d handler: nil];
  [fm createDirectoryAtPath: d withIntermediateDirectories: YES
                 attributes: nil error: NULL];
  return d;
}

static uint32_t
be32(const uint8_t *p)
{
  return ((uint32_t)p[0] << 24) | ((uint32_t)p[1] << 16)
       | ((uint32_t)p[2] << 8) | p[3];
}

/* Puts FinderInfo/fork into the file's xattrs (nil = leave out), exports the
 * sidecar the way an archive or copy to a foreign volume does, returns it. */
static NSData *
exportSidecar(NSString *path, NSData *fi, NSData *fork)
{
  const char *c = [path fileSystemRepresentation];
  if (fi)
    gs_setxattr(c, [GSXATTR_FINDERINFO UTF8String], [fi bytes],
                [fi length], 0);
  if (fork)
    gs_setxattr(c, [GSXATTR_RESOURCEFORK UTF8String], [fork bytes],
                [fork length], 0);
  GSFileMetadata *md = [GSFileMetadata metadataForFileAtPath: path];
  if (![md writeSidecarToFileAtPath: path error: NULL])
    return nil;
  return [NSData dataWithContentsOfFile:
    [GSFileMetadata sidecarPathForFilePath: path]];
}

int
main(void)
{
  NSAutoreleasePool *arp = [NSAutoreleasePool new];
  NSFileManager *fm = [NSFileManager defaultManager];
  NSString *dir = scratchDir();
  NSArray *names = [NSArray arrayWithObjects: @"webfix.webloc",
    @"ftpfix.ftploc", @"mailfix.mailtoloc", nil];

  for (NSString *name in names)
    {
      NSString *fixture = [kFixedDir stringByAppendingPathComponent: name];
      NSData *want = [NSData dataWithContentsOfFile:
        [kFixedDir stringByAppendingPathComponent:
          [@"._" stringByAppendingString: name]]];
      GSAppleDouble *ad = [[[GSAppleDouble alloc] initWithData: want]
        autorelease];
      NSString *path = [dir stringByAppendingPathComponent: name];

      [fm copyPath: fixture toPath: path handler: nil];
      NSData *got = exportSidecar(path, [ad finderInfo], [ad resourceFork]);
      const uint8_t *b = [got bytes];

      PASS(want != nil && [ad hasFinderInfo] && [ad hasResourceFork],
           "%s: E28 fixed sidecar fixture is there", [name UTF8String]);
      PASS(got != nil && [got length] >= 50 && b[25] == 2,
           "%s: exported sidecar has two entries", [name UTF8String]);
      PASS([got length] >= 50 && be32(b + 26) == 9 && be32(b + 30) == 50
           && be32(b + 34) == 32,
           "%s: entry 9 first, 32 bytes at 50", [name UTF8String]);
      PASS([got length] >= 50 && be32(b + 38) == 2 && be32(b + 42) == 82,
           "%s: entry 2 follows at 82", [name UTF8String]);
      PASS_EQUAL(got, want,
                 "%s: byte for byte the sidecar 10.6 accepted",
                 [name UTF8String]);
      [fm removeFileAtPath: [GSFileMetadata sidecarPathForFilePath: path]
                   handler: nil];
    }

  /* E17 e/f: a fork without any FinderInfo still gets a zeroed entry 9, or
   * copyfile refuses the whole sidecar and the fork is lost. */
  {
    NSString *path = [dir stringByAppendingPathComponent: @"forkonly"];
    uint8_t forkBytes[20];
    memset(forkBytes, 0xAB, sizeof(forkBytes));
    NSData *fork = [NSData dataWithBytes: forkBytes length: sizeof(forkBytes)];
    NSData *zeros = [NSMutableData dataWithLength: 32];

    [fm createFileAtPath: path contents: [NSData data] attributes: nil];
    NSData *got = exportSidecar(path, nil, fork);
    GSAppleDouble *ad = got ? [[[GSAppleDouble alloc] initWithData: got]
      autorelease] : nil;
    const uint8_t *b = [got bytes];

    PASS([got length] >= 50 && b[25] == 2 && be32(b + 26) == 9
         && be32(b + 34) == 32 && be32(b + 38) == 2 && be32(b + 42) == 82,
         "fork only: entry 9 (32 bytes) before entry 2 at 82");
    PASS_EQUAL([ad finderInfo], zeros, "fork only: entry 9 is all zeros");
    PASS_EQUAL([ad resourceFork], fork, "fork only: the fork is kept");
  }

  [fm removeFileAtPath: dir handler: nil];
  [arp release];
  return 0;
}
