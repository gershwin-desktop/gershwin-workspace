/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 */
#import <Foundation/Foundation.h>
#import "Testing.h"
#import "FSNAliasFile.h"
#import "GSFileMetadata.h"
#include <unistd.h>
#ifdef __linux__
# include <sys/xattr.h>
#endif

static NSString *root;

static void
put(NSString *name, NSData *d)
{
  [d writeToFile: [root stringByAppendingPathComponent: name] atomically: YES];
}

/* AppleDouble V2 with the given entries, built by hand so the test does not
 * depend on the writer under test. */
static NSData *
appleDouble(NSData *finderInfo, NSData *rsrc)
{
  NSMutableData *d = [NSMutableData data];
  uint8_t hdr[26] = {0x00,0x05,0x16,0x07, 0x00,0x02,0x00,0x00};
  uint8_t desc[24] = {0};
  uint32_t fiOff = 26 + 24;
  uint32_t rfOff = fiOff + (uint32_t)[finderInfo length];
  uint32_t v;

  hdr[25] = 2;
#define PUT32(o, x) do { v = (x); desc[o] = v >> 24; desc[o+1] = v >> 16; \
  desc[o+2] = v >> 8; desc[o+3] = v; } while (0)
  PUT32(0, 9); PUT32(4, fiOff); PUT32(8, (uint32_t)[finderInfo length]);
  PUT32(12, 2); PUT32(16, rfOff); PUT32(20, (uint32_t)[rsrc length]);
  [d appendBytes: hdr length: 26];
  [d appendBytes: desc length: 24];
  [d appendData: finderInfo];
  [d appendData: rsrc];
  return d;
}

/* Fork with data "BB" (id 5, offset 0) and "AA" (id 3, offset aaOff). */
static NSData *
twoResourceFork(uint8_t aaOff)
{
  enum { kMap = 28 + 2 + 8 + 24 };
  uint8_t hdr[16] = {0,0,1,0, 0,0,1,0x0c, 0,0,0,12, 0,0,0,kMap};
  uint8_t data[12] = {0,0,0,2,'B','B', 0,0,0,2,'A','A'};
  uint8_t map[kMap] = {0};
  NSMutableData *m = [NSMutableData dataWithBytes: hdr length: 16];

  memcpy(map, hdr, 16);
  map[25] = 28; map[27] = kMap;
  memcpy(map + 30, "alis", 4);
  map[35] = 1; map[37] = 10;
  map[39] = 5; map[40] = 0xff; map[41] = 0xff; map[45] = 0;
  map[51] = 3; map[52] = 0xff; map[53] = 0xff; map[57] = aaOff;
  [m increaseLengthBy: 240];
  [m appendBytes: data length: 12];
  [m appendBytes: map length: kMap];
  return m;
}

static NSData *
finderInfo(BOOL alias)
{
  uint8_t fi[32] = {0};

  if (alias)
    {
      fi[8] = 0x80;
    }
  return [NSData dataWithBytes: fi length: 32];
}

static NSData *
firstResource(NSString *type, NSData *fork)
{
  return [GSFileMetadata firstDataForResourceType:
	    [GSFileMetadata osTypeFromString: type] inFork: fork];
}

/* The resource fork exactly as the first alias writer laid it out (kept
 * byte for byte as a fixture): type count 1 instead of 0 and a reference list
 * offset of 18, which points past the end of its 46 byte map. */
