/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

/* t_GWThumbnailStore.m - the one thumbnail store against a private
 * directory: PNG round trips, storing any image format at the one size,
 * validity, failure records, sources other than the indexed path,
 * thumbnails.plist on disk (old bare names migrated, two writers merged,
 * a lost index rebuilt from the PNGs), the cleanup, and the move of an
 * earlier build's entries out of a ~/.cache/thumbnails style directory.
 * Headless; never touches the real ~/GNUstep or ~/.cache. */

#import <AppKit/AppKit.h>
#import "Testing.h"
#import "GWThumbnailStore.h"
#import "GWThumbnailPNG.h"
#import "GWThumbnailImage.h"
#include <sys/stat.h>
#include <sys/time.h>
#include <unistd.h>

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

static NSData *
iconTIFF(NSUInteger side)
{
  NSBitmapImageRep *rep = [[[NSBitmapImageRep alloc]
    initWithBitmapDataPlanes: NULL pixelsWide: side pixelsHigh: side
               bitsPerSample: 8 samplesPerPixel: 3 hasAlpha: NO isPlanar: NO
              colorSpaceName: NSDeviceRGBColorSpace bytesPerRow: side * 3
                bitsPerPixel: 24] autorelease];
  memset([rep bitmapData], 0x40, side * side * 3);
  return [rep TIFFRepresentation];
}

static BOOL
exists(NSString *path)
{
  struct stat st;
  return lstat([path fileSystemRepresentation], &st) == 0;
}

static int
modeOf(NSString *path)
{
  struct stat st;
  return stat([path fileSystemRepresentation], &st) == 0 ? (int)(st.st_mode & 0777) : -1;
}

static void
writeFile(NSString *path, NSString *content)
{
  [[content dataUsingEncoding: NSUTF8StringEncoding] writeToFile: path atomically: NO];
}

static void
shiftTime(NSString *path, long seconds)
{
  struct timeval tv[2];

  gettimeofday(&tv[0], NULL);
  tv[0].tv_sec += seconds;
  tv[1] = tv[0];
  utimes([path fileSystemRepresentation], tv);
}

static NSString *
fileOf(GWThumbnailStore *store, NSString *path)
{
  NSString *name = [[store entryForPath: path] objectForKey: GWThumbnailEntryName];
  return name ? [[store directory] stringByAppendingPathComponent: name] : nil;
}

