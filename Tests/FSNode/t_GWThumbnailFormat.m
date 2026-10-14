/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

/* t_GWThumbnailFormat.m - the rules of Workspace's thumbnail store:
 * index entries old and new, the validity check, which entries a cleanup
 * may drop, the PNG text chunks a lost index is rebuilt from, file name
 * counters, and the fit into the one stored size. Headless, Foundation
 * only. */

#import <Foundation/Foundation.h>
#import "Testing.h"
#import "GWThumbnailFormat.h"

static void
appendChunk(NSMutableData *png, const char *type, const void *payload,
            uint32_t length)
{
  unsigned char header[8];
  unsigned char crc[4] = { 0, 0, 0, 0 };

  header[0] = (length >> 24) & 0xff;
  header[1] = (length >> 16) & 0xff;
  header[2] = (length >> 8) & 0xff;
  header[3] = length & 0xff;
  memcpy(header + 4, type, 4);
  [png appendBytes: header length: 8];
  if (length > 0)
    {
      [png appendBytes: payload length: length];
    }
  /* The parser never checks CRCs, it only has to find the chunks. */
  [png appendBytes: crc length: 4];
}

static void
appendText(NSMutableData *png, const char *key, const char *value)
{
  NSMutableData *payload = [NSMutableData data];

  [payload appendBytes: key length: strlen(key) + 1];
  [payload appendBytes: value length: strlen(value)];
  appendChunk(png, "tEXt", [payload bytes], (uint32_t)[payload length]);
}

