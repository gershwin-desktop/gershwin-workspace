/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

/* t_GWThumbnailStore.m - the on-disk half of Workspace's AppImage icon
 * cache against a private cache directory: PNG round trips with tEXt
 * metadata, where entries land and with which permissions, the validity
 * check on reading, failure records, and the sweep deleting only stale
 * entries Workspace wrote. Headless; never touches the real ~/.cache. */

#import <Foundation/Foundation.h>
#import "Testing.h"
#import "GWThumbnailStore.h"
#import "GWThumbnailPNG.h"
#include <sys/stat.h>
#include <sys/time.h>
#include <unistd.h>

static NSString * const kSoftware = @"Gershwin Workspace";

static NSData *
solidRGBA(NSUInteger w, NSUInteger h, unsigned char alpha)
{
  NSMutableData *d = [NSMutableData dataWithLength: w * h * 4];
  unsigned char *p = [d mutableBytes];
  NSUInteger i;

  for (i = 0; i < w * h; i++)
    {
      p[i * 4] = 200; p[i * 4 + 1] = 100; p[i * 4 + 2] = 50; p[i * 4 + 3] = alpha;
    }
  return d;
}

static NSData *
iconPNG(NSUInteger side)
{
  return GWThumbnailPNGEncodeRGBA(solidRGBA(side, side, 255), side, side, nil);
}

static int
modeOf(NSString *path)
{
  struct stat st;

  if (stat([path fileSystemRepresentation], &st) != 0)
    {
      return -1;
    }
  return st.st_mode & 0777;
}

static BOOL
exists(NSString *path)
{
  struct stat st;
  return lstat([path fileSystemRepresentation], &st) == 0;
}

static NSString *
entryPath(NSString *root, NSString *sub, NSString *original)
{
  return [[root stringByAppendingPathComponent: sub]
           stringByAppendingPathComponent:
             GWThumbnailFileNameForURI(GWThumbnailURIForPath(original))];
}

static void
writeFile(NSString *path, NSString *content)
{
  [[content dataUsingEncoding: NSUTF8StringEncoding] writeToFile: path atomically: NO];
}

static GWThumbnailFileStamp
stampOf(NSString *path)
{
  GWThumbnailFileStamp s = { -1, -1 };
  GWThumbnailStampForPath(path, &s);
  return s;
}

/* An entry another program wrote, or one of ours aged on purpose. */
static void
plantEntry(NSString *file, NSString *original, NSString *software,
           GWThumbnailFileStamp stamp)
{
  NSMutableDictionary *text = [NSMutableDictionary dictionary];

  [text setObject: GWThumbnailURIForPath(original) forKey: GWThumbnailKeyURI];
  [text setObject: [NSString stringWithFormat: @"%lld", stamp.mtime]
           forKey: GWThumbnailKeyMTime];
  [text setObject: [NSString stringWithFormat: @"%lld", stamp.size]
           forKey: GWThumbnailKeySize];
  [text setObject: software forKey: GWThumbnailKeySoftware];
  [[NSFileManager defaultManager]
    createDirectoryAtPath: [file stringByDeletingLastPathComponent]
    withIntermediateDirectories: YES attributes: nil error: NULL];
  [GWThumbnailPNGEncodeRGBA(solidRGBA(1, 1, 0), 1, 1, text)
    writeToFile: file atomically: NO];
}