int
main(void)
{
  NSAutoreleasePool *arp = [NSAutoreleasePool new];
  NSFileManager *fm = [NSFileManager defaultManager];
  NSString *base = [NSTemporaryDirectory() stringByAppendingPathComponent:
    [NSString stringWithFormat: @"t_GWThumbnailStore.%d", getpid()]];
  NSString *dir = [base stringByAppendingPathComponent: @"Library/Thumbnails"];
  NSString *src = [base stringByAppendingPathComponent: @"files"];
  NSString *app = [src stringByAppendingPathComponent: @"Tool.AppImage"];
  GWThumbnailStore *store;

  [fm removeFileAtPath: base handler: nil];
  [fm createDirectoryAtPath: src withIntermediateDirectories: YES attributes: nil error: NULL];
  writeFile(app, @"an AppImage as far as the store cares");

  store = [[GWThumbnailStore alloc] initWithDirectory: dir pixelSize: 64];
  NEED(PASS([[store directory] isEqualToString: dir]
            && [dir hasPrefix: NSTemporaryDirectory()],
            "the store lives in the private temp directory"));

  START_SET("store and read")
    NSUInteger w = 0, h = 0;
    NSData *png = [store storeImageData: iconPNG(256) forPath: app
                                   kind: GWThumbnailKindIcon source: nil];
    NSDictionary *entry = [store entryForPath: app];
    NSDictionary *text = GWThumbnailTextChunksInPNG(png);
    NSString *file = fileOf(store, app);

    PASS(GWThumbnailPNGDecodeRGBA(png, 4096, &w, &h) != nil && w == 64 && h == 64,
         "a 256 px icon is kept at the one size, 64 here");
    PASS(GWThumbnailNameCounter([entry objectForKey: GWThumbnailEntryName]) > 0
         && [[[entry objectForKey: GWThumbnailEntryName] pathExtension] isEqual: @"png"],
         "named by the counter, as GWThumbnailer always did");
    PASS([[NSData dataWithContentsOfFile: file] isEqual: png] && modeOf(file) == 0600,
         "the file is that PNG, 0600");
    PASS_EQUAL([text objectForKey: GWThumbnailTextPath], app, "its text names the source");
    PASS_EQUAL([text objectForKey: GWThumbnailTextKind], GWThumbnailKindIcon, "and the kind");
    PASS([[store dataForPath: app kind: GWThumbnailKindIcon source: nil] isEqual: png],
         "read back while the source is unchanged");
    PASS([store dataForPath: app kind: GWThumbnailKindThumbnail source: nil] == nil,
         "not as another kind");
    shiftTime(app, 100);
    PASS([store dataForPath: app kind: GWThumbnailKindIcon source: nil] == nil,
         "not once the source changed");
    [store storeImageData: iconPNG(256) forPath: app kind: GWThumbnailKindIcon source: nil];
    PASS(!exists(file) && exists(fileOf(store, app)),
         "storing again replaces the file");

    NSString *image = [src stringByAppendingPathComponent: @"photo.tiff"];
    writeFile(image, @"t");
    png = [store storeImageData: iconTIFF(32) forPath: image
                           kind: GWThumbnailKindThumbnail source: nil];
    PASS(GWThumbnailPNGDecodeRGBA(png, 4096, &w, &h) != nil && w == 32,
         "a TIFF is stored as PNG, a small one not blown up");

    NSString *noimage = [src stringByAppendingPathComponent: @"x.svg"];
    writeFile(noimage, @"s");
    PASS([store storeImageData: [@"<svg/>" dataUsingEncoding: NSASCIIStringEncoding]
                       forPath: noimage kind: GWThumbnailKindIcon source: nil] == nil
         && [store entryForPath: noimage] == nil, "undecodable data stores nothing");
  END_SET("store and read")

  START_SET("sources and failures")
    NSString *bundle = [src stringByAppendingPathComponent: @"Tool.app"];
    NSString *iconFile = [bundle stringByAppendingPathComponent: @"Tool.tiff"];
    NSString *broken = [src stringByAppendingPathComponent: @"broken.AppImage"];

    [fm createDirectoryAtPath: bundle attributes: nil];
    writeFile(iconFile, @"icon");
    PASS([store storeImageData: iconPNG(48) forPath: bundle kind: GWThumbnailKindIcon
                        source: iconFile] != nil,
         "an application's icon is stored against its icon file");
    PASS([store fileForPath: bundle kind: GWThumbnailKindIcon source: iconFile] != nil,
         "and found with it");
    PASS([store fileForPath: bundle kind: GWThumbnailKindIcon source: nil] == nil,
         "but not against another source");
    shiftTime(iconFile, 100);
    PASS([store fileForPath: bundle kind: GWThumbnailKindIcon source: iconFile] == nil,
         "a changed icon file is noticed");

    writeFile(broken, @"corrupt");
    PASS(![store hasFailureForPath: broken source: nil], "no failure yet");
    PASS([store storeFailureForPath: broken source: nil]
         && [store hasFailureForPath: broken source: nil], "failure recorded");
    shiftTime(broken, 100);
    PASS(![store hasFailureForPath: broken source: nil], "a changed file is tried again");
    [store storeFailureForPath: broken source: nil];
  END_SET("sources and failures")

  START_SET("thumbnails.plist")
    NSDictionary *disk;
    GWThumbnailStore *other;
    NSString *mine = [src stringByAppendingPathComponent: @"mine.AppImage"];
    NSString *theirs = [src stringByAppendingPathComponent: @"theirs.AppImage"];

    [store flush];
    disk = [NSDictionary dictionaryWithContentsOfFile:
      [dir stringByAppendingPathComponent: @"thumbnails.plist"]];
    PASS([[disk objectForKey: app] isKindOfClass: [NSDictionary class]]
         && [[[disk objectForKey: app] objectForKey: GWThumbnailEntryMTime] longLongValue] > 0,
         "the index on disk holds entries with stamps, keyed by source path");

    /* A second writer, as another process would be. */
    other = [[GWThumbnailStore alloc] initWithDirectory: dir pixelSize: 64];
    writeFile(mine, @"m");
    writeFile(theirs, @"t");
    [store storeImageData: iconPNG(16) forPath: mine kind: GWThumbnailKindIcon source: nil];
    [other storeImageData: iconPNG(16) forPath: theirs kind: GWThumbnailKindIcon source: nil];
    [other flush];
    [store flush];
    disk = [NSDictionary dictionaryWithContentsOfFile:
      [dir stringByAppendingPathComponent: @"thumbnails.plist"]];
    PASS([disk objectForKey: mine] != nil && [disk objectForKey: theirs] != nil,
         "two writers lose nothing of each other's");
    PASS(![[[disk objectForKey: mine] objectForKey: GWThumbnailEntryName]
            isEqual: [[disk objectForKey: theirs] objectForKey: GWThumbnailEntryName]],
         "and never take the same file name");
    PASS([store entryForPath: theirs] != nil, "the other writer's entries are taken over");
    [other release];
  END_SET("thumbnails.plist")

  START_SET("old index migrated")
    NSString *oldDir = [base stringByAppendingPathComponent: @"old/Thumbnails"];
    NSString *fresh = [src stringByAppendingPathComponent: @"fresh.png"];
    NSString *stale = [src stringByAppendingPathComponent: @"stale.png"];
    NSDictionary *old;
    GWThumbnailStore *migrated;

    [fm createDirectoryAtPath: oldDir withIntermediateDirectories: YES attributes: nil error: NULL];
    writeFile(fresh, @"f");
    writeFile(stale, @"s");
    shiftTime(fresh, -1000);
    [iconTIFF(8) writeToFile: [oldDir stringByAppendingPathComponent: @"a.tiff"] atomically: NO];
    [iconTIFF(8) writeToFile: [oldDir stringByAppendingPathComponent: @"b.tiff"] atomically: NO];
    shiftTime([oldDir stringByAppendingPathComponent: @"b.tiff"], -1000);
    old = [NSDictionary dictionaryWithObjectsAndKeys: @"a.tiff", fresh, @"b.tiff", stale, nil];
    [old writeToFile: [oldDir stringByAppendingPathComponent: @"thumbnails.plist"] atomically: NO];

    migrated = [[GWThumbnailStore alloc] initWithDirectory: oldDir pixelSize: 64];
    PASS([migrated fileForPath: fresh kind: GWThumbnailKindThumbnail source: nil] != nil,
         "a bare name made after its source became a valid thumbnail entry");
    PASS([migrated entryForPath: stale] == nil
         && !exists([oldDir stringByAppendingPathComponent: @"b.tiff"]),
         "one older than its source is dropped with its file");
    PASS([[[NSDictionary dictionaryWithContentsOfFile:
             [oldDir stringByAppendingPathComponent: @"thumbnails.plist"]]
            objectForKey: fresh] isKindOfClass: [NSDictionary class]],
         "and the migrated index is written back");
    [migrated release];
  END_SET("old index migrated")

  START_SET("read-only")
    GWThumbnailStore *reader;
    NSString *other = [src stringByAppendingPathComponent: @"other.AppImage"];
    NSString *oldDir = [base stringByAppendingPathComponent: @"old2/Thumbnails"];
    NSString *aged = [src stringByAppendingPathComponent: @"aged.png"];
    NSDictionary *old;

    [store flush];
    reader = [[GWThumbnailStore alloc] initWithDirectory: dir pixelSize: 64 writable: NO];
    writeFile(other, @"o");
    PASS([reader fileForPath: app kind: GWThumbnailKindIcon source: nil] != nil,
         "a read-only store finds valid entries");
    PASS([reader storeImageData: iconPNG(16) forPath: other kind: GWThumbnailKindIcon
                         source: nil] == nil && [reader entryForPath: other] == nil,
         "but stores nothing");
    PASS(![reader removeEntryForPath: app] && exists(fileOf(store, app)),
         "and removes nothing");
    [reader release];

    [fm createDirectoryAtPath: oldDir withIntermediateDirectories: YES attributes: nil error: NULL];
    writeFile(aged, @"a");
    old = [NSDictionary dictionaryWithObject: @"c.tiff" forKey: aged];
    [old writeToFile: [oldDir stringByAppendingPathComponent: @"thumbnails.plist"] atomically: NO];
    reader = [[GWThumbnailStore alloc] initWithDirectory: oldDir pixelSize: 64 writable: NO];
    PASS([[[NSDictionary dictionaryWithContentsOfFile:
             [oldDir stringByAppendingPathComponent: @"thumbnails.plist"]]
            objectForKey: aged] isEqual: @"c.tiff"],
         "nor does it migrate an old index: only Workspace keeps the store");
    [reader release];
  END_SET("read-only")

  START_SET("lost index rebuilt")
    GWThumbnailStore *rebuilt;
    NSString *broken = [src stringByAppendingPathComponent: @"broken.AppImage"];

    [store flush];
    unlink([[dir stringByAppendingPathComponent: @"thumbnails.plist"] fileSystemRepresentation]);
    rebuilt = [[GWThumbnailStore alloc] initWithDirectory: dir pixelSize: 64];
    PASS([rebuilt fileForPath: app kind: GWThumbnailKindIcon source: nil] != nil,
         "entries come back from the PNGs' text chunks");
    PASS([rebuilt hasFailureForPath: broken source: nil], "failure records too");
    PASS(exists([dir stringByAppendingPathComponent: @"thumbnails.plist"]),
         "and the index is written again");
    [rebuilt release];
  END_SET("lost index rebuilt")

  START_SET("cleanup")
    NSString *gone = [src stringByAppendingPathComponent: @"gone.AppImage"];
    NSString *changed = [src stringByAppendingPathComponent: @"changed.AppImage"];
    NSString *kept = [src stringByAppendingPathComponent: @"kept.AppImage"];
    NSString *lost = [src stringByAppendingPathComponent: @"lost.AppImage"];
    NSString *goneFile, *changedFile, *junk, *lostFile;
    NSArray *dropped;

    writeFile(gone, @"g");
    writeFile(changed, @"c");
    writeFile(kept, @"k");
    writeFile(lost, @"l");
    [store storeImageData: iconPNG(16) forPath: gone kind: GWThumbnailKindIcon source: nil];
    [store storeImageData: iconPNG(16) forPath: changed kind: GWThumbnailKindIcon source: nil];
    [store storeImageData: iconPNG(16) forPath: kept kind: GWThumbnailKindIcon source: nil];
    [store flush];
    goneFile = fileOf(store, gone);
    changedFile = fileOf(store, changed);

    /* A file whose writer died before its index update reached disk. */
    {
      GWThumbnailFileStamp ls;
      NSDictionary *le;

      GWThumbnailStampForPath(lost, &ls);
      le = GWThumbnailMakeEntry(@"ffe.png", GWThumbnailKindIcon, nil, ls, NO);
      lostFile = [[dir stringByAppendingPathComponent: @"ffe.png"] retain];
      [GWThumbnailPNGEncodeRGBA(solidRGBA(4, 4, 255), 4, 4,
         GWThumbnailTextForEntry(lost, le, @"Gershwin Workspace"))
        writeToFile: lostFile atomically: NO];
      shiftTime(lostFile, -120);
    }

    junk = [dir stringByAppendingPathComponent: @"ff0.png"];
    [iconPNG(4) writeToFile: junk atomically: NO];
    shiftTime(junk, -120);
    unlink([gone fileSystemRepresentation]);
    shiftTime(changed, 100);

    dropped = [store removeStaleEntries];
    PASS([dropped containsObject: gone] && [dropped containsObject: changed],
         "deleted and changed sources are reported");
    PASS(!exists(goneFile) && !exists(changedFile) && [store entryForPath: gone] == nil,
         "and their files and entries are gone");
    PASS([store entryForPath: kept] != nil, "an unchanged source keeps its entry");
    PASS(!exists(junk), "a file no entry references and no source claims is deleted");
    PASS([store fileForPath: lost kind: GWThumbnailKindIcon source: nil] != nil,
         "a file whose index update was lost is adopted again");
    PASS([[store removeStaleEntries] count] == 0, "a second cleanup finds nothing");
    [lostFile release];

    NSString *moved = [src stringByAppendingPathComponent: @"moved.AppImage"];
    writeFile(moved, @"m");
    [store storeImageData: iconPNG(16) forPath: moved kind: GWThumbnailKindIcon source: nil];
    rename([moved fileSystemRepresentation],
           [[src stringByAppendingPathComponent: @"renamed.AppImage"] fileSystemRepresentation]);
    PASS([[store removeStaleEntriesForPaths: [NSArray arrayWithObject: moved]] count] == 1
         && [store entryForPath: moved] == nil, "a moved file's entry goes at once");

    NSString *folder = [src stringByAppendingPathComponent: @"folder"];
    NSString *inside = [folder stringByAppendingPathComponent: @"inner.AppImage"];
    [fm createDirectoryAtPath: folder attributes: nil];
    writeFile(inside, @"i");
    [store storeImageData: iconPNG(16) forPath: inside kind: GWThumbnailKindIcon source: nil];
    rename([folder fileSystemRepresentation],
           [[src stringByAppendingPathComponent: @"folder2"] fileSystemRepresentation]);
    PASS([[store removeStaleEntriesForPaths: [NSArray arrayWithObject: folder]] count] == 1
         && [store entryForPath: inside] == nil,
         "a moved folder takes the entries of what is inside along");
  END_SET("cleanup")

  START_SET("earlier cache imported")
    NSString *cache = [base stringByAppendingPathComponent: @"cache/thumbnails"];
    NSString *normal = [cache stringByAppendingPathComponent: @"normal"];
    NSString *failDir = [cache stringByAppendingPathComponent: @"fail/gershwin-workspace-1.1.0"];
    NSString *ours = [src stringByAppendingPathComponent: @"Imported.AppImage"];
    NSString *failed = [src stringByAppendingPathComponent: @"Failed.AppImage"];
    NSString *foreign = [normal stringByAppendingPathComponent: @"foreign.png"];
    GWThumbnailFileStamp s;
    NSMutableDictionary *t;
    NSString *haveFile;

    [fm createDirectoryAtPath: normal withIntermediateDirectories: YES attributes: nil error: NULL];
    [fm createDirectoryAtPath: failDir withIntermediateDirectories: YES attributes: nil error: NULL];
    writeFile(ours, @"o");
    writeFile(failed, @"f");

    GWThumbnailStampForPath(ours, &s);
    t = [NSMutableDictionary dictionary];
    [t setObject: [@"file://" stringByAppendingString: ours] forKey: @"Thumb::URI"];
    [t setObject: [NSString stringWithFormat: @"%lld", s.mtime] forKey: @"Thumb::MTime"];
    [t setObject: [NSString stringWithFormat: @"%lld", s.size] forKey: @"Thumb::Size"];
    [t setObject: @"Gershwin Workspace" forKey: @"Software"];
    [GWThumbnailPNGEncodeRGBA(solidRGBA(128, 128, 255), 128, 128, t)
      writeToFile: [normal stringByAppendingPathComponent: @"a1.png"] atomically: NO];
    [t setObject: @"Another Viewer" forKey: @"Software"];
    [GWThumbnailPNGEncodeRGBA(solidRGBA(8, 8, 255), 8, 8, t) writeToFile: foreign atomically: NO];

    GWThumbnailStampForPath(failed, &s);
    [t setObject: [@"file://" stringByAppendingString: failed] forKey: @"Thumb::URI"];
    [t setObject: [NSString stringWithFormat: @"%lld", s.mtime] forKey: @"Thumb::MTime"];
    [t setObject: [NSString stringWithFormat: @"%lld", s.size] forKey: @"Thumb::Size"];
    [t setObject: @"Gershwin Workspace" forKey: @"Software"];
    [GWThumbnailPNGEncodeRGBA(solidRGBA(1, 1, 0), 1, 1, t)
      writeToFile: [failDir stringByAppendingPathComponent: @"b2.png"] atomically: NO];

    {
      /* An AppImage this store already has an icon for. */
      NSString *have = [src stringByAppendingPathComponent: @"Have.AppImage"];
      GWThumbnailFileStamp hs;

      writeFile(have, @"h");
      [store storeImageData: iconPNG(256) forPath: have kind: GWThumbnailKindIcon source: nil];
      GWThumbnailStampForPath(have, &hs);
      [t setObject: [@"file://" stringByAppendingString: have] forKey: @"Thumb::URI"];
      [t setObject: [NSString stringWithFormat: @"%lld", hs.mtime] forKey: @"Thumb::MTime"];
      [t setObject: [NSString stringWithFormat: @"%lld", hs.size] forKey: @"Thumb::Size"];
      [GWThumbnailPNGEncodeRGBA(solidRGBA(8, 8, 255), 8, 8, t)
        writeToFile: [normal stringByAppendingPathComponent: @"c3.png"] atomically: NO];
      haveFile = [fileOf(store, have) retain];
    }
    PASS([store importEntriesFromCacheDirectory: cache software: @"Gershwin Workspace"] == 2,
         "Workspace's icon and failure record are moved");
    PASS(exists(haveFile) && !exists([normal stringByAppendingPathComponent: @"c3.png"]),
         "an entry the store already has is kept, the old one only deleted");
    [haveFile release];
    PASS([store fileForPath: ours kind: GWThumbnailKindIcon source: nil] != nil
         && [store hasFailureForPath: failed source: nil], "into this store");
    PASS(!exists([normal stringByAppendingPathComponent: @"a1.png"]) && !exists(failDir),
         "and deleted there, the emptied fail directory too");
    PASS(exists(foreign), "another program's thumbnail is left alone");
    PASS([store importEntriesFromCacheDirectory: cache software: @"Gershwin Workspace"] == 0,
         "a second run moves nothing");
  END_SET("earlier cache imported")

  START_SET("images without drawing")
    NSImage *small = GWThumbnailImageFromPNG(iconPNG(256), 48, 1.0);
    NSBitmapImageRep *rep = (NSBitmapImageRep *)[[small representations] lastObject];
    NSUInteger w = 0, h = 0;
    PASS([small size].width == 48 && [rep pixelsWide] == 48,
         "a stored PNG drawn at 48 points becomes 48 pixels at scale 1");
    small = GWThumbnailImageFromPNG(iconPNG(256), 48, 2.0);
    rep = (NSBitmapImageRep *)[[small representations] lastObject];
    PASS([small size].width == 48 && [rep pixelsWide] == 96, "and 96 pixels at scale 2");
    PASS(GWThumbnailRGBAFromData(iconTIFF(8), 64, &w, &h) != nil && w == 8,
         "a TIFF bitmap is read without drawing");
  END_SET("images without drawing")

  [store release];
  [fm removeFileAtPath: base handler: nil];
  [arp release];
  return 0;
}