static NSData *
oldWriterFork(NSData *alis)
{
  static const uint8_t prefix[28] = {
    0x00,0x00,0x01,0x00, 0x00,0x00,0xa7,0x7a,
    0x00,0x00,0xa6,0x7a, 0x00,0x00,0x00,0x46,
    0x6b,0x73,0x73,0x21, 0x4c,0x00,0x00,0x00,
    0x00,0x1c,0x00,0x46
  };
  static const uint8_t tl[10] = { 0,1, 'a','l','i','s', 0,0, 0,0x12 };
  static const uint8_t rl[8] = { 0,0, 0xff,0xff, 0,0,0,0 };
  uint32_t dataLen = (uint32_t)[alis length] + 4;
  uint32_t mapOff = 256 + dataLen;
  uint8_t hdr[16] = { 0,0,1,0, mapOff >> 24, mapOff >> 16, mapOff >> 8, mapOff,
		      dataLen >> 24, dataLen >> 16, dataLen >> 8, dataLen,
		      0,0,0,46 };
  uint8_t map[46];
  uint32_t n = (uint32_t)[alis length];
  uint8_t hsz[4] = { n >> 24, n >> 16, n >> 8, n };
  NSMutableData *out = [NSMutableData dataWithBytes: hdr length: 16];

  memcpy(map, prefix, 28);
  memcpy(map, hdr, 16);
  memcpy(map + 28, tl, 10);
  memcpy(map + 38, rl, 8);
  [out increaseLengthBy: 240];
  [out appendBytes: hsz length: 4];
  [out appendData: alis];
  [out appendBytes: map length: 46];
  return out;
}