int
main(void)
{
  NSAutoreleasePool *arp = [NSAutoreleasePool new];
  GWThumbnailFileStamp stamp = { 1700000000LL, 4096LL, 1700000100LL };
  GWThumbnailFileStamp touched = { 1700000001LL, 4096LL, 1700000100LL };
  GWThumbnailFileStamp grown = { 1700000000LL, 4097LL, 1700000100LL };
  GWThumbnailFileStamp attrs = { 1700000000LL, 4096LL, 1700000200LL };

  START_SET("index entries")
    NSDictionary *old = GWThumbnailEntryFromIndexValue(@"1a.tiff");
    NSDictionary *entry = GWThumbnailMakeEntry(@"2b.png", GWThumbnailKindIcon,
                                               nil, stamp, NO);
    PASS_EQUAL([old objectForKey: GWThumbnailEntryName], @"1a.tiff",
               "a bare file name from an old index keeps its file");
    PASS_EQUAL([old objectForKey: GWThumbnailEntryKind], GWThumbnailKindThumbnail,
               "and is a thumbnail");
    PASS([old objectForKey: GWThumbnailEntryMTime] == nil, "without a stamp");
    PASS(GWThumbnailEntryFromIndexValue(entry) == entry, "a dictionary stays as it is");
    PASS(GWThumbnailEntryFromIndexValue([NSNumber numberWithInt: 3]) == nil,
         "anything else is no entry");
    PASS([entry objectForKey: GWThumbnailEntryCTime] == nil,
         "ctime is not recorded unless asked for");
    PASS_EQUAL(GWThumbnailEntrySourcePath(entry, @"/a/x.AppImage"), @"/a/x.AppImage",
               "an entry without source is validated against its own path");
    PASS_EQUAL(GWThumbnailEntrySourcePath(GWThumbnailMakeEntry(@"3.png",
                 GWThumbnailKindIcon, @"/a/X.app/Resources/X.tiff", stamp, NO),
                 @"/a/X.app"),
               @"/a/X.app/Resources/X.tiff", "an application's icon file is its source");
  END_SET("index entries")

  START_SET("validity")
    NSDictionary *entry = GWThumbnailMakeEntry(@"2b.png", GWThumbnailKindIcon,
                                               nil, stamp, NO);
    NSDictionary *watched = GWThumbnailMakeEntry(@"2c.png", GWThumbnailKindIcon,
                                                 nil, stamp, YES);
    PASS(GWThumbnailEntryMatches(entry, stamp), "same mtime and size match");
    PASS(!GWThumbnailEntryMatches(entry, touched), "another mtime does not");
    PASS(!GWThumbnailEntryMatches(entry, grown), "another size does not");
    PASS(GWThumbnailEntryMatches(entry, attrs), "ctime is ignored unless recorded");
    PASS(!GWThumbnailEntryMatches(watched, attrs), "a recorded ctime is checked");
    PASS(!GWThumbnailEntryMatches(GWThumbnailEntryFromIndexValue(@"1a.tiff"), stamp),
         "an entry without stamp never matches");
  END_SET("validity")

  START_SET("cleanup decision")
    NSDictionary *entry = GWThumbnailMakeEntry(@"2b.png", GWThumbnailKindIcon,
                                               nil, stamp, NO);
    GWThumbnailSourceState present = { YES, YES, { 1700000000LL, 4096LL, 0 } };
    GWThumbnailSourceState changed = { YES, YES, { 1700000005LL, 4096LL, 0 } };
    GWThumbnailSourceState deleted = { NO, YES, { 0, 0, 0 } };
    GWThumbnailSourceState unmounted = { NO, NO, { 0, 0, 0 } };
    PASS(!GWThumbnailEntryIsStale(entry, present, 10), "unchanged source: kept");
    PASS(GWThumbnailEntryIsStale(entry, changed, 10), "changed source: dropped");
    PASS(GWThumbnailEntryIsStale(entry, deleted, 10), "deleted source: dropped");
    PASS(!GWThumbnailEntryIsStale(entry, unmounted, 86400),
         "directory gone for a day: kept (unmounted media)");
    PASS(GWThumbnailEntryIsStale(entry, unmounted, 31 * 86400.0),
         "directory gone for a month: dropped");
    PASS(GWThumbnailEntryIsStale(GWThumbnailMakeEntry(@"f.png", GWThumbnailKindFailure,
                                                      nil, stamp, NO), changed, 10),
         "failure records follow the same rule");
  END_SET("cleanup decision")

  START_SET("text chunks")
    NSDictionary *entry = GWThumbnailMakeEntry(@"2b.png", GWThumbnailKindIcon,
                                               @"/a/X.app/X.tiff", stamp, YES);
    NSDictionary *text = GWThumbnailTextForEntry(@"/a/X.app", entry, @"Gershwin Workspace");
    NSString *path = nil;
    NSDictionary *back = GWThumbnailEntryFromText(text, @"2b.png", &path);
    PASS_EQUAL(path, @"/a/X.app", "the path survives");
    PASS_EQUAL(back, entry, "the whole entry survives the round trip");
    PASS(GWThumbnailEntryFromText([NSDictionary dictionaryWithObject: @"x"
      forKey: GWThumbnailTextKind], @"n.png", &path) == nil,
         "chunks without path or stamp give no entry");

    NSMutableData *png = [NSMutableData data];
    unsigned char ihdr[13] = { 0, 0, 0, 1, 0, 0, 0, 1, 8, 6, 0, 0, 0 };
    [png appendBytes: "\x89PNG\r\n\x1a\n" length: 8];
    appendChunk(png, "IHDR", ihdr, 13);
    appendText(png, "GW::Path", "/x/caf\xe9.png");
    appendChunk(png, "IDAT", "xx", 2);
    appendText(png, "After", "idat");
    NSDictionary *chunks = GWThumbnailTextChunksInPNG(png);
    PASS_EQUAL([chunks objectForKey: GWThumbnailTextPath], @"/x/café.png",
               "tEXt values are read as Latin-1");
    PASS([chunks objectForKey: @"After"] == nil, "chunks after IDAT are not read");
    PASS([GWThumbnailTextChunksInPNG([png subdataWithRange: NSMakeRange(0, 40)])
           count] == 0, "a chunk cut short is not read");
    PASS(GWThumbnailTextChunksInPNG([@"GIF89a, not a png" dataUsingEncoding:
           NSASCIIStringEncoding]) == nil, "not a PNG gives nil");
    {
      NSUInteger w = 0, h = 0;
      PASS(GWThumbnailPNGDimensions(png, &w, &h) && w == 1 && h == 1,
           "the size is read from IHDR without decoding");
      PASS(!GWThumbnailPNGDimensions([png subdataWithRange: NSMakeRange(0, 20)], &w, &h),
           "a cut IHDR gives no size");
    }
  END_SET("text chunks")

  START_SET("names and old cache")
    PASS(GWThumbnailNameCounter(@"1f.png") == 31, "hex counter of a png name");
    PASS(GWThumbnailNameCounter(@"a.tiff") == 10, "and of an old tiff name");
    PASS(GWThumbnailNameCounter(@"thumbnails.plist") == -1, "the index is no name");
    PASS(GWThumbnailNameCounter(@"zz.png") == -1, "nor is junk");
    PASS_EQUAL(GWThumbnailPathForFileURI(@"file:///tmp/a%20b/%C3%A4.AppImage"),
               @"/tmp/a b/ä.AppImage", "a file URI decodes to its path");
    PASS(GWThumbnailPathForFileURI(@"http://h/x") == nil, "other schemes do not");
    PASS(GWThumbnailPathForFileURI(@"file:///a%2") == nil, "broken escapes do not");
  END_SET("names and old cache")

  START_SET("fit and downscale")
    NSUInteger w = 0, h = 0;
    GWThumbnailFitSize(1024, 512, 512, &w, &h);
    PASS(w == 512 && h == 256, "aspect ratio kept");
    GWThumbnailFitSize(64, 48, 512, &w, &h);
    PASS(w == 64 && h == 48, "never upscaled");
    unsigned char quad[16] = { 255, 0, 0, 255,  0, 0, 0, 0,  0, 0, 0, 0,  0, 0, 0, 0 };
    NSData *one = GWThumbnailDownscaleRGBA([NSData dataWithBytes: quad length: 16], 2, 2, 1, 1);
    const unsigned char *p = [one bytes];
    PASS([one length] == 4 && p[0] == 255 && p[3] == 64,
         "transparent pixels lower alpha without darkening colour");
    PASS(GWThumbnailDownscaleRGBA([NSData dataWithBytes: quad length: 16], 2, 2, 4, 4) == nil,
         "upscaling is refused");
  END_SET("fit and downscale")

  [arp release];
  return 0;
}
