/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

/* t_AppImageIconDiskCache.m - Workspace used to keep AppImage icons only in
 * memory, so every start opened the squashfs of every visible AppImage
 * again. AppImageIconData() now asks the shared thumbnail cache
 * first. This drives it against real AppImage-shaped files (an ELF ident
 * with the type 2 magic, then a squashfs image built with mksquashfs) and
 * counts real extractions:
 *   - the first request extracts and writes the entry, the next does not;
 *   - a corrupt AppImage is extracted once, then its failure record answers;
 *   - a touched AppImage is extracted again;
 *   - Workspace moving or renaming an AppImage drops its entries.
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

static NSString *
entry(NSString *root, NSString *sub, NSString *original)
{
  return [[root stringByAppendingPathComponent: sub]
           stringByAppendingPathComponent:
             GWThumbnailFileNameForURI(GWThumbnailURIForPath(original))];
}

static BOOL
exists(NSString *path)
{
  return [[NSFileManager defaultManager] fileExistsAtPath: path];
}

/* The notification hook removes entries on a thread of its own. */
static BOOL
waitUntilGone(NSString *path)
{
  int i;

  for (i = 0; i < 300 && exists(path); i++)
    {
      usleep(10000);
    }
  return !exists(path);
}

static void
postChange(NSString *operation, NSString *source, NSString *destination,
           NSArray *files)
{
  NSDictionary *info = [NSDictionary dictionaryWithObjectsAndKeys:
    operation, @"operation", source, @"source", destination, @"destination",
    files, @"files", nil];

  [[NSNotificationCenter defaultCenter]
    postNotificationName: @"GWFileSystemDidChangeNotification" object: info];
}

