/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

/* t_AppImageIconDiskCache.m - Workspace used to keep AppImage icons only in
 * memory, so every start opened the squashfs of every visible AppImage
 * again. AppImageStoredIcon() now asks the thumbnail store first. This
 * drives it against real AppImage-shaped files (an ELF ident with the type
 * 2 magic, then a squashfs image built with mksquashfs) and counts real
 * extractions:
 *   - the first request extracts and stores the icon, the next does not;
 *   - a corrupt AppImage is extracted once, then its failure record answers;
 *   - a touched AppImage is extracted again;
 *   - the drawing path takes an entry or failure record as proof of an
 *     AppImage instead of probing the file.
 * The store is pointed at a private directory before anything can write. */

#if defined(GW_NO_SQUASHFS)
#import <Foundation/Foundation.h>

int
main(void)
{
  NSAutoreleasePool *arp = [NSAutoreleasePool new];

  NSLog(@"libsquashfs is not installed, so Workspace is built without "
        @"AppImage support and there is nothing to test");
  [arp release];
  return 0;
}
#else
#import <Foundation/Foundation.h>
#import "Testing.h"

#include <sys/time.h>
#include <unistd.h>

#include "../../Workspace/AppImageIconProvider.m"
#import "GWThumbnailPNG.h"

static NSData *
iconPNG(NSUInteger side)
{
  NSMutableData *rgba = [NSMutableData dataWithLength: side * side * 4];
  memset([rgba mutableBytes], 0x80, side * side * 4);
  return GWThumbnailPNGEncodeRGBA(rgba, side, side, nil);
}

/* What the AppImage runtime looks like to the code under test: an ELF ident
 * carrying "AI\2" at offset 8, padded to the 4096 boundary where the
 * scanner looks for the squashfs superblock. */
static NSMutableData *
runtimeHeader(void)
{
  NSMutableData *head = [NSMutableData dataWithLength: 4096];
  unsigned char *h = [head mutableBytes];

  memcpy(h, "\x7f" "ELF", 4);
  h[8] = 'A'; h[9] = 'I'; h[10] = 0x02;
  return head;
}

static BOOL
buildAppImage(NSString *path, NSString *work)
{
  NSFileManager *fm = [NSFileManager defaultManager];
  NSString *src = [work stringByAppendingPathComponent: @"squashfs-root"];
  NSString *sqfs = [work stringByAppendingPathComponent: @"image.sqfs"];
  NSMutableData *file = runtimeHeader();
  NSString *cmd;

  [fm removeFileAtPath: src handler: nil];
  [fm removeFileAtPath: sqfs handler: nil];
  [fm createDirectoryAtPath: src withIntermediateDirectories: YES
                 attributes: nil error: NULL];
  [iconPNG(256) writeToFile: [src stringByAppendingPathComponent: @".DirIcon"]
                 atomically: NO];
  cmd = [NSString stringWithFormat:
    @"mksquashfs '%@' '%@' -no-progress >/dev/null 2>&1", src, sqfs];
  if (system([cmd UTF8String]) != 0)
    {
      return NO;
    }
  [file appendData: [NSData dataWithContentsOfFile: sqfs]];
  return [file writeToFile: path atomically: NO];
}

