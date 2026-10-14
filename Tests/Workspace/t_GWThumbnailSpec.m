/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

/* t_GWThumbnailSpec.m - the shared thumbnail cache rules Workspace's
 * AppImage icon cache follows: cache location, URI escaping, MD5 naming,
 * size directories, PNG text chunks, the validity check, which entries the
 * sweep may delete, and the downscale into a size box. Headless,
 * Foundation only. */

#import <Foundation/Foundation.h>
#import "Testing.h"
#import "GWThumbnailSpec.h"

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

static NSMutableData *
pngHead(void)
{
  NSMutableData *png = [NSMutableData data];
  unsigned char ihdr[13] = { 0, 0, 0, 1, 0, 0, 0, 1, 8, 6, 0, 0, 0 };

  [png appendBytes: "\x89PNG\r\n\x1a\n" length: 8];
  appendChunk(png, "IHDR", ihdr, 13);
  return png;
}

static NSDictionary *
textWith(NSString *uri, NSString *mtime, NSString *size, NSString *software)
{
  NSMutableDictionary *d = [NSMutableDictionary dictionary];

  if (uri) [d setObject: uri forKey: GWThumbnailKeyURI];
  if (mtime) [d setObject: mtime forKey: GWThumbnailKeyMTime];
  if (size) [d setObject: size forKey: GWThumbnailKeySize];
  if (software) [d setObject: software forKey: GWThumbnailKeySoftware];
  return d;
}

