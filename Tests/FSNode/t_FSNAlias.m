/* t_FSNAlias.m - ObjectTesting coverage for Alias records (issue #71:
 * Support Aliases for interoperability).  Headless, Foundation-only.
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */
#import <Foundation/Foundation.h>
#import "Testing.h"
#import <arpa/inet.h>
#import <sys/stat.h>
#include "../../FSNode/FSNAlias.m"

#define BASE @"/tmp/opencode"

static void
putU16(NSMutableData *d, NSUInteger off, uint16_t v)
{
  v = htons(v);
  [d replaceBytesInRange:NSMakeRange(off, 2) withBytes:(uint8_t *)&v];
}

static void
putU32(NSMutableData *d, NSUInteger off, uint32_t v)
{
  v = htonl(v);
  [d replaceBytesInRange:NSMakeRange(off, 4) withBytes:(uint8_t *)&v];
}

static NSData *
pascalString(NSString *s, NSUInteger fieldSize)
{
  NSMutableData *d = [NSMutableData dataWithLength:fieldSize];
  NSData *utf8 = [s dataUsingEncoding:NSUTF8StringEncoding];
  uint8_t len = (uint8_t)[utf8 length];

  [(NSMutableData *)d replaceBytesInRange:NSMakeRange(0, 1) withBytes:&len];
  [(NSMutableData *)d replaceBytesInRange:NSMakeRange(1, [utf8 length])
				withBytes:[utf8 bytes]];
  return d;
}

/* Decode a contiguous lower-case hex string into NSData (for embedding a
 * known-good bookmark captured from a real 10.6.8 installation). */
static NSData *
dataFromHex(const char *hex)
{
  NSUInteger len = strlen(hex);
  NSMutableData *d = [NSMutableData dataWithCapacity: len / 2];
  for (NSUInteger i = 0; i + 1 < len; i += 2)
    {
      unsigned int v = 0;
      uint8_t byte;

      sscanf(hex + i, "%2x", &v);
      byte = (uint8_t)v;
      [d appendBytes: &byte length: 1];
    }
  return d;
}

static void
appendTlv(NSMutableData *d, uint16_t tag, NSData *value)
{
  uint16_t t = htons(tag);
  uint16_t l = htons((uint16_t)[value length]);
  uint8_t pad = 0;

  [d appendBytes:&t length:2];
  [d appendBytes:&l length:2];
  [d appendData:value];
  if ([value length] % 2 != 0)
    {
      [d appendBytes:&pad length:1];
    }
}

/* Hand-built version 2 record: file "report.txt" on volume "MacHD",
 * POSIX path taken from the argument. */
static NSData *
v2RecordWithPosixPath(NSString *posixPath)
{
  NSMutableData *d = [NSMutableData data];
  uint8_t magic[4] = { 'a', 'l', 'i', 's' };

  [d increaseLengthBy:150];   /* v2 fixed header, filled in below */
  [d replaceBytesInRange:NSMakeRange(0, 4) withBytes:magic];

  putU16(d, 6, 2);                        /* version 2 */
  putU16(d, 8, 0);                        /* kind: file */
  [d replaceBytesInRange:NSMakeRange(10, 28)
			withBytes:[pascalString(@"MacHD", 28) bytes]];
  putU32(d, 38, 400000000u);              /* volume date */
  ((uint8_t *)[d mutableBytes])[42] = 'H';
  ((uint8_t *)[d mutableBytes])[43] = '+';
  putU16(d, 44, 0);                       /* disk type: fixed */
  putU32(d, 46, 2);                       /* parent CNID */
  [d replaceBytesInRange:NSMakeRange(50, 64)
			withBytes:[pascalString(@"report.txt", 64) bytes]];
  putU32(d, 114, 777);                    /* target CNID */
  putU32(d, 118, 350000000u);             /* target creation date */

  appendTlv(d, 18, [posixPath dataUsingEncoding:NSUTF8StringEncoding]);
  appendTlv(d, 0xFFFF, [NSData data]);    /* end of record */
  putU16(d, 4, (uint16_t)[d length]);     /* total record size */
  return d;
}

static NSData *
v3FolderRecord(void)
{
  NSMutableData *d = [NSMutableData data];
  uint8_t magic[4] = { 'a', 'l', 'i', 's' };

  [d increaseLengthBy:54];   /* v3 fixed header */
  [d replaceBytesInRange:NSMakeRange(0, 4) withBytes:magic];
  putU16(d, 6, 3);                        /* version 3 */
  putU16(d, 8, 1);                        /* kind: folder */

  NSData *posix = [@"/Users/test/Documents"
		     dataUsingEncoding:NSUTF8StringEncoding];
  appendTlv(d, 18, posix);
  appendTlv(d, 0xFFFF, [NSData data]);
  putU16(d, 4, (uint16_t)[d length]);
  return d;
}

static NSString *
tmpRoot(void)
{
  return [NSString stringWithFormat:@"%@/alias_t_%ld", BASE, (long)getpid()];
}