int
main(void)
{
  NSAutoreleasePool *arp = [NSAutoreleasePool new];
  NSFileManager *fm = [NSFileManager defaultManager];
  NSString *base = [NSTemporaryDirectory() stringByAppendingPathComponent:
    [NSString stringWithFormat: @"t_AppImageIconDiskCache.%d", getpid()]];
  NSString *root = [base stringByAppendingPathComponent: @"Thumbnails"];
  NSString *apps = [base stringByAppendingPathComponent: @"apps"];
  NSString *good = [apps stringByAppendingPathComponent: @"Good.AppImage"];
  NSString *broken = [apps stringByAppendingPathComponent: @"Broken.AppImage"];
  GWThumbnailStore *store;
  long before;
  NSData *first, *again;
  NSUInteger w = 0, h = 0;

  [fm removeFileAtPath: base handler: nil];
  [fm createDirectoryAtPath: apps withIntermediateDirectories: YES
                 attributes: nil error: NULL];

  /* Before anything can ask for it, so the user's own store is never
   * opened. */
  store = [[GWThumbnailStore alloc] initWithDirectory: root pixelSize: 64];
  [GWThumbnailStore setSharedStore: store];
  NEED(PASS([[[GWThumbnailStore sharedStore] directory] hasPrefix: NSTemporaryDirectory()],
            "the store writes into the private temp directory"));

  if (!buildAppImage(good, base))
    {
      NSLog(@"mksquashfs unavailable - skipping the disk cache coverage");
      [arp release];
      return 0;
    }
  [runtimeHeader() writeToFile: broken atomically: NO];

  START_SET("first request extracts, the next reads the store")
    before = appImageExtractionCount;
    first = AppImageStoredIcon(good);
    PASS(first != nil && appImageExtractionCount == before + 1,
         "first request extracts once");
    PASS([[[store entryForPath: good] objectForKey: GWThumbnailEntryKind]
           isEqual: GWThumbnailKindIcon], "and stores an icon entry for it");
    PASS(GWThumbnailPNGDecodeRGBA(first, 4096, &w, &h) != nil && w == 64 && h == 64,
         "the 256 icon is kept at the store's one size");
    before = appImageExtractionCount;
    again = AppImageStoredIcon(good);
    PASS([again isEqual: first] && appImageExtractionCount == before,
         "a second request (a restart) extracts nothing");
  END_SET("first request extracts, the next reads the store")

  START_SET("a corrupt AppImage is probed once")
    before = appImageExtractionCount;
    PASS(AppImageStoredIcon(broken) == nil && appImageExtractionCount == before + 1,
         "the corrupt file is extracted once and fails");
    PASS([store hasFailureForPath: broken source: nil], "a failure record is written");
    PASS(AppImageStoredIcon(broken) == nil && appImageExtractionCount == before + 1,
         "the failure record keeps it from being extracted again");
  END_SET("a corrupt AppImage is probed once")

  START_SET("a modified AppImage is extracted again")
    struct timeval tv[2];
    gettimeofday(&tv[0], NULL);
    tv[1] = tv[0];
    tv[1].tv_sec += 100;
    utimes([good fileSystemRepresentation], tv);
    before = appImageExtractionCount;
    PASS(AppImageStoredIcon(good) != nil && appImageExtractionCount == before + 1,
         "a touched AppImage is extracted again");
    PASS([[[store entryForPath: good] objectForKey: GWThumbnailEntryMTime]
           longLongValue] == (long long)tv[1].tv_sec,
         "and its entry now carries the new mtime");
  END_SET("a modified AppImage is extracted again")

  START_SET("the drawing path takes the store's word without probing")
    NSString *cached = [apps stringByAppendingPathComponent: @"Cached.AppImage"];
    NSString *uncached = [apps stringByAppendingPathComponent: @"Uncached.AppImage"];
    NSString *failed = [apps stringByAppendingPathComponent: @"Failed.AppImage"];
    long probes;

    /* No AppImage magic at all: only the store can make them AppImages. */
    [@"an entry says this was an AppImage" writeToFile: cached atomically: NO];
    [store storeImageData: iconPNG(64) forPath: cached kind: GWThumbnailKindIcon source: nil];
    [@"failed before, no magic needed" writeToFile: failed atomically: NO];
    [store storeFailureForPath: failed source: nil];
    [runtimeHeader() writeToFile: uncached atomically: NO];

    probes = appImageProbeCallCount;
    PASS(AppImageKnownToStore(cached), "a valid icon entry is known");
    PASS(AppImageKnownToStore(failed), "so is a failure record");
    PASS(!AppImageKnownToStore(uncached), "a file without either is not");
    PASS(appImageProbeCallCount == probes, "none of that probes the file");
    PASS(AppImageNodeIsAppImage([FSNode nodeWithPath: uncached], NULL)
         && appImageProbeCallCount == probes + 1,
         "the probe is what decides for a file the store does not know");
  END_SET("the drawing path takes the store's word without probing")

  [GWThumbnailStore setSharedStore: nil];
  [store release];
  [fm removeFileAtPath: base handler: nil];
  [arp release];
  return 0;
}
#endif /* GW_NO_SQUASHFS */