int
main(void)
{
  NSAutoreleasePool *arp = [NSAutoreleasePool new];
  NSFileManager *fm = [NSFileManager defaultManager];
  NSString *base = [NSTemporaryDirectory() stringByAppendingPathComponent:
    [NSString stringWithFormat: @"t_GWThumbnailStore.%d", getpid()]];
  NSString *root = [base stringByAppendingPathComponent: @"cache/thumbnails"];
  NSString *originals = [base stringByAppendingPathComponent: @"apps"];
  NSString *app = [originals stringByAppendingPathComponent: @"Tool 1.AppImage"];
  GWThumbnailStore *store;

  [fm removeFileAtPath: base handler: nil];
  [fm createDirectoryAtPath: originals withIntermediateDirectories: YES
                 attributes: nil error: NULL];
  writeFile(app, @"not really an AppImage, the store does not care");

  store = [[GWThumbnailStore alloc] initWithDirectory: root
                                             software: kSoftware
                                             mimeType: @"application/vnd.appimage"
                                              program: @"gershwin-workspace"
                                              version: @"9.9"];
  /* Nothing below may write anywhere but the private directory. */
  NEED(PASS([[store directory] isEqualToString: root]
            && [root hasPrefix: NSTemporaryDirectory()],
            "store writes into the private temp directory"));

  START_SET("PNG round trip")
    NSDictionary *text = [NSDictionary dictionaryWithObject: @"vé"
                                                     forKey: @"Thumb::X"];
    NSData *pixels = solidRGBA(3, 2, 128);
    NSData *png = GWThumbnailPNGEncodeRGBA(pixels, 3, 2, text);
    NSUInteger w = 0, h = 0;
    NSData *back = GWThumbnailPNGDecodeRGBA(png, 64, &w, &h);
    PASS(w == 3 && h == 2 && [back isEqual: pixels], "pixels survive encode and decode");
    PASS_EQUAL([GWThumbnailTextChunksInPNG(png) objectForKey: @"Thumb::X"], @"vé",
               "tEXt written ahead of IDAT, Latin-1");
    PASS(GWThumbnailPNGDecodeRGBA(png, 2, &w, &h) == nil, "larger than maxSide -> nil");
    PASS(GWThumbnailPNGDecodeRGBA([png subdataWithRange: NSMakeRange(0, [png length] - 20)],
                                  64, &w, &h) == nil, "truncated PNG -> nil");
    PASS(GWThumbnailPNGDecodeRGBA([@"icns-not-png" dataUsingEncoding: NSASCIIStringEncoding],
                                  64, &w, &h) == nil, "not a PNG -> nil");
  END_SET("PNG round trip")

  START_SET("stamp")
    GWThumbnailFileStamp s;
    NSString *locked = [originals stringByAppendingPathComponent: @"locked.AppImage"];
    PASS(GWThumbnailStampForPath(app, &s) && s.size == 47, "readable file has a stamp");
    PASS(!GWThumbnailStampForPath(originals, &s), "a directory has none");
    writeFile(locked, @"x");
    chmod([locked fileSystemRepresentation], 0);
    PASS(getuid() == 0 || !GWThumbnailStampForPath(locked, &s),
         "an unreadable file has none, so the cache is left alone");
    unlink([locked fileSystemRepresentation]);
  END_SET("stamp")

  START_SET("store and read")
    GWThumbnailFileStamp stamp = stampOf(app);
    GWThumbnailFileStamp later = { stamp.mtime + 1, stamp.size };
    NSString *normal = entryPath(root, @"normal", app);
    NSUInteger w = 0, h = 0;
    NSData *thumb = [store storeIconData: iconPNG(256) forPath: app
                                   stamp: stamp pixels: 48];
    NSDictionary *text = GWThumbnailTextChunksInPNG(thumb);

    PASS(GWThumbnailPNGDecodeRGBA(thumb, 4096, &w, &h) != nil && w == 128 && h == 128,
         "a 256 icon drawn at 48 is stored at 128 in normal");
    PASS([[NSData dataWithContentsOfFile: normal] isEqual: thumb],
         "entry is at normal/<md5 of URI>.png");
    PASS(modeOf(normal) == 0600, "entry is 0600");
    PASS(modeOf([root stringByAppendingPathComponent: @"normal"]) == 0700
         && modeOf(root) == 0700, "directories are created 0700");
    PASS_EQUAL([text objectForKey: GWThumbnailKeyURI], GWThumbnailURIForPath(app), "Thumb::URI");
    PASS_EQUAL([text objectForKey: GWThumbnailKeyMTime],
               ([NSString stringWithFormat: @"%lld", stamp.mtime]), "Thumb::MTime");
    PASS_EQUAL([text objectForKey: GWThumbnailKeySize], @"47", "Thumb::Size");
    PASS_EQUAL([text objectForKey: GWThumbnailKeyMimetype], @"application/vnd.appimage",
               "Thumb::Mimetype");
    PASS_EQUAL([text objectForKey: GWThumbnailKeySoftware], kSoftware, "Software");
    PASS([[store thumbnailForPath: app stamp: stamp pixels: 64] isEqual: thumb],
         "read back while the original is unchanged");
    PASS([store thumbnailForPath: app stamp: later pixels: 64] == nil,
         "not used once the original's mtime changed");
    PASS([store thumbnailForPath: app stamp: stamp pixels: 200] == nil,
         "another size directory holds nothing yet");
    PASS([[fm directoryContentsAtPath: [root stringByAppendingPathComponent: @"normal"]]
           count] == 1, "no temporary file is left behind");

    thumb = [store storeIconData: iconPNG(256) forPath: app stamp: stamp pixels: 200];
    PASS(GWThumbnailPNGDecodeRGBA(thumb, 4096, &w, &h) != nil && w == 256
         && exists(entryPath(root, @"large", app)), "drawn at 200: large, 256 kept");

    NSString *small = [originals stringByAppendingPathComponent: @"small.AppImage"];
    writeFile(small, @"s");
    thumb = [store storeIconData: iconPNG(32) forPath: small stamp: stampOf(small) pixels: 48];
    PASS(GWThumbnailPNGDecodeRGBA(thumb, 4096, &w, &h) != nil && w == 32,
         "a small icon is not upscaled");

    NSString *tiff = [originals stringByAppendingPathComponent: @"tiff.AppImage"];
    writeFile(tiff, @"t");
    PASS([store storeIconData: [@"II*\0 a tiff icon" dataUsingEncoding: NSASCIIStringEncoding]
                      forPath: tiff stamp: stampOf(tiff) pixels: 48] == nil
         && !exists(entryPath(root, @"normal", tiff)),
         "a non-PNG icon is not cached");
  END_SET("store and read")

  START_SET("failures")
    NSString *broken = [originals stringByAppendingPathComponent: @"broken.AppImage"];
    GWThumbnailFileStamp stamp;
    writeFile(broken, @"corrupt");
    stamp = stampOf(broken);
    GWThumbnailFileStamp changed = { stamp.mtime, stamp.size + 1 };
    NSString *failFile = entryPath(root, @"fail/gershwin-workspace-9.9", broken);

    PASS(![store hasFailureForPath: broken stamp: stamp], "no failure recorded yet");
    PASS([store storeFailureForPath: broken stamp: stamp] && exists(failFile),
         "failure written to fail/<program>-<version>/");
    PASS(modeOf(failFile) == 0600, "failure entry is 0600");
    PASS([store hasFailureForPath: broken stamp: stamp], "the same file is not probed again");
    PASS(![store hasFailureForPath: broken stamp: changed], "a changed file is probed again");
    PASS([[GWThumbnailTextChunksInPNG([NSData dataWithContentsOfFile: failFile])
            objectForKey: GWThumbnailKeySoftware] isEqual: kSoftware],
         "failure carries the same metadata");
  END_SET("failures")

  START_SET("containsPath")
    PASS([store containsPath: [root stringByAppendingPathComponent: @"normal/x.png"]],
         "a file in the cache");
    PASS(![store containsPath: app], "an original outside it");
    PASS(![store containsPath: [root stringByAppendingString: @"-other/x"]],
         "a sibling sharing the name prefix");
  END_SET("containsPath")

  START_SET("sweep")
    NSString *kept = [originals stringByAppendingPathComponent: @"kept.AppImage"];
    NSString *gone = [originals stringByAppendingPathComponent: @"gone.AppImage"];
    NSString *touched = [originals stringByAppendingPathComponent: @"touched.AppImage"];
    NSString *foreign = [originals stringByAppendingPathComponent: @"foreign.AppImage"];
    NSString *oldFail = [originals stringByAppendingPathComponent: @"oldfail.AppImage"];
    NSString *mountless = @"/nonexistent-volume-of-t_GWThumbnailStore/x.AppImage";
    GWThumbnailFileStamp none = { 1, 1 };
    struct timeval tv[2];

    writeFile(kept, @"k");
    writeFile(gone, @"g");
    writeFile(touched, @"t");
    [store storeIconData: iconPNG(16) forPath: kept stamp: stampOf(kept) pixels: 48];
    [store storeIconData: iconPNG(16) forPath: gone stamp: stampOf(gone) pixels: 48];
    [store storeIconData: iconPNG(16) forPath: touched stamp: stampOf(touched) pixels: 48];
    [store storeFailureForPath: gone stamp: stampOf(gone)];
    plantEntry(entryPath(root, @"normal", foreign), foreign, @"Another Viewer", none);
    plantEntry(entryPath(root, @"fail/another-viewer-1.0", gone), gone, kSoftware, none);
    plantEntry(entryPath(root, @"fail/gershwin-workspace-1.0", oldFail), oldFail, kSoftware, none);
    plantEntry(entryPath(root, @"normal", mountless), mountless, kSoftware, none);

    unlink([gone fileSystemRepresentation]);
    gettimeofday(&tv[0], NULL);
    tv[1] = tv[0];
    tv[1].tv_sec += 100;
    utimes([touched fileSystemRepresentation], tv);

    NSUInteger removed = [store removeStaleEntries];
    PASS(removed == 4, "four stale entries of ours removed (got %lu)", (unsigned long)removed);
    PASS(exists(entryPath(root, @"normal", kept)), "unchanged original: kept");
    PASS(!exists(entryPath(root, @"normal", gone)), "deleted original: removed");
    PASS(!exists(entryPath(root, @"fail/gershwin-workspace-9.9", gone)),
         "its failure record: removed");
    PASS(!exists(entryPath(root, @"normal", touched)), "modified original: removed");
    PASS(!exists(entryPath(root, @"fail/gershwin-workspace-1.0", oldFail)),
         "an older version's failure record: removed");
    PASS(exists(entryPath(root, @"normal", foreign)), "another program's entry: kept");
    PASS(exists(entryPath(root, @"fail/another-viewer-1.0", gone)),
         "another program's fail directory is not looked at");
    PASS(exists(entryPath(root, @"normal", mountless)),
         "original on a missing volume: kept while young");
    PASS([store removeStaleEntries] == 0, "a second sweep finds nothing");
  END_SET("sweep")

  START_SET("removeStaleEntriesForPath")
    NSString *moved = [originals stringByAppendingPathComponent: @"moved.AppImage"];
    NSString *other = [originals stringByAppendingPathComponent: @"other.AppImage"];
    writeFile(moved, @"m");
    writeFile(other, @"o");
    [store storeIconData: iconPNG(16) forPath: moved stamp: stampOf(moved) pixels: 48];
    [store storeIconData: iconPNG(16) forPath: moved stamp: stampOf(moved) pixels: 200];
    [store storeIconData: iconPNG(16) forPath: other stamp: stampOf(other) pixels: 48];
    PASS([store removeStaleEntriesForPath: moved] == 0, "nothing while the file is there");
    rename([moved fileSystemRepresentation],
           [[originals stringByAppendingPathComponent: @"renamed.AppImage"]
             fileSystemRepresentation]);
    PASS([store removeStaleEntriesForPath: moved] == 2, "both sizes of the moved file go");
    PASS(exists(entryPath(root, @"normal", other)), "other files' entries stay");
  END_SET("removeStaleEntriesForPath")

  [store release];
  [fm removeFileAtPath: base handler: nil];
  [arp release];
  return 0;
}