int
main(void)
{
  NSAutoreleasePool *arp = [NSAutoreleasePool new];
  NSString *softwareName = @"Gershwin Workspace";

  START_SET("cache directory")
    PASS_EQUAL(GWThumbnailCacheDirectory(nil, @"/home/u"),
               @"/home/u/.cache/thumbnails", "unset XDG_CACHE_HOME uses ~/.cache");
    PASS_EQUAL(GWThumbnailCacheDirectory(@"", @"/home/u"),
               @"/home/u/.cache/thumbnails", "empty XDG_CACHE_HOME uses ~/.cache");
    PASS_EQUAL(GWThumbnailCacheDirectory(@"rel/cache", @"/home/u"),
               @"/home/u/.cache/thumbnails", "relative XDG_CACHE_HOME is ignored");
    PASS_EQUAL(GWThumbnailCacheDirectory(@"/x/cache", @"/home/u"),
               @"/x/cache/thumbnails", "absolute XDG_CACHE_HOME is used");
  END_SET("cache directory")

  START_SET("URI and file name")
    PASS_EQUAL(GWThumbnailURIForPath(@"/home/jens/photos/me.png"),
               @"file:///home/jens/photos/me.png", "plain path");
    PASS_EQUAL(GWThumbnailFileNameForURI(@"file:///home/jens/photos/me.png"),
               @"c6ee772d9e49320e97ec29a7eb5b1697.png",
               "the standard's own example hash");
    PASS_EQUAL(GWThumbnailURIForPath(@"/tmp/a b/x#y%z;?[]^`{|}\"<>.AppImage"),
               @"file:///tmp/a%20b/x%23y%25z%3B%3F%5B%5D%5E%60%7B%7C%7D%22%3C%3E.AppImage",
               "unsafe characters are escaped in uppercase hex");
    PASS_EQUAL(GWThumbnailURIForPath(@"/k/!$&'()*+,-.:=@_~"),
               @"file:///k/!$&'()*+,-.:=@_~",
               "characters GLib leaves alone stay as they are");
    PASS_EQUAL(GWThumbnailURIForPath(@"/k/ä.AppImage"),
               @"file:///k/%C3%A4.AppImage", "non-ASCII is escaped as UTF-8 bytes");
    PASS(GWThumbnailURIForPath(@"rel/x.AppImage") == nil, "relative path has no URI");
    PASS_EQUAL(GWThumbnailPathForURI(@"file:///tmp/a%20b/%C3%A4.AppImage"),
               @"/tmp/a b/ä.AppImage", "file URI decodes back to its path");
    PASS(GWThumbnailPathForURI(@"http://host/x.png") == nil, "other schemes have no path");
    PASS(GWThumbnailPathForURI(@"file:///a%2") == nil, "a broken escape has no path");
    PASS(GWThumbnailPathForURI(@"file:///a%00b") == nil, "an escaped NUL has no path");
  END_SET("URI and file name")

  START_SET("size directories")
    PASS_EQUAL(GWThumbnailSizeDirectoryForPixels(48), @"normal", "48 -> normal");
    PASS_EQUAL(GWThumbnailSizeDirectoryForPixels(128), @"normal", "128 -> normal");
    PASS_EQUAL(GWThumbnailSizeDirectoryForPixels(129), @"large", "129 -> large");
    PASS_EQUAL(GWThumbnailSizeDirectoryForPixels(256), @"large", "256 -> large");
    PASS_EQUAL(GWThumbnailSizeDirectoryForPixels(257), @"x-large", "257 -> x-large");
    PASS_EQUAL(GWThumbnailSizeDirectoryForPixels(1024), @"xx-large", "1024 -> xx-large");
    PASS_EQUAL(GWThumbnailSizeDirectoryForPixels(4000), @"xx-large", "above 1024 -> xx-large");
    PASS(GWThumbnailPixelsForSizeDirectory(@"normal") == 128, "normal is 128");
    PASS(GWThumbnailPixelsForSizeDirectory(@"x-large") == 512, "x-large is 512");
    PASS(GWThumbnailPixelsForSizeDirectory(@"fail") == 0, "fail is no size directory");
    PASS([GWThumbnailSizeDirectories() count] == 4, "four size directories");
    PASS_EQUAL(GWThumbnailFailureDirectoryName(@"gershwin-workspace", @"1.1.0"),
               @"gershwin-workspace-1.1.0", "fail directory is program-version");
  END_SET("size directories")

  START_SET("text chunks")
    NSMutableData *png = pngHead();
    appendText(png, "Thumb::URI", "file:///x.AppImage");
    appendText(png, "Thumb::MTime", "123");
    appendText(png, "Software", "caf\xe9");
    appendChunk(png, "IDAT", "xx", 2);
    appendText(png, "After", "idat");
    appendChunk(png, "IEND", NULL, 0);
    NSDictionary *text = GWThumbnailTextChunksInPNG(png);
    PASS_EQUAL([text objectForKey: GWThumbnailKeyURI], @"file:///x.AppImage", "URI read");
    PASS_EQUAL([text objectForKey: GWThumbnailKeyMTime], @"123", "MTime read");
    PASS_EQUAL([text objectForKey: GWThumbnailKeySoftware], @"café", "values are Latin-1");
    PASS([text objectForKey: @"After"] == nil, "chunks after IDAT are not read");

    NSData *head = [png subdataWithRange: NSMakeRange(0, [png length] - 30)];
    NSData *cut = [png subdataWithRange: NSMakeRange(0, 8 + 25 + 12 + 5)];
    PASS([[GWThumbnailTextChunksInPNG(head) objectForKey: GWThumbnailKeyMTime]
           isEqual: @"123"], "a head of the file is enough");
    PASS([GWThumbnailTextChunksInPNG(cut) count] == 0,
         "a chunk cut short is not read");
    PASS(GWThumbnailTextChunksInPNG([@"GIF89a not a png at all"
      dataUsingEncoding: NSASCIIStringEncoding]) == nil, "not a PNG -> nil");
  END_SET("text chunks")

  START_SET("validity")
    NSString *uri = @"file:///a/b.AppImage";
    GWThumbnailFileStamp stamp = { 1700000000LL, 4096LL };
    GWThumbnailFileStamp touched = { 1700000001LL, 4096LL };
    GWThumbnailFileStamp grown = { 1700000000LL, 4097LL };

    PASS(GWThumbnailMatchesFile(textWith(uri, @"1700000000", @"4096", nil), uri, stamp),
         "same URI, mtime and size match");
    PASS(!GWThumbnailMatchesFile(textWith(uri, @"1700000000", @"4096", nil), uri, touched),
         "another mtime does not match");
    PASS(!GWThumbnailMatchesFile(textWith(uri, @"1700000000", @"4096", nil), uri, grown),
         "another size does not match");
    PASS(GWThumbnailMatchesFile(textWith(uri, @"1700000000", nil, nil), uri, grown),
         "Size is only checked when present");
    PASS(!GWThumbnailMatchesFile(textWith(uri, nil, @"4096", nil), uri, stamp),
         "a missing MTime never matches");
    PASS(!GWThumbnailMatchesFile(textWith(@"file:///other", @"1700000000", nil, nil), uri, stamp),
         "another URI does not match");
    PASS(!GWThumbnailMatchesFile(textWith(uri, @"1700000000x", nil, nil), uri, stamp),
         "a MTime that is not an integer does not match");
    PASS(!GWThumbnailMatchesFile(textWith(uri, @"", nil, nil), uri, stamp),
         "an empty MTime does not match");
  END_SET("validity")

  START_SET("sweep decision")
    NSString *uri = @"file:///a/b.AppImage";
    GWThumbnailOriginalState present = { YES, YES, { 1700000000LL, 4096LL } };
    GWThumbnailOriginalState touched = { YES, YES, { 1700000005LL, 4096LL } };
    GWThumbnailOriginalState resized = { YES, YES, { 1700000000LL, 1LL } };
    GWThumbnailOriginalState deleted = { NO, YES, { 0, 0 } };
    GWThumbnailOriginalState unmounted = { NO, NO, { 0, 0 } };
    NSDictionary *ours = textWith(uri, @"1700000000", @"4096", softwareName);
    NSDictionary *theirs = textWith(uri, @"1700000000", @"4096", @"GNOME::ThumbnailFactory");
    NSDictionary *anonymous = textWith(uri, @"1700000000", @"4096", nil);

    PASS(!GWThumbnailIsStale(ours, softwareName, present, 10), "ours, still valid: kept");
    PASS(GWThumbnailIsStale(ours, softwareName, touched, 10), "ours, mtime changed: deleted");
    PASS(GWThumbnailIsStale(ours, softwareName, resized, 10), "ours, size changed: deleted");
    PASS(GWThumbnailIsStale(ours, softwareName, deleted, 10), "ours, original deleted: deleted");
    PASS(!GWThumbnailIsStale(ours, softwareName, unmounted, 86400),
         "ours, directory gone for a day: kept (unmounted media)");
    PASS(GWThumbnailIsStale(ours, softwareName, unmounted, 31 * 86400.0),
         "ours, directory gone for a month: deleted");
    PASS(!GWThumbnailIsStale(theirs, softwareName, deleted, 10),
         "another program's entry is never deleted");
    PASS(!GWThumbnailIsStale(anonymous, softwareName, deleted, 10),
         "an entry without Software is never deleted");
    PASS(GWThumbnailIsStale(textWith(uri, nil, nil, softwareName), softwareName, present, 10),
         "ours without MTime: deleted");
    PASS(!GWThumbnailIsStale(textWith(@"http://h/x", @"1", nil, softwareName),
                              softwareName, deleted, 10),
         "a non-file URI is never judged");
  END_SET("sweep decision")

  START_SET("fit and downscale")
    NSUInteger w = 0, h = 0;
    GWThumbnailFitSize(256, 256, 128, &w, &h);
    PASS(w == 128 && h == 128, "256 square fits 128");
    GWThumbnailFitSize(256, 128, 128, &w, &h);
    PASS(w == 128 && h == 64, "aspect ratio kept");
    GWThumbnailFitSize(64, 48, 128, &w, &h);
    PASS(w == 64 && h == 48, "never upscaled");
    GWThumbnailFitSize(1000, 2, 128, &w, &h);
    PASS(w == 128 && h == 1, "a thin image keeps at least one pixel");

    unsigned char quad[16] = { 255, 0, 0, 255,  0, 0, 0, 0,  0, 0, 0, 0,  0, 0, 0, 0 };
    NSData *one = GWThumbnailDownscaleRGBA([NSData dataWithBytes: quad length: 16], 2, 2, 1, 1);
    const unsigned char *p = [one bytes];
    PASS([one length] == 4 && p[0] == 255 && p[1] == 0 && p[3] == 64,
         "transparent pixels lower alpha but do not darken colour");

    NSMutableData *flat = [NSMutableData dataWithLength: 4 * 4 * 4];
    unsigned char *f = [flat mutableBytes];
    NSUInteger i;
    for (i = 0; i < 16; i++)
      {
        f[i * 4] = 10; f[i * 4 + 1] = 20; f[i * 4 + 2] = 30; f[i * 4 + 3] = 255;
      }
    NSData *half = GWThumbnailDownscaleRGBA(flat, 4, 4, 2, 2);
    p = [half bytes];
    PASS([half length] == 16 && p[12] == 10 && p[13] == 20 && p[14] == 30 && p[15] == 255,
         "a flat image stays flat");
    NSData *odd = GWThumbnailDownscaleRGBA(flat, 4, 4, 3, 3);
    PASS([odd length] == 36, "non-integer ratios produce the asked size");
    PASS(GWThumbnailDownscaleRGBA(flat, 5, 4, 2, 2) == nil, "buffer size mismatch -> nil");
    PASS(GWThumbnailDownscaleRGBA(flat, 4, 4, 8, 8) == nil, "upscale -> nil");
  END_SET("fit and downscale")

  [arp release];
  return 0;
}