static BOOL
makeTree(NSString *rel)
{
  NSString *dir = [tmpRoot() stringByAppendingPathComponent: rel];
  return [[NSFileManager defaultManager]
	   createDirectoryAtPath: dir
	   withIntermediateDirectories: YES attributes: nil error: NULL];
}

static NSString *
writeFile(NSString *rel, NSString *contents)
{
  NSString *path = [tmpRoot() stringByAppendingPathComponent: rel];
  NSData *data = [contents dataUsingEncoding:NSUTF8StringEncoding];

  if ([data writeToFile: path atomically: NO] == NO)
    {
      return nil;
    }
  return path;
}

int
main(void)
{
  NSAutoreleasePool *arp = [NSAutoreleasePool new];

  START_SET("v2 record parsing")
    {
      NSData *rec = v2RecordWithPosixPath(@"/Users/test/report.txt");

      PASS([FSNAlias isAliasData: rec], "'alis' magic recognised");
      PASS([FSNAlias isAliasData: [@"junkjunk" dataUsingEncoding:NSUTF8StringEncoding]] == NO,
	   "non-alias data rejected");

      FSNAlias *a = [[FSNAlias alloc] initWithData: rec];
      PASS(a != nil, "v2 record parses");
      PASS([a version] == 2, "version is 2");
      PASS([a isDirectory] == NO, "kind file");
      PASS_EQUAL([a targetName], @"report.txt", "target name");
      PASS_EQUAL([a volumeName], @"MacHD", "volume name");
      PASS_EQUAL([a posixPath], @"/Users/test/report.txt", "posix path tlv");
      PASS([a resolvePath] == nil, "missing target does not resolve");
    }
  END_SET("v2 record parsing")

  START_SET("tlv padding")
    {
      /* "/Users/test/x" is 13 octets - odd, so a pad byte must be
       * skipped before the next TLV. */
      NSData *rec = v2RecordWithPosixPath(@"/Users/test/x");
      FSNAlias *a = [[FSNAlias alloc] initWithData: rec];

      PASS(a != nil, "record with odd-length TLV parses");
      PASS_EQUAL([a posixPath], @"/Users/test/x", "odd-length posix path");
    }
  END_SET("tlv padding")

  START_SET("v3 record parsing")
    {
      FSNAlias *a = [[FSNAlias alloc] initWithData: v3FolderRecord()];

      PASS(a != nil, "v3 record parses");
      PASS([a version] == 3, "version is 3");
      PASS([a isDirectory], "kind folder");
      PASS_EQUAL([a posixPath], @"/Users/test/Documents", "posix path tlv");
    }
  END_SET("v3 record parsing")

  START_SET("serialization round-trip")
    {
      NSString *root = tmpRoot();
      [[NSFileManager defaultManager] removeItemAtPath: root error: NULL];
      PASS(makeTree(@"vol/sub"), "temp tree created");
      NSString *filePath = writeFile(@"vol/sub/report.txt", @"hello");
      PASS(filePath != nil, "target file written");

      FSNAlias *a = [FSNAlias aliasWithPath: filePath];
      PASS(a != nil, "alias built for real path");
      NSData *data = [a aliasData];
      PASS([data length] >= 150, "record at least minimum size");

      /* Wire format is big-endian and follows the macOS "alis" record the
       * open-source macos-alias encoder emits: first 4 bytes are zero, the
       * total record size is a 16-bit value at offset 4, version (2) at
       * offset 6, kind at offset 8, volume name (Str31) at offset 10. */
      const uint8_t *bytes = [data bytes];
      PASS(bytes[0] == 0 && bytes[1] == 0 && bytes[2] == 0 && bytes[3] == 0,
	   "first 4 bytes are zero");
      uint16_t sizeField = (uint16_t)((bytes[4] << 8) | bytes[5]);
      PASS(sizeField == [data length], "size field is big-endian total at 4");
      uint16_t versionField = (uint16_t)((bytes[6] << 8) | bytes[7]);
      PASS(versionField == 2, "version field is big-endian 2");
      uint16_t kindField = (uint16_t)((bytes[8] << 8) | bytes[9]);
      PASS(kindField == 0, "kind field is file");

      struct stat st;
      PASS(stat([filePath fileSystemRepresentation], &st) == 0, "stat ok");

      FSNAlias *b = [[FSNAlias alloc] initWithData: data];
      PASS(b != nil, "own record parses back");
      PASS_EQUAL([b posixPath], filePath, "posix path round-trips");
      PASS_EQUAL([b targetName], @"report.txt", "name round-trips");
      PASS([b isDirectory] == NO, "kind round-trips");
      /* Spec section 9: a foreign filesystem's inode must NOT be fabricated
       * into the HFS CNID field. */
      PASS([b targetCNID] == 0, "foreign inode not stored as CNID");

      NSString *mount = [b volumeMountPoint];
      BOOL isPrefix = [filePath hasPrefix: mount];
      PASS(isPrefix && [[NSFileManager defaultManager]
			 fileExistsAtPath: mount],
	   "volume mount point recorded");

      [[NSFileManager defaultManager] removeItemAtPath: root error: NULL];
    }
  END_SET("serialization round-trip")

  START_SET("resolution")
    {
      NSString *root = tmpRoot();
      [[NSFileManager defaultManager] removeItemAtPath: root error: NULL];
      makeTree(@"vol/sub");
      NSString *orig = writeFile(@"vol/sub/report.txt", @"hello");

      FSNAlias *a = [FSNAlias aliasWithPath: orig];

      /* Path-first: while the target remains at its path, resolution is by
       * path (spec section 10). */
      PASS_EQUAL([a resolvePath], orig, "resolves while target in place");

      /* The target is moved elsewhere.  With no Mac File Manager identity
       * (CNID == 0, the foreign case), there is no additional identity to
       * locate it by, so resolution fails (Tier C, spec section 25). */
      NSFileManager *fm = [NSFileManager defaultManager];
      makeTree(@"vol/other/deep/nest");
      NSString *moved = [tmpRoot()
			  stringByAppendingPathComponent:
			    @"vol/other/deep/nest/report.txt"];
      PASS([fm moveItemAtPath: orig toPath: moved error: NULL],
	   "target moved away");

      PASS([a resolvePath] == nil,
	   "no relocation recovery without identity (Tier C)");

      /* Pathname-first behaviour: an identically-named replacement at the
       * original path resolves to that replacement (spec section 10). */
      NSString *imposter = writeFile(@"vol/sub/report.txt", @"fake");
      PASS(imposter != nil, "different file at old path");
      PASS_EQUAL([a resolvePath], imposter,
		 "path-first resolves to same-named replacement");

      /* With the replacement gone as well, there is nothing to resolve. */
      [fm removeItemAtPath: imposter error: NULL];
      PASS([a resolvePath] == nil, "deleted target does not resolve");

      [[NSFileManager defaultManager] removeItemAtPath: root error: NULL];
    }
  END_SET("resolution")

  START_SET("10.6 bookmark (Finder interoperability)")
    {
      /* Reference bookmark captured from a real 10.6.8 installation: a
       * hand-built bookmark with the CNID array omitted and the volume UUID
       * left empty, since GNUstep has no CNID and no volume UUID for a Mac-only
       * path.  A bookmark of this form (no CNID, empty UUID) resolves to the
       * file on 10.6.8 via the path list alone.  The encoder must reproduce
       * these exact bytes. */
  static const char *refHex =
      "626f6f6bc4010000000001101000000010010000050000000101000055736572"
      "730000000400000001010000757365720200000001010000626d000003000000"
      "01010000737263000a00000001010000777366696c652e747874000014000000"
      "010600000400000014000000200000002c000000380000001800000001020000"
      "01000000000000000f0000000000000000000000000000000400000003030000"
      "030000000400000003030000f50100000c000000010100004d6163696e746f73"
      "6820484408000000040300000000000000000000080000000004000000000000"
      "00000000000000000101000018000000010200008100000001000800ef3f0000"
      "01000800000000000000000001000000010100002f0000000000000001050000"
      "a8000000feffffff01000000000000000c000000041000004c00000000000000"
      "10100000680000000000000002200000fc0000000000000010200000a0000000"
      "0000000011200000d40000000000000012200000b40000000000000013200000"
      "c40000000000000020200000dc00000000000000302000000801000000000000"
      "01c00000880000000000000011c00000140000000000000012c0000094000000"
      "00000000";
      NSData *reference = dataFromHex(refHex);

      /* Built with the same parameters as the reference: volume name
       * "Macintosh HD", empty volume UUID. */
      NSData *bm = [FSNAlias aliasBookmarkForTargetPath:
		      @"/Users/user/bm/src/wsfile.txt"
		      volumeName: @"Macintosh HD"
		      volumeUUID: @""];
      PASS(bm != nil, "bookmark built");
      PASS([bm length] == [reference length],
	   "bookmark length matches 10.6.8 reference");
      PASS([bm isEqual: reference], "bookmark bytes match 10.6.8 reference");

      /* Structural checks independent of the captured reference. */
      const uint8_t *b = [bm bytes];
      PASS(memcmp(b, "book", 4) == 0, "bookmark magic present");
      uint32_t ver = (uint32_t)b[8] | ((uint32_t)b[9] << 8)
		     | ((uint32_t)b[10] << 16) | ((uint32_t)b[11] << 24);
      PASS(ver == 0x10010000, "bookmark version 0x10010000");

      /* isAliasData must accept the bookmark form too. */
      PASS([FSNAlias isAliasData: bm], "isAliasData accepts bookmark");
    }
  END_SET("10.6 bookmark (Finder interoperability)")

  [arp release];
  return 0;
}