int
main(void)
{
  NSAutoreleasePool *arp = [NSAutoreleasePool new];
  NSFileManager *fm = [NSFileManager defaultManager];
  NSString *base = [NSTemporaryDirectory() stringByAppendingPathComponent:
    [NSString stringWithFormat: @"t_AppImageIconDiskCache.%d", getpid()]];
  NSString *root = [base stringByAppendingPathComponent: @"thumbnails"];
  NSString *apps = [base stringByAppendingPathComponent: @"apps"];
  NSString *good = [apps stringByAppendingPathComponent: @"Good.AppImage"];
  NSString *broken = [apps stringByAppendingPathComponent: @"Broken.AppImage"];
  NSString *failDir = @"fail/gershwin-workspace-" PACKAGE_VERSION;
  long before;
  NSData *first, *again;
  NSUInteger w = 0, h = 0;

  [fm removeFileAtPath: base handler: nil];
  [fm createDirectoryAtPath: apps withIntermediateDirectories: YES
                 attributes: nil error: NULL];

  /* +load pointed the store at the real ~/.cache/thumbnails; nothing has
   * written there yet. Redirect it before the first request. */
  [appImageThumbnailStore release];
  appImageThumbnailStore = [[GWThumbnailStore alloc]
    initWithDirectory: root
             software: @"Gershwin Workspace"
             mimeType: @"application/vnd.appimage"
              program: @"gershwin-workspace"
              version: @PACKAGE_VERSION];
  NEED(PASS([[appImageThumbnailStore directory] hasPrefix: NSTemporaryDirectory()],
            "the store writes into the private temp directory"));

  if (!buildAppImage(good, base))
    {
      NSLog(@"mksquashfs unavailable - skipping the disk cache coverage");
      [arp release];
      return 0;
    }
  [runtimeHeader() writeToFile: broken atomically: NO];

  START_SET("first request extracts, the next reads the cache")
    before = appImageExtractionCount;
    first = AppImageIconData(good);
    PASS(first != nil && appImageExtractionCount == before + 1,
         "first request extracts once");
    PASS(exists(entry(root, @"normal", good)), "and writes normal/<md5>.png");
    PASS(GWThumbnailPNGDecodeRGBA(first, 4096, &w, &h) != nil && w == 128 && h == 128,
         "the 256 icon comes back at 128");
    before = appImageExtractionCount;
    again = AppImageIconData(good);
    PASS([again isEqual: first] && appImageExtractionCount == before,
         "a second request (a restart) extracts nothing");
  END_SET("first request extracts, the next reads the cache")

  START_SET("a corrupt AppImage is probed once")
    before = appImageExtractionCount;
    PASS(AppImageIconData(broken) == nil && appImageExtractionCount == before + 1,
         "the corrupt file is extracted once and fails");
    PASS(exists(entry(root, failDir, broken)), "a failure record is written");
    PASS(AppImageIconData(broken) == nil && appImageExtractionCount == before + 1,
         "the failure record keeps it from being extracted again");
  END_SET("a corrupt AppImage is probed once")

  START_SET("a modified AppImage is extracted again")
    struct timeval tv[2];
    gettimeofday(&tv[0], NULL);
    tv[1] = tv[0];
    tv[1].tv_sec += 100;
    utimes([good fileSystemRepresentation], tv);
    before = appImageExtractionCount;
    PASS(AppImageIconData(good) != nil && appImageExtractionCount == before + 1,
         "a touched AppImage is extracted again");
    PASS([[GWThumbnailTextChunksInPNG([NSData dataWithContentsOfFile:
            entry(root, @"normal", good)]) objectForKey: GWThumbnailKeyMTime]
           isEqual: ([NSString stringWithFormat: @"%ld", (long)tv[1].tv_sec])],
         "and its entry now carries the new mtime");
  END_SET("a modified AppImage is extracted again")

  START_SET("the drawing path takes a valid entry without probing")
    NSString *cached = [apps stringByAppendingPathComponent: @"Cached.AppImage"];
    NSString *uncached = [apps stringByAppendingPathComponent: @"Uncached.AppImage"];
    NSString *plain = [apps stringByAppendingPathComponent: @"Plain.AppImage"];
    NSString *failed = [apps stringByAppendingPathComponent: @"Failed.AppImage"];
    GWThumbnailFileStamp stamp;
    NSString *realPath = nil;
    NSData *thumb = nil;
    BOOL knownFailure = NO;
    long probes;

    /* No AppImage magic at all: only the entry can make it one. */
    [@"an entry says this was an AppImage" writeToFile: cached atomically: NO];
    GWThumbnailStampForPath(cached, &stamp);
    [appImageThumbnailStore storeIconData: iconPNG(64) forPath: cached
                                    stamp: stamp pixels: 48];
    [runtimeHeader() writeToFile: uncached atomically: NO];
    [@"neither magic nor entry" writeToFile: plain atomically: NO];
    [@"failed before, no magic needed" writeToFile: failed atomically: NO];
    GWThumbnailStampForPath(failed, &stamp);
    [appImageThumbnailStore storeFailureForPath: failed stamp: stamp];

    probes = appImageProbeCallCount;
    PASS(AppImageNodeIsAppImageWithThumbnail([FSNode nodeWithPath: cached],
                                             &realPath, &thumb, &knownFailure)
         && thumb != nil && !knownFailure && [realPath isEqual: cached],
         "a valid entry is returned synchronously");
    PASS(appImageProbeCallCount == probes, "and spares the magic-byte probe");
    PASS(AppImageNodeIsAppImage([FSNode nodeWithPath: cached], NULL)
         && appImageProbeCallCount == probes,
         "the verdict is remembered for the redraw checks");

    thumb = nil;
    PASS(AppImageNodeIsAppImageWithThumbnail([FSNode nodeWithPath: uncached],
                                             &realPath, &thumb, &knownFailure)
         && thumb == nil && appImageProbeCallCount == probes + 1,
         "without an entry the file is probed and left to the loader");
    PASS(!AppImageNodeIsAppImageWithThumbnail([FSNode nodeWithPath: plain],
                                              &realPath, &thumb, &knownFailure)
         && appImageProbeCallCount == probes + 2,
         "a file named like an AppImage without magic or entry is none");
    probes = appImageProbeCallCount;
    PASS(AppImageNodeIsAppImageWithThumbnail([FSNode nodeWithPath: failed],
                                             &realPath, &thumb, &knownFailure)
         && thumb == nil && knownFailure && appImageProbeCallCount == probes,
         "a failure record is reported without probing, so no loader is needed");
  END_SET("the drawing path takes a valid entry without probing")

  START_SET("base icons are scaled without drawing")
    NSImage *base = AppImageBaseIconFromPNG(iconPNG(256));
    NSBitmapImageRep *rep = (NSBitmapImageRep *)[[base representations] lastObject];
    NSUInteger box = AppImageThumbnailPixels();
    PASS(base != nil && [base size].width == APPIMAGE_BASE_ICON_SIZE
         && [base size].height == APPIMAGE_BASE_ICON_SIZE,
         "a 256 px PNG becomes a 48 point icon");
    PASS([rep isKindOfClass: [NSBitmapImageRep class]]
         && (NSUInteger)[rep pixelsWide] == box && (NSUInteger)[rep pixelsHigh] == box,
         "with exactly the pixels a 48 point icon needs at this scale factor");
    base = AppImageBaseIconFromPNG(iconPNG(16));
    PASS(base != nil && [base size].width < APPIMAGE_BASE_ICON_SIZE,
         "a small icon is not blown up");
    PASS(AppImageBaseIconFromPNG([@"II*\0" dataUsingEncoding: NSASCIIStringEncoding]) == nil,
         "non-PNG data gives nil");
  END_SET("base icons are scaled without drawing")

  START_SET("Workspace's own moves drop the entries")
    NSString *elsewhere = [base stringByAppendingPathComponent: @"elsewhere"];
    NSString *renamed = [apps stringByAppendingPathComponent: @"Renamed.AppImage"];

    [fm createDirectoryAtPath: elsewhere attributes: nil];
    rename([good fileSystemRepresentation],
           [[elsewhere stringByAppendingPathComponent: @"Good.AppImage"]
             fileSystemRepresentation]);
    postChange(@"NSWorkspaceMoveOperation", apps, elsewhere,
               [NSArray arrayWithObject: @"Good.AppImage"]);
    PASS(waitUntilGone(entry(root, @"normal", good)), "a moved AppImage's entry goes");

    PASS(buildAppImage(good, base) && AppImageIconData(good) != nil
         && exists(entry(root, @"normal", good)), "a fresh entry for the next case");
    rename([good fileSystemRepresentation], [renamed fileSystemRepresentation]);
    postChange(@"WorkspaceRenameOperation", good, renamed, nil);
    PASS(waitUntilGone(entry(root, @"normal", good)), "a renamed AppImage's entry goes");
    PASS(exists(entry(root, failDir, broken)), "other AppImages' entries stay");
  END_SET("Workspace's own moves drop the entries")

  [fm removeFileAtPath: base handler: nil];
  [arp release];
  return 0;
}
#endif /* GW_NO_SQUASHFS */