int
main(void)
{
  NSAutoreleasePool *arp = [NSAutoreleasePool new];
  NSFileManager *fm = [NSFileManager defaultManager];

  root = [NSString stringWithFormat: @"%@/links_alias_%ld",
		   NSTemporaryDirectory(), (long)getpid()];
  [fm removeItemAtPath: root error: NULL];
  [fm createDirectoryAtPath: root withIntermediateDirectories: YES
		 attributes: nil error: NULL];
  NSString *target = [root stringByAppendingPathComponent: @"notes.txt"];
  [@"data" writeToFile: target atomically: YES];

  START_SET("alias file written by us resolves again")
    {
      NSString *p = [FSNAlias writeAliasFileForPath: target inDirectory: root];
      FSNAlias *a = [FSNAlias aliasWithContentsOfFile: p];

      PASS(a != nil, "classic form: resource fork 'alis' found");
      PASS_EQUAL([a resolvePath], target, "classic form resolves");

      p = [FSNAlias writeAliasBookmarkForTargetPath: target inDirectory: root];
      a = [FSNAlias aliasWithContentsOfFile: p];
      PASS(a != nil, "bookmark form: data fork 'book' found");
      PASS_EQUAL([a resolvePath], target, "bookmark form resolves");
    }
  END_SET("alias file written by us resolves again")

  START_SET("resource fork parsing follows the Resource Manager layout")
    {
      FSNAlias *src = [FSNAlias aliasWithPath: target];
      NSData *fork = [src aliasResourceForkData];
      NSData *rec = firstResource(@"alis", fork);

      PASS_EQUAL(rec, [src aliasData], "alis resource returned byte for byte");
      PASS(firstResource(@"icns", fork) == nil,
	   "other type is absent");
      PASS(firstResource(@"alis", [fork subdataWithRange:
					       NSMakeRange(0, 100)]) == nil,
	   "truncated fork rejected");
      PASS(firstResource(@"alis", [NSData data]) == nil,
	   "empty fork rejected");

      /* A hand-made fork with two resources of the type: the lowest id wins,
       * and the 24 bit data offsets are honoured. */
      NSData *m = twoResourceFork(6);
      NSData *two = firstResource(@"alis", m);
      PASS_EQUAL(two, [NSData dataWithBytes: "AA" length: 2],
		 "lowest resource id of the type wins");

      /* An offset beyond the data area must be refused, not read. */
      PASS(firstResource(@"alis", twoResourceFork(0xf0)) == nil,
	   "data offset beyond the data area rejected");
    }
  END_SET("resource fork parsing follows the Resource Manager layout")

  START_SET("which files count as aliases")
    {
      FSNAlias *src = [FSNAlias aliasWithPath: target];
      NSData *fork = [src aliasResourceForkData];
      NSData *bookmark = [FSNAlias aliasBookmarkForTargetPath: target];

      /* 10.6 Finder form: empty data fork, 'alis' resource, kIsAlias. */
      put(@"a.bin", [NSData data]);
      put(@"._a.bin", appleDouble(finderInfo(YES), fork));
      FSNAlias *a = [FSNAlias aliasWithContentsOfFile:
			 [root stringByAppendingPathComponent: @"a.bin"]];
      PASS_EQUAL([a resolvePath], target, "sidecar fork alias resolves");

      /* Bookmark in the data fork with the flag. */
      put(@"c.bin", bookmark);
      put(@"._c.bin", appleDouble(finderInfo(YES), [NSData data]));
      a = [FSNAlias aliasWithContentsOfFile:
	       [root stringByAppendingPathComponent: @"c.bin"]];
      PASS_EQUAL([a resolvePath], target, "data fork bookmark resolves");

      /* Same bytes without kIsAlias: just a file that starts with "book". */
      put(@"d.bin", bookmark);
      put(@"._d.bin", appleDouble(finderInfo(NO), [NSData data]));
      PASS([FSNAlias aliasWithContentsOfFile:
		[root stringByAppendingPathComponent: @"d.bin"]] == nil,
	   "no kIsAlias: not an alias");
      put(@"e.txt", [@"booklet of notes about things" dataUsingEncoding:
				NSUTF8StringEncoding]);
      PASS([FSNAlias isAliasFileAtPath:
		[root stringByAppendingPathComponent: @"e.txt"]] == NO,
	   "text starting with book is not an alias");

      /* kIsAlias but nothing usable inside. */
      put(@"f.bin", [NSData data]);
      put(@"._f.bin", appleDouble(finderInfo(YES),
				  [fork subdataWithRange: NSMakeRange(0, 40)]));
      PASS([FSNAlias aliasWithContentsOfFile:
		[root stringByAppendingPathComponent: @"f.bin"]] == nil,
	   "flagged file with broken fork yields nil");

      /* A directory is never an alias file. */
      PASS([FSNAlias isAliasFileAtPath: root] == NO, "directory is no alias");
    }
  END_SET("which files count as aliases")

  START_SET("aliases written by the first writer still open")
    {
      FSNAlias *src = [FSNAlias aliasWithPath: target];
      NSData *fi = [src aliasFinderInfoData];
      NSData *oldFork = oldWriterFork([src aliasData]);

      /* That writer stored a "._" sidecar with kIsAlias and the fork above
       * next to an empty data fork. */
      put(@"old.bin", [NSData data]);
      put(@"._old.bin", appleDouble(fi, oldFork));
      FSNAlias *a = [FSNAlias aliasWithContentsOfFile:
			 [root stringByAppendingPathComponent: @"old.bin"]];
      PASS_EQUAL([a resolvePath], target, "first-writer alias resolves");
    }
  END_SET("aliases written by the first writer still open")

  START_SET("extended attributes carry the forks")
    {
      NSString *p = [root stringByAppendingPathComponent: @"x.bin"];
      FSNAlias *src = [FSNAlias aliasWithPath: target];
      NSData *fork = [src aliasResourceForkData];
      NSData *fi = finderInfo(YES);

      put(@"x.bin", [NSData data]);
#ifdef __linux__
      if (setxattr([p fileSystemRepresentation], "user.com.apple.FinderInfo",
		   [fi bytes], [fi length], 0) == 0
	  && setxattr([p fileSystemRepresentation],
		      "user.com.apple.ResourceFork",
		      [fork bytes], [fork length], 0) == 0)
	{
	  PASS_EQUAL([[FSNAlias aliasWithContentsOfFile: p] resolvePath], target,
		     "alias from user.com.apple.* attributes resolves");
	}
      else
	{
	  fprintf(stderr, "SKIPPED xattr set (no xattr support here)\n");
	}
#endif
    }
  END_SET("extended attributes carry the forks")

  [fm removeItemAtPath: root error: NULL];
  [arp release];
  return 0;
}
