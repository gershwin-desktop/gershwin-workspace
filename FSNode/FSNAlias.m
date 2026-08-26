/* FSNAlias.m - implementation of Alias records.
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

#import "FSNAlias.h"

#include <sys/stat.h>
#include <string.h>

/* Seconds between 1904-01-01 (classic Mac epoch) and 1970-01-01. */
#define MAC_EPOCH_OFFSET 2082844800u

/* How deep below the last known ancestor the inode search may descend. */
#define RESOLVE_MAX_DEPTH 8

#define V2_HEADER_LEN 150
#define V3_HEADER_LEN 54

/* TLV tags from the alias format specification. */
#define TLV_CARBON_FOLDERNAME	0
#define TLV_CNID_PATH		1
#define TLV_CARBON_PATH		2
#define TLV_END			0xFFFF
#define TLV_UNICODE_NAME	14
#define TLV_UNICODE_VOLUME	15
#define TLV_POSIX_PATH		18
#define TLV_VOLUME_POSIX_PATH	19

/* Bookmark (Finder 10.6 format) record type codes.
 * A bookmark is a header followed by a Table of Contents (TOC) that maps
 * numeric keys to data records; each data record is
 *   [length:4 LE][typecode:4 LE][payload:length], 4-byte aligned.
 * The data-record offset stored in the TOC is relative to the header size
 * (the data area base).  The 10.6 bookmark header is 16 bytes: the 4-byte
 * marker "book", the total size (LE), the version (0x10010000), and the
 * header size (16).  Immediately after the header comes a 4-byte TOC offset
 * field that points at the volume mount-point record's type field. */
#define BMK_TOC_MAGIC		0xFFFFFFFEu
#define BMK_STRING		0x0100u
#define BMK_ARRAY		0x0600u
#define BMK_URL			0x0900u

#define BMK_KEY_PATH		0x1004u  /* array of path components */
#define BMK_KEY_CNID_PATH	0x1005u  /* array of CNIDs (one per component) */
#define BMK_KEY_FILE_NAME	0x1020u  /* target file name */
#define BMK_KEY_VOLUME_PATH	0x2002u  /* volume mount path, e.g. "/" */
#define BMK_KEY_VOLUME_NAME	0x2010u  /* volume name, e.g. "Macintosh HD" */
#define BMK_KEY_DISPLAY_NAME	0xF017u  /* display name */

/* Resolve one bookmark data item referenced by a TOC entry (relative offset).
 * Returns an NSString (string/URL) or an NSArray of NSString (array record),
 * or nil.  Autoreleased. */
static uint16_t readU16(const uint8_t *b, NSUInteger off);
static uint32_t readU32(const uint8_t *b, NSUInteger off);
static uint32_t readU32LE(const uint8_t *b, NSUInteger off);

static id
fsnaResolveBookmarkItem(const uint8_t *b, NSUInteger len,
			NSUInteger hdrsize, NSUInteger relOff,
			unsigned depth)
{
  NSUInteger o = hdrsize + relOff;

  if (depth > 32)
    {
      return nil;
    }
  if (o + 8 > len)
    {
      return nil;
    }
  uint32_t dlen = readU32LE(b, o);
  uint32_t tc = readU32LE(b, o + 4);
  uint32_t dtype = tc & 0xFFFFFF00u;
  const uint8_t *payload = b + o + 8;

  if (dlen > len || o + 8 + (NSUInteger)dlen > len)
    {
      return nil;
    }
  if (dtype == BMK_STRING)
    {
      return [[[NSString alloc] initWithBytes: payload
				       length: dlen
				     encoding: NSUTF8StringEncoding] autorelease];
    }
  else if (dtype == BMK_URL)
    {
      /* subtype 1 = absolute URL string. */
      if ((tc & 0xFFu) == 1)
	{
	  return [[[NSString alloc] initWithBytes: payload
					   length: dlen
					 encoding: NSUTF8StringEncoding]
		   autorelease];
	}
      return nil;
    }
  else if (dtype == BMK_ARRAY)
    {
      NSMutableArray *arr = [NSMutableArray array];
      uint32_t i;

      for (i = 0; i + 4 <= dlen; i += 4)
	{
	  uint32_t eo = readU32LE(payload, i);
	  id item = fsnaResolveBookmarkItem(b, len, hdrsize, eo, depth + 1);

	  if (item != nil)
	    {
	      [arr addObject: item];
	    }
	}
      return arr;
    }
  return nil;
}

static uint16_t
readU16(const uint8_t *b, NSUInteger off)
{
  return (uint16_t)((b[off] << 8) | b[off + 1]);
}

static uint32_t
readU32(const uint8_t *b, NSUInteger off)
{
  return ((uint32_t)b[off] << 24) | ((uint32_t)b[off + 1] << 16)
    | ((uint32_t)b[off + 2] << 8) | (uint32_t)b[off + 3];
}

/* Little-endian readers for the 10.6+ "book" bookmark data fork format. */
static uint32_t
readU32LE(const uint8_t *b, NSUInteger off)
{
  return (uint32_t)b[off] | ((uint32_t)b[off + 1] << 8)
    | ((uint32_t)b[off + 2] << 16) | ((uint32_t)b[off + 3] << 24);
}

static void
fsnaWriteU16(NSMutableData *d, NSUInteger off, uint16_t v)
{
  uint8_t *b = [d mutableBytes];

  b[off] = (uint8_t)(v >> 8);
  b[off + 1] = (uint8_t)v;
}

/* Little-endian 32-bit writer, used for the 10.6 "book" bookmark format. */
static void
fsnaWriteU32LEInto(uint8_t *b, NSUInteger off, uint32_t v)
{
  b[off] = (uint8_t)(v & 0xff);
  b[off + 1] = (uint8_t)((v >> 8) & 0xff);
  b[off + 2] = (uint8_t)((v >> 16) & 0xff);
  b[off + 3] = (uint8_t)((v >> 24) & 0xff);
}

static void
fsnaAppendU32LE(NSMutableData *d, uint32_t v)
{
  uint8_t b[4];

  fsnaWriteU32LEInto(b, 0, v);
  [d appendBytes: b length: 4];
}

static void
fsnaWriteU32(NSMutableData *d, NSUInteger off, uint32_t v)
{
  uint8_t *b = [d mutableBytes];

  b[off] = (uint8_t)(v >> 24);
  b[off + 1] = (uint8_t)(v >> 16);
  b[off + 2] = (uint8_t)(v >> 8);
  b[off + 3] = (uint8_t)v;
}

/* Big-endian writers for raw byte buffers (resource fork / AppleDouble). */
static void
fsnaPutBE16(uint8_t *b, uint16_t v)
{
  b[0] = (uint8_t)(v >> 8);
  b[1] = (uint8_t)v;
}

static void
fsnaPutBE32(uint8_t *b, uint32_t v)
{
  b[0] = (uint8_t)(v >> 24);
  b[1] = (uint8_t)(v >> 16);
  b[2] = (uint8_t)(v >> 8);
  b[3] = (uint8_t)v;
}

/* Build the TLV value for the UTF-16 name/volume entries (a 16-bit character
 * count followed by the big-endian UTF-16 bytes). */
static NSData *
fsnaUtf16TlvValue(NSString *s)
{
  NSData *u = [s dataUsingEncoding: NSUTF16BigEndianStringEncoding];
  NSUInteger chars = [u length] / 2;
  NSMutableData *v = [NSMutableData dataWithCapacity: 2 + [u length]];
  uint8_t ln[2];

  fsnaPutBE16(ln, (uint16_t)chars);
  [v appendBytes: ln length: 2];
  [v appendData: u];
  return v;
}

static NSString *
readPascalString(const uint8_t *b, NSUInteger off, NSUInteger fieldSize)
{
  NSUInteger len = MIN((NSUInteger)b[off], fieldSize - 1);

  if (len == 0)
    {
      return nil;
    }
  return [[NSString alloc] initWithBytes: b + off + 1
				  length: len
				encoding: NSUTF8StringEncoding];
}

static void
writePascalString(NSMutableData *d, NSUInteger off,
		  NSUInteger fieldSize, NSString *s)
{
  uint8_t *b = [d mutableBytes];
  NSData *utf8 = [s dataUsingEncoding:NSUTF8StringEncoding];
  NSUInteger len = MIN([utf8 length], fieldSize - 1);

  if (s == nil || len == 0)
    {
      return;
    }
  b[off] = (uint8_t)len;
  memcpy(b + off + 1, [utf8 bytes], len);
}

static void
fsnaAppendTlv(NSMutableData *d, uint16_t tag, NSData *value)
{
  uint8_t header[4];
  uint8_t pad = 0;

  header[0] = (uint8_t)(tag >> 8);
  header[1] = (uint8_t)tag;
  header[2] = (uint8_t)((uint16_t)[value length] >> 8);
  header[3] = (uint8_t)(uint16_t)[value length];
  [d appendBytes:header length:4];
  [d appendData:value];
  if ([value length] % 2 != 0)
    {
      [d appendBytes:&pad length:1];
    }
}

/* ------------------------------------------------------------------ */
/* 10.6 "bookmark" (data-fork) encoder for Finder interoperability.    */
/*                                                                     */
/* A 10.6 alias stores a bookmark in the file's data fork.  The format */
/* is a 16-byte header followed by a record region whose offsets are   */
/* relative to byte 16, then a table of contents whose magic is        */
/* 0xfffffffe; each TOC entry is [key][recordOffset(rel16)][reserved]. */
/*                                                                     */
/* Resolution on 10.6 needs only the target path components plus the   */
/* root-volume markers (0x2002 mount point "/" and 0x2030 "is root").  */
/* The CNID array (0x1005) and the volume UUID (0x2011) are OPTIONAL;  */
/* omitting both lets GNUstep emit a resolvable alias with no          */
/* Finder-specific state.  This was confirmed against a captured       */
/* reference bookmark: a hand-built bookmark with zeroed CNID and      */
/* empty volume UUID resolves to the file on the startup volume.       */
/* ------------------------------------------------------------------ */

static const uint8_t kAliasBookmarkFlags1010[24] = {
  0x01,0x00,0x00,0x00, 0x00,0x00,0x00,0x00,
  0x0f,0x00,0x00,0x00, 0x00,0x00,0x00,0x00,
  0x00,0x00,0x00,0x00, 0x00,0x00,0x00,0x00
};
static const uint8_t kAliasBookmarkFlags2020[24] = {
  0x81,0x00,0x00,0x00, 0x01,0x00,0x08,0x00,
  0xef,0x3f,0x00,0x00, 0x01,0x00,0x08,0x00,
  0x00,0x00,0x00,0x00, 0x00,0x00,0x00,0x00
};

/* Append one bookmark record; return its offset relative to byte 16. */
static uint32_t
fsnaAliasBookmarkRecord(NSMutableData *records, uint32_t *base, uint32_t type,
                        const void *bytes, NSUInteger len)
{
  uint32_t off = *base + (uint32_t)[records length];
  uint8_t hdr[8];

  fsnaWriteU32LEInto(hdr, 0, (uint32_t)len);
  fsnaWriteU32LEInto(hdr, 4, type);
  [records appendBytes: hdr length: 8];
  [records appendBytes: bytes length: len];
  while ([records length] % 4 != 0)
    {
      uint8_t z = 0;
      [records appendBytes: &z length: 1];
    }
  return off;
}

/* Choose a free "<name> alias" / "<name> alias N" path inside directory. */
static NSString *
fsnaUniqueAliasPath(NSString *directory, NSString *name)
{
  NSFileManager *fm = [NSFileManager defaultManager];
  NSString *base = [name stringByDeletingPathExtension];
  NSString *ext = [name pathExtension];
  NSString *aliasName;
  int count = 1;

  if ([base length] == 0)
    {
      base = name;
      ext = nil;
    }
  aliasName = [NSString stringWithFormat: @"%@ %@",
			base, NSLocalizedString(@"alias", @"")];
  if (ext && [ext length])
    {
      aliasName = [aliasName stringByAppendingPathExtension: ext];
    }
  NSString *aliasPath = [directory stringByAppendingPathComponent: aliasName];

  while ([fm fileExistsAtPath: aliasPath])
    {
      NSString *suffix;

      count++;
      suffix = [NSString stringWithFormat: @"%@ %@ %d",
			base, NSLocalizedString(@"alias", @""), count];
      if (ext && [ext length])
	{
	  suffix = [suffix stringByAppendingPathExtension: ext];
	}
      aliasPath = [directory stringByAppendingPathComponent: suffix];
    }
  return aliasPath;
}

@implementation FSNAlias

NSString * const FSNWorkspaceCreateAliasOperation =
  @"WorkspaceCreateAliasOperation";

+ (BOOL)isAliasData:(NSData *)data
{
  if (data == nil || [data length] < 8)
    {
      return NO;
    }
  const uint8_t *b = [data bytes];

  /* Bookmark records begin with "book" (10.6 "book"+"mark" magic block). */
  if (memcmp(b, "book", 4) == 0)
    {
      return YES;
    }
  /* Classic "alis" records.  The canonical macOS layout (kAliasVersionTwo)
   * starts with the record size, then a 4-byte userType of zero, then the
   * 2-byte header constant 0x0160, version and kind.  Our older output and
   * some writers put the literal "alis" at offset 4 (or 0).  Accept all. */
  if (memcmp(b, "alis", 4) == 0)
    {
      return YES;
    }
  if ([data length] >= 12 && memcmp(b + 4, "alis", 4) == 0)
    {
      return YES;
    }
  if ([data length] >= 10 && b[8] == 0x01 && b[9] == 0x60)
    {
      /* Canonical macOS "alis": header constant 0x0160 at offset 8. */
      return YES;
    }
  if ([data length] >= 10 && b[0] == 0 && b[1] == 0 && b[2] == 0 && b[3] == 0
      && readU16(b, 6) == 2)
    {
      /* macos-alias layout: zero prefix, record size (16-bit) at offset 4,
       * version 2 at offset 6, kind at offset 8. */
      return YES;
    }
  return NO;
}

+ (NSString *)writeAliasFileForPath:(NSString *)path
			inDirectory:(NSString *)directory
{
  FSNAlias *a = [self aliasWithPath: path];

  if (a == nil)
    {
      return nil;
    }
  return [self _writeAlias: a inDirectory: directory];
}

+ (NSString *)writeAliasFileForTargetPath:(NSString *)targetPath
				inDirectory:(NSString *)directory
				  volumeName:(NSString *)volumeName
{
  FSNAlias *a = [self aliasWithTargetPath: targetPath
			       volumeName: volumeName];

  if (a == nil)
    {
      return nil;
    }
  return [self _writeAlias: a inDirectory: directory];
}

/* Build the 10.6 bookmark data for a target path.  The startup volume is
 * identified implicitly (root volume, mount point "/"); no CNID or volume
 * UUID is required, so GNUstep can produce this with no Finder-specific
 * state.  volumeName/volumeUUID, when known, are recorded but may be empty. */
+ (NSData *)aliasBookmarkForTargetPath:(NSString *)targetPath
			    volumeName:(NSString *)volumeName
			    volumeUUID:(NSString *)volumeUUID
{
  NSArray *raw = [targetPath componentsSeparatedByString: @"/"];
  NSMutableArray *comps = [NSMutableArray array];

  for (NSString *c in raw)
    {
      if ([c length] > 0)
	{
	  [comps addObject: c];
	}
    }

  uint32_t base = 4;
  NSMutableData *records = [NSMutableData data];
  NSMutableArray *compOffs = [NSMutableArray array];

  for (NSString *c in comps)
    {
      NSData *s = [c dataUsingEncoding: NSUTF8StringEncoding];
      uint32_t o = fsnaAliasBookmarkRecord(records, &base, 0x0101,
					   [s bytes], [s length]);
      [compOffs addObject: [NSNumber numberWithUnsignedInt: o]];
    }

  /* 0x1004 target path array (no count field; count = length / 4). */
  NSMutableData *arr = [NSMutableData data];
  for (NSNumber *o in compOffs)
    {
      fsnaAppendU32LE(arr, [o unsignedIntValue]);
    }
  uint32_t pathArrOff = fsnaAliasBookmarkRecord(records, &base, 0x0601,
						[arr bytes], [arr length]);

   /* 0x1010 target flags (fixed, copied from a captured reference bookmark). */
  uint32_t f1010 = fsnaAliasBookmarkRecord(records, &base, 0x0201,
					   kAliasBookmarkFlags1010, 24);

  /* 0xc001 containing-folder index, 0xc012 creator UID. */
  uint8_t i32buf[4];
  fsnaWriteU32LEInto(i32buf, 0, (uint32_t)MAX(0, (int)[comps count] - 2));
  uint32_t c001 = fsnaAliasBookmarkRecord(records, &base, 0x0303, i32buf, 4);
  fsnaWriteU32LEInto(i32buf, 0, 501);
  uint32_t c012 = fsnaAliasBookmarkRecord(records, &base, 0x0303, i32buf, 4);

  /* 0xc011 creator name: reuse the "user" path component when present. */
  uint32_t c011;
  NSUInteger userIdx = [comps indexOfObject: @"user"];
  if (userIdx != NSNotFound)
    {
      c011 = [[compOffs objectAtIndex: userIdx] unsignedIntValue];
    }
  else
    {
      NSData *u = [@"user" dataUsingEncoding: NSUTF8StringEncoding];
      c011 = fsnaAliasBookmarkRecord(records, &base, 0x0101,
				     [u bytes], [u length]);
    }

  if (volumeName == nil)
    {
      volumeName = @"";
    }
  NSData *vold = [volumeName dataUsingEncoding: NSUTF8StringEncoding];
  uint32_t v2010 = fsnaAliasBookmarkRecord(records, &base, 0x0101,
					   [vold bytes], [vold length]);

  /* 0x2012 volume size (i64) and 0x2013 creation date (f64): both 0. */
  uint8_t zero8[8] = {0};
  uint32_t v2012 = fsnaAliasBookmarkRecord(records, &base, 0x0304, zero8, 8);
  uint32_t v2013 = fsnaAliasBookmarkRecord(records, &base, 0x0400, zero8, 8);

  if (volumeUUID == nil)
    {
      volumeUUID = @"";
    }
  NSData *uuid = [volumeUUID dataUsingEncoding: NSUTF8StringEncoding];
  uint32_t v2011 = fsnaAliasBookmarkRecord(records, &base, 0x0101,
					   [uuid bytes], [uuid length]);

  /* 0x2020 volume flags (fixed). */
  uint32_t v2020 = fsnaAliasBookmarkRecord(records, &base, 0x0201,
					   kAliasBookmarkFlags2020, 24);

  /* 0x2002 volume mount point "/" - the last record before the TOC. */
  NSData *slash = [@"/" dataUsingEncoding: NSUTF8StringEncoding];
  uint32_t v2002 = fsnaAliasBookmarkRecord(records, &base, 0x0101,
					   [slash bytes], 1);

   /* Post-record region: 0x2030 boolean (len 0, type 0x0501) + 4 mystery
    * bytes (copied verbatim from a captured reference bookmark). */
  NSMutableData *post = [NSMutableData data];
  uint8_t boolrec[8] = {0,0,0,0, 0x01,0x05,0,0};
  [post appendBytes: boolrec length: 8];
  uint8_t mystery[4] = {0xa8,0,0,0};
  [post appendBytes: mystery length: 4];
  uint32_t volrootRel16 = (20 + (uint32_t)[records length]) - 16;

  uint32_t tocKeys[12] = {
    0x1004, 0x1010, 0x2002, 0x2010, 0x2011, 0x2012,
    0x2013, 0x2020, 0x2030, 0xc001, 0xc011, 0xc012
  };
  uint32_t tocRecs[12] = {
    pathArrOff, f1010, v2002, v2010, v2011, v2012,
    v2013, v2020, volrootRel16, c001, c011, c012
  };

  NSMutableData *toc = [NSMutableData data];
  uint8_t m[4];
  fsnaWriteU32LEInto(m, 0, 0xfffffffe); [toc appendBytes: m length: 4];
  fsnaWriteU32LEInto(m, 0, 1);          [toc appendBytes: m length: 4];
  fsnaWriteU32LEInto(m, 0, 0);          [toc appendBytes: m length: 4];
  fsnaWriteU32LEInto(m, 0, 12);         [toc appendBytes: m length: 4];
  for (int i = 0; i < 12; i++)
    {
      fsnaWriteU32LEInto(m, 0, tocKeys[i]); [toc appendBytes: m length: 4];
      fsnaWriteU32LEInto(m, 0, tocRecs[i]); [toc appendBytes: m length: 4];
      fsnaWriteU32LEInto(m, 0, 0);          [toc appendBytes: m length: 4];
    }

  uint32_t total = 16 + 4 + (uint32_t)[records length]
		   + (uint32_t)[post length] + (uint32_t)[toc length];
  uint32_t tocOff = 20 + v2002;

  NSMutableData *out = [NSMutableData dataWithCapacity: total];
  [out appendBytes: "book" length: 4];
  fsnaAppendU32LE(out, total);
  fsnaAppendU32LE(out, 0x10010000);
  fsnaAppendU32LE(out, 16);
  fsnaAppendU32LE(out, tocOff);
  [out appendData: records];
  [out appendData: post];
  [out appendData: toc];
  return out;
}

+ (NSData *)aliasBookmarkForTargetPath:(NSString *)targetPath
{
  return [self aliasBookmarkForTargetPath: targetPath
			      volumeName: @""
			      volumeUUID: @""];
}

/* Write a 10.6 bookmark alias file.  The bookmark lives in the data fork;
 * a "._" AppleDouble sidecar carries the Finder Info (type "alis") so the
 * file is recognised as an alias once it reaches a Finder system. */
+ (NSString *)writeAliasBookmarkForTargetPath:(NSString *)targetPath
				  inDirectory:(NSString *)directory
				    volumeName:(NSString *)volumeName
{
  NSData *bm = [self aliasBookmarkForTargetPath: targetPath
					volumeName: volumeName
					volumeUUID: @""];
  if (bm == nil)
    {
      return nil;
    }
  FSNAlias *a = [self aliasWithTargetPath: targetPath volumeName: volumeName];
  if (a == nil)
    {
      return nil;
    }
  NSString *aliasPath = fsnaUniqueAliasPath(directory, [a targetName]);
  if ([bm writeToFile: aliasPath atomically: YES] == NO)
    {
      return nil;
    }
  NSData *fi = [a aliasFinderInfoData];
  NSData *sidecar = fsnaAppleDouble(fi, [NSData data]);
  if (sidecar == nil)
    {
      return nil;
    }
  NSString *sidecarName = [NSString stringWithFormat: @"._%@",
					[aliasPath lastPathComponent]];
  NSString *sidecarPath = [directory stringByAppendingPathComponent: sidecarName];
  if ([sidecar writeToFile: sidecarPath atomically: YES] == NO)
    {
      return nil;
    }
  return aliasPath;
}

+ (NSString *)writeAliasBookmarkForTargetPath:(NSString *)targetPath
				  inDirectory:(NSString *)directory
{
  return [self writeAliasBookmarkForTargetPath: targetPath
				       inDirectory: directory
					 volumeName: @""];
}

/* Shared writer: the alias file itself has an empty data fork; the "alis"
 * resource and Finder Info travel in a "._" AppleDouble sidecar so the file
 * resolves natively on Finder systems once copied there by a Mac-aware tool. */
+ (NSString *)_writeAlias:(FSNAlias *)a inDirectory:(NSString *)directory
{
  NSString *aliasPath = fsnaUniqueAliasPath(directory, [a targetName]);

  if ([[NSData data] writeToFile: aliasPath atomically: YES] == NO)
    {
      return nil;
    }

  NSData *rsrc = [a aliasResourceForkData];
  NSData *fi = [a aliasFinderInfoData];
  NSData *sidecar = fsnaAppleDouble(fi, rsrc);

  if (sidecar == nil)
    {
      return nil;
    }

  NSString *sidecarName = [NSString stringWithFormat: @"._%@",
					[aliasPath lastPathComponent]];
  NSString *sidecarPath = [directory stringByAppendingPathComponent: sidecarName];

  if ([sidecar writeToFile: sidecarPath atomically: YES] == NO)
    {
      return nil;
    }
  return aliasPath;
}

+ (FSNAlias *)aliasWithPath:(NSString *)path
{  struct stat st;
  FSNAlias *a;
  const char *rep = [path fileSystemRepresentation];

  if (rep == NULL || stat(rep, &st) != 0)
    {
      return nil;
    }

  a = [[self alloc] init];
  a->_targetName = [path lastPathComponent];
  a->_posixPath = path;
  a->_isDirectory = S_ISDIR(st.st_mode);
  a->_version = 2;
  /* Spec section 9: do not fabricate an HFS CNID from a foreign filesystem's
   * inode.  Leave the identity fields zero; path-based resolution is used. */
  a->_targetCNID = 0;

  /* The mount point is found by walking up until the device id changes:
   * portable across Linux and the BSDs without any mount-table parsing. */
  {
    NSString *dir = [path stringByDeletingLastPathComponent];
    dev_t dev = st.st_dev;
    NSString *mount = dir;

    while ([dir isEqualToString: @""] == NO && [dir length] > 1)
      {
	struct stat dst;

	if (stat([dir fileSystemRepresentation], &dst) != 0)
	  {
	    break;
	  }
	if (dst.st_dev != dev)
	  {
	    break;
	  }
	mount = dir;
	dir = [dir stringByDeletingLastPathComponent];
      }
    a->_volumeMountPoint = mount;
    if ([mount isEqualTo: @"/"])
      {
	a->_volumeName = @"";
      }
    else
      {
	a->_volumeName = [mount lastPathComponent];
      }
    /* Spec section 9: do not populate the parent CNID from a foreign inode. */
    a->_parentCNID = 0;
    a->_parentName = [mount lastPathComponent];
  }

  return a;
}

+ (FSNAlias *)aliasWithTargetPath:(NSString *)targetPath
			volumeName:(NSString *)volumeName
{
  FSNAlias *a = [[self alloc] init];

  if (a == nil)
    {
      return nil;
    }
  a->_version = 2;
  a->_targetName = [targetPath lastPathComponent];
  a->_posixPath = targetPath;
  a->_isDirectory = NO;
  a->_targetCNID = 0;
  a->_parentCNID = 0;

  if (volumeName == nil || [volumeName length] == 0)
    {
      a->_volumeName = @"Macintosh HD";
    }
  else
    {
      a->_volumeName = volumeName;
    }

  NSString *parentDir = [targetPath stringByDeletingLastPathComponent];
  a->_parentName = [parentDir lastPathComponent];
  if ([targetPath hasPrefix: @"/"])
    {
      a->_volumeMountPoint = @"/";
    }
  else
    {
      a->_volumeMountPoint = a->_volumeName;
    }

  return a;
}

- (instancetype)init
{
  self = [super init];
  if (self != nil)
    {
      _version = 2;
    }
  return self;
}

- (void)dealloc
{
  [_volumeName release];
  [_targetName release];
  [_posixPath release];
  [_volumeMountPoint release];
  [super dealloc];
}

 - (instancetype)_initWithBookmarkData:(NSData *)data
{
    const uint8_t *b = [data bytes];
  NSUInteger len = [data length];
  NSUInteger hdrsize;
  NSUInteger toc = NSNotFound;
  uint32_t count;
  NSUInteger e;
  uint32_t n;
  NSMutableDictionary *tocd;
  NSArray *components = nil;
  NSString *volPath = nil;
  NSString *name = nil;
  NSMutableString *path;
  NSNumber *offNum;

  self = [super init];
  if (self == nil)
    {
      return nil;
    }
  
  /* Header size: 10.6 places the 8-byte "book" "mark" marker at offsets 0
   * and 8, with the data-area base (header size) at offset 16.  Later
   * bookmarks store the total size at offset 4 and the header size at 12. */
    if (len >= 12 && memcmp(b + 8, "mark", 4) == 0)
    {
            hdrsize = readU32LE(b, 16);
    }
  else
    {
            hdrsize = readU32LE(b, 12);
    }
  if (hdrsize == 0 || hdrsize + 8 > len)
    {
      [self release];
      return nil;
    }
  
  /* The TOC lives at the end of the file; scan backward for its magic, then
   * reject any match that does not look like a real TOC header. */
  for (NSUInteger i = len; i >= 4; i--)
    {
      if (readU32LE(b, i - 4) == BMK_TOC_MAGIC)
	{
	  if (i + 16 <= len)
	    {
	      /* TOC header: [magic][tocid][nexttoc][count]; count is at toc+12
	       * = (i-4)+12 = i+8. */
	      count = readU32LE(b, i + 8);
	      if (count > 0 && count < 512)
		{
		  toc = i - 4;
		  break;
		}
	    }
	}
    }
  if (toc == NSNotFound)
    {
      [self release];
      return nil;
    }
  count = readU32LE(b, toc + 12);
    if (count == 0 || count > 512)
    {
      [self release];
      return nil;
    }

  /* Collect key -> data-record offset. */
  tocd = [NSMutableDictionary dictionary];
  e = toc + 16;
  for (n = 0; n < count; n++, e += 12)
    {
      uint32_t key = readU32LE(b, e);
      uint32_t off = readU32LE(b, e + 4);

      [tocd setObject: [NSNumber numberWithUnsignedInt: off]
	       forKey: [NSNumber numberWithUnsignedInt: key]];
    }
  
  /* Target path: array of component strings (key 0x1004). */
  offNum = [tocd objectForKey:
	      [NSNumber numberWithUnsignedInt: BMK_KEY_PATH]];
  if (offNum != nil)
    {
      id item = fsnaResolveBookmarkItem(b, len, hdrsize,
					[offNum unsignedIntValue], 0);
            if ([item isKindOfClass: [NSArray class]])
	{
	  components = item;
	}
    }
  /* Volume mount path (key 0x2002), e.g. "/" or "/Volumes/Foo". */
  offNum = [tocd objectForKey:
	      [NSNumber numberWithUnsignedInt: BMK_KEY_VOLUME_PATH]];
  if (offNum != nil)
    {
      volPath = fsnaResolveBookmarkItem(b, len, hdrsize,
					[offNum unsignedIntValue], 0);
          }
  /* Display / file name (key 0xF017, else 0x1020). */
  offNum = [tocd objectForKey:
	      [NSNumber numberWithUnsignedInt: BMK_KEY_DISPLAY_NAME]];
  if (offNum == nil)
    {
      offNum = [tocd objectForKey:
		  [NSNumber numberWithUnsignedInt: BMK_KEY_FILE_NAME]];
    }
  if (offNum != nil)
    {
      name = fsnaResolveBookmarkItem(b, len, hdrsize,
				     [offNum unsignedIntValue], 0);
          }

    if (components == nil || [components count] == 0)
    {
      [self release];
      return nil;
    }

    path = [NSMutableString string];
  if (volPath != nil && [volPath length] > 0)
    {
      [path appendString: volPath];
      if ([volPath characterAtIndex: [volPath length] - 1] != '/')
	{
	  [path appendString: @"/"];
	}
    }
  else
    {
      [path appendString: @"/"];
    }
    [path appendString: [components componentsJoinedByString: @"/"]];
  
  if ([path length] == 0)
    {
      [self release];
      return nil;
    }

  _posixPath = [path retain];
    _targetName = [[name length] ? name : [components lastObject] retain];
  _volumeMountPoint = [[volPath length] ? volPath : @"/" retain];
  _version = 3;
    return self;
}

- (instancetype)initWithData:(NSData *)data
{
  const uint8_t *b;
  NSUInteger len;
  NSUInteger headerLen;
  BOOL newCanon;
  BOOL oldCanon;
  self = [super init];

  if (self == nil)
    {
      return nil;
    }
  if (data == nil || [data length] < 8)
    {
      [self release];
      return nil;
    }
  b = [data bytes];
  len = [data length];

  /* Bookmarks (10.6 "book"+"mark" magic) are handled separately. */
  if (memcmp(b, "book", 4) == 0)
    {
      if ([self _initWithBookmarkData: data] == nil)
	{
	  [self release];
	  return nil;
	}
      return self;
    }

  if ([[self class] isAliasData: data] == NO)
    {
      goto fail;
    }

  /* Three classic "alis" layouts are accepted:
   *  - new canonical (macOS): recordSize@0, userType@4=0, header 0x0160@8,
   *    version@10, kind@12, volumeName@14, fileName@54, TLVs@114;
   *  - our older output: "alis"@4, version@8, volumeName@12, fileName@56,
   *    TLVs@150;
   *  - legacy "alis"@0: version@6, volumeName@10, fileName@50, TLVs@150. */
  newCanon = (len >= 10 && b[8] == 0x01 && b[9] == 0x60);
  oldCanon = (len >= 8 && memcmp(b + 4, "alis", 4) == 0);

  if (newCanon)
    {
      _version = readU16(b, 10);
      headerLen = 114;
    }
  else if (oldCanon)
    {
      _version = readU16(b, 8);
      headerLen = (_version == 3) ? 54 : 150;
    }
  else
    {
      _version = readU16(b, 6);
      headerLen = (_version == 3) ? 54 : 150;
    }

  if (_version == 2)
    {
      /* ok */
    }
  else if (_version == 3)
    {
      /* ok */
    }
  else
    {
      goto fail;
    }
  if (len < headerLen)
    {
      goto fail;
    }

  if (_version == 3)
    {
      _isDirectory = (readU16(b, oldCanon ? 10 : 8) == 1);
      _targetCNID = readU32(b, 28);
    }
  else if (newCanon)
    {
      _isDirectory = (readU16(b, 12) == 1);
      _volumeName = readPascalString(b, 14, 32);
      _targetName = readPascalString(b, 54, 32);
      _targetCNID = readU32(b, 86);
    }
  else if (oldCanon)
    {
      _isDirectory = (readU16(b, 10) == 1);
      _volumeName = readPascalString(b, 12, 28);
      _targetName = readPascalString(b, 56, 64);
      _targetCNID = readU32(b, 114);
    }
  else
    {
      _isDirectory = (readU16(b, 8) == 1);
      _volumeName = readPascalString(b, 10, 28);
      _targetName = readPascalString(b, 50, 64);
      _targetCNID = readU32(b, 114);
    }

  /* Tag-length-value data; odd lengths are followed by a pad byte. */
  {
    NSUInteger off = headerLen;

    while (off + 4 <= len)
      {
	uint16_t tag = readU16(b, off);
	uint16_t tlen = readU16(b, off + 2);
	NSUInteger valueOff = off + 4;

	if (tag == TLV_END)
	  {
	    break;
	  }
	if (valueOff + tlen > len)
	  {
	    break;
	  }
	switch (tag)
	  {
	    case TLV_POSIX_PATH:
	      DESTROY(_posixPath);
	      _posixPath = [[NSString alloc] initWithBytes: b + valueOff
						    length: tlen
						  encoding:NSUTF8StringEncoding];
	      break;
	    case TLV_VOLUME_POSIX_PATH:
	      DESTROY(_volumeMountPoint);
	      _volumeMountPoint = [[NSString alloc]
				    initWithBytes: b + valueOff
					   length: tlen
					 encoding:NSUTF8StringEncoding];
	      break;
	    case TLV_UNICODE_NAME:
	      if (_targetName == nil)
		{
		  _targetName = [[NSString alloc]
				  initWithBytes: b + valueOff
					 length: tlen
				       encoding: NSUTF16BigEndianStringEncoding];
		}
	      break;
	    case TLV_UNICODE_VOLUME:
	      if (_volumeName == nil)
		{
		  _volumeName = [[NSString alloc]
				  initWithBytes: b + valueOff
					 length: tlen
				       encoding: NSUTF16BigEndianStringEncoding];
		}
	      break;
	    default:
	      break;
	  }
	off = valueOff + tlen + (tlen % 2);
      }
  }

  /* Real Mac aliases store TLV 18 (POSIX path) relative to the volume mount
   * point (no leading slash), with TLV 19 carrying the mount point.  Reassemble
   * the absolute path so callers get a usable POSIX path.  Our own writer emits
   * an absolute TLV 18, in which case this is a no-op. */
  if (_posixPath != nil && [_posixPath hasPrefix: @"/"] == NO
      && _volumeMountPoint != nil && [_volumeMountPoint length] > 0)
    {
      NSString *abs;
      if ([_volumeMountPoint isEqualToString: @"/"])
	{
	  abs = [@"/" stringByAppendingString: _posixPath];
	}
      else
	{
	  abs = [_volumeMountPoint stringByAppendingPathComponent: _posixPath];
	}
      DESTROY(_posixPath);
      _posixPath = [abs retain];
    }

  return self;

fail:
  [self release];
  return nil;
}

- (NSData *)aliasData
{
  /* Classic "alis" record, big-endian, in the layout macOS reads from a
   * resource fork.  This follows INTEROP_ALIASES.md: a 150-byte fixed region
   * (section 5) followed by tagged values at offset 150 (section 6).  Per
   * section 7 and 9 the record carries the full path (TLV 18 POSIX path, TLV
   * 19 mount point, plus Carbon/Unicode forms) and does NOT fabricate HFS
   * CNIDs from a foreign filesystem's identity, so it is built entirely from
   * the path and the target volume's name. */
  NSMutableData *d = [NSMutableData dataWithLength: 150];
  uint8_t *b = [d mutableBytes];

  /* recordSize is written as a 16-bit value at offset 4 (macOS ignores the
   * high bytes); patched to the final length below. */
  fsnaWriteU16(d, 4, 0);
  fsnaWriteU16(d, 6, (uint16_t)_version);    /* version (2) */
  fsnaWriteU16(d, 8, _isDirectory ? 1 : 0);  /* kind: 0=file 1=directory */

  writePascalString(d, 10, 32, _volumeName); /* volume name (Str31) */
  /* volumeCreateDate [38:42] left 0 */
  b[42] = 'H'; b[43] = '+';                  /* volume signature "H+" */
  /* volume type: 0 = startup/local, 1 = other */
  uint16_t volType = 0;
  if ([_volumeMountPoint length] > 1)
    {
      volType = 1;
    }
  else if ([_volumeName length] == 0)
    {
      volType = 1;
    }
  fsnaWriteU16(d, 44, volType);
  fsnaWriteU32(d, 46, _parentCNID);          /* parent directory CNID */
  writePascalString(d, 50, 64, _targetName); /* file name (Str63) */
  fsnaWriteU32(d, 114, _targetCNID);         /* target file CNID */
  /* fileCreateDate [118:122], fileType/fileCreator [122:130] left 0 */
  fsnaWriteU16(d, 130, 0xFFFF);              /* nlvlFrom = -1 */
  fsnaWriteU16(d, 132, 0xFFFF);              /* nlvlTo = -1 */
  fsnaWriteU32(d, 134, 0x00000D02);          /* volume attributes */
  /* volume file-system id [138:140] and reserved [140:150] left 0 */

  /* Tagged values start at 150. */
  NSString *parentName = (_parentName != nil) ? _parentName : @"";
  fsnaAppendTlv(d, TLV_CARBON_FOLDERNAME,
		[parentName dataUsingEncoding: NSUTF8StringEncoding]);

  /* CNID path: the containing-folder CNID followed by the target CNID, each
   * a 4-byte big-endian value (both zero when we cannot query the Mac). */
  uint8_t cnidPath[8];
  fsnaPutBE32(cnidPath, _parentCNID);
  fsnaPutBE32(cnidPath + 4, _targetCNID);
  fsnaAppendTlv(d, TLV_CNID_PATH, [NSData dataWithBytes: cnidPath length: 8]);

  if (_targetName != nil)
    {
      fsnaAppendTlv(d, TLV_UNICODE_NAME, fsnaUtf16TlvValue(_targetName));
    }
  if (_volumeName != nil && [_volumeName length])
    {
      fsnaAppendTlv(d, TLV_UNICODE_VOLUME, fsnaUtf16TlvValue(_volumeName));
    }

  /* Carbon path (colon-separated, volume-qualified) - this is what 10.6's
   * Alias Manager uses for path-based resolution when the CNID fields are
   * zero.  It is the volume name, a colon, then the path components joined
   * by colons. */
  NSString *rel = _posixPath;
  if ([rel hasPrefix: @"/"])
    {
      rel = [rel substringFromIndex: 1];
    }
  NSArray *comps = [rel pathComponents];
  NSString *carbonPath = [NSString stringWithFormat: @"%@:%@",
					   _volumeName,
					   [comps componentsJoinedByString: @":"]];
  fsnaAppendTlv(d, TLV_CARBON_PATH,
		[carbonPath dataUsingEncoding: NSUTF8StringEncoding]);

  /* POSIX path of the target, absolute (e.g. /Volumes/NTFS-Disk/...).  Spec
   * section 7.3: the complete POSIX target path; pathname-first resolution on
   * 10.6 relies on this, not on the CNID fields. */
  fsnaAppendTlv(d, TLV_POSIX_PATH,
		[_posixPath dataUsingEncoding: NSUTF8StringEncoding]);
  if (_volumeMountPoint != nil)
    {
      fsnaAppendTlv(d, TLV_VOLUME_POSIX_PATH,
		    [_volumeMountPoint dataUsingEncoding: NSUTF8StringEncoding]);
    }
  fsnaAppendTlv(d, TLV_END, [NSData data]);

  fsnaWriteU16(d, 4, (uint16_t)[d length]);  /* total record size */
  return d;
}

/* Build the resource fork that carries the "alis" resource - a classic
 * resource fork header, a gap, the alias data, and a minimal type/resource
 * map.  This is what macOS reads to resolve an alias file. */
- (NSData *)aliasResourceForkData
{
  NSData *alis = [self aliasData];
  NSUInteger alisLen = [alis length];
  NSUInteger mapLen = 46;
  NSUInteger dataAreaLen = 4 + alisLen;   /* 4-byte handle-size prefix + alis */
  NSUInteger mapOff = 256 + dataAreaLen;

  NSMutableData *hdr = [NSMutableData dataWithLength: 16];
  fsnaWriteU32(hdr, 0, 256);
  fsnaWriteU32(hdr, 4, (uint32_t)mapOff);
  fsnaWriteU32(hdr, 8, (uint32_t)dataAreaLen);
  fsnaWriteU32(hdr, 12, (uint32_t)mapLen);

  /* The first 16 bytes of the map duplicate the fork header (overwritten
   * above); the trailing 12 bytes are constant.  The resource manager locates
   * the type list at the fixed map+28 offset, so the resList offset stored in
   * the type entry is not consulted. */
  static const uint8_t kMapPrefix[28] = {
    0x00,0x00,0x01,0x00, 0x00,0x00,0xa7,0x7a,
    0x00,0x00,0xa6,0x7a, 0x00,0x00,0x00,0x46,
    0x6b,0x73,0x73,0x21, 0x4c,0x00,0x00,0x00,
    0x00,0x1c,0x00,0x46
  };
  uint8_t map[46];
  memcpy(map, kMapPrefix, 28);
  memcpy(map, [hdr bytes], 16);
  /* type list: count=1, type "alis", resCount=0, resListOff=18 */
  uint8_t tl[10] = { 0x00,0x01, 'a','l','i','s', 0x00,0x00, 0x00,0x12 };
  memcpy(map + 28, tl, 10);
  /* resource entry: resID=0, nameOff=0xFFFF, attrs=0, dataOff=0 */
  uint8_t rl[8] = { 0x00,0x00, 0xff,0xff, 0x00,0x00,0x00,0x00 };
  memcpy(map + 38, rl, 8);

  NSMutableData *out = [NSMutableData dataWithCapacity: mapOff + mapLen];
  [out appendData: hdr];
  [out increaseLengthBy: 240];              /* pad to the data area at 256 */
  /* Each resource's data is preceded by a 4-byte big-endian handle size. */
  uint8_t hsz[4];
  fsnaPutBE32(hsz, (uint32_t)alisLen);
  [out appendBytes: hsz length: 4];
  [out appendData: alis];
  [out appendBytes: map length: 46];
  return out;
}

/* The 32-byte Finder Info: OSType "alis", creator "MACS", and the alias flag
 * (0x8000) plus 0x0400.  This is what marks a file as a Mac alias. */
- (NSData *)aliasFinderInfoData
{
  uint8_t fi[32] = {0};
  fi[0] = 'a'; fi[1] = 'l'; fi[2] = 'i'; fi[3] = 's';
  fi[4] = 'M'; fi[5] = 'A'; fi[6] = 'C'; fi[7] = 'S';
  /* kIsAlias (0x8000) set, kHasBeenInited (0x0400) cleared - spec section 17:
   * Finder should reconsider the item rather than trust stale state. */
  fi[8] = 0x80; fi[9] = 0x00;
  return [NSData dataWithBytes: fi length: 32];
}

/* Wrap the resource fork and Finder Info in an AppleDouble V2 sidecar ("._"
 * file) so the alias survives on filesystems that lack native xattrs and is
 * reconstituted by macOS when the file is copied via a Mac-aware tool. */
static NSData *
fsnaAppleDouble(NSData *finderInfo, NSData *resourceFork)
{
  NSUInteger fiLen = 32;
  NSUInteger rfLen = [resourceFork length];
  NSUInteger total = 26 + 2 * 12 + fiLen + rfLen;
  NSMutableData *d = [NSMutableData dataWithLength: total];
  uint8_t *b = [d mutableBytes];

  fsnaWriteU32(d, 0, 0x00051607);           /* AppleDouble magic */
  fsnaWriteU32(d, 4, 0x00020000);           /* version 2 */
  memcpy(b + 8, "Mac OS X", 8);
  memset(b + 16, ' ', 8);
  fsnaWriteU16(d, 24, 2);                   /* entry count */

  NSUInteger dc = 50;                       /* body after header + descriptors */
  fsnaWriteU32(d, 26, 9);                   /* entry 9: Finder Info */
  fsnaWriteU32(d, 30, (uint32_t)dc);
  fsnaWriteU32(d, 34, (uint32_t)fiLen);
  memcpy(b + dc, [finderInfo bytes], fiLen);
  dc += fiLen;
  fsnaWriteU32(d, 38, 2);                   /* entry 2: Resource Fork */
  fsnaWriteU32(d, 42, (uint32_t)dc);
  fsnaWriteU32(d, 46, (uint32_t)rfLen);
  if (rfLen)
    {
      memcpy(b + dc, [resourceFork bytes], rfLen);
    }
  return d;
}

/* Depth-limited search for an entry with the recorded inode. */
static NSString *
searchByInode(NSString *dir, uint32_t inode, int depth)
{
  NSFileManager *fm = [NSFileManager defaultManager];
  NSArray *names = [fm contentsOfDirectoryAtPath: dir error: NULL];

  if (depth > RESOLVE_MAX_DEPTH)
    {
      return nil;
    }
  for (NSString *name in names)
    {
      NSString *full = [dir stringByAppendingPathComponent: name];
      struct stat st;

      if (stat([full fileSystemRepresentation], &st) != 0)
	{
	  continue;
	}
      if ((uint32_t)st.st_ino == inode)
	{
	  return full;
	}
      if (S_ISDIR(st.st_mode))
	{
	  NSString *found = searchByInode(full, inode, depth + 1);

	  if (found != nil)
	    {
	      return found;
	    }
	}
    }
  return nil;
}

- (NSString *)resolvePath
{
  NSFileManager *fm = [NSFileManager defaultManager];

  if (_posixPath != nil && [fm fileExistsAtPath: _posixPath])
    {
      struct stat st;

      if (_targetCNID == 0)
	{
	  return _posixPath;
	}
      if (stat([_posixPath fileSystemRepresentation], &st) == 0
	  && (uint32_t)st.st_ino == _targetCNID)
	{
	  return _posixPath;
	}
      /* Something else now sits at the old path; keep searching. */
    }

  if (_posixPath == nil && _targetCNID == 0 && _targetName == nil)
    {
      return nil;
    }

  {
    NSString *dir = [_posixPath stringByDeletingLastPathComponent];
    int level = 0;

    /* Search below every surviving ancestor, innermost first - the
     * directory that used to hold the target may survive even though
     * the target itself has been moved elsewhere within the volume.
     * Never sweep an unrelated tree rooted at "/". */
    while ([dir length] > 1 && level < RESOLVE_MAX_DEPTH)
      {
	if ([fm fileExistsAtPath: dir] == NO)
	  {
	    dir = [dir stringByDeletingLastPathComponent];
	    continue;
	  }
	if ([dir isEqualToString: @"/"])
	  {
	    break;
	  }

	/* Spec section 9/11: when we have no Mac File Manager identity (CNID == 0,
	 * the foreign-filesystem case), there is no additional identity information
	 * with which to locate a moved object, so path-first resolution fails
	 * outright (Tier C in section 25).  We deliberately do NOT fall back to a
	 * name search, because pathname-first behaviour must not resolve an alias
	 * to an identically-named imposter (section 10). */
	NSString *found = nil;

	if (_targetCNID != 0)
	  {
	    found = searchByInode(dir, _targetCNID, 0);
	  }
	if (found != nil)
	  {
	    return found;
	  }
	level++;
	dir = [dir stringByDeletingLastPathComponent];
      }
  }

  return nil;
}

- (int)version
{
  return _version;
}

- (BOOL)isDirectory
{
  return _isDirectory;
}

- (NSString *)volumeName
{
  return _volumeName;
}

- (NSString *)targetName
{
  return _targetName;
}

- (NSString *)posixPath
{
  return _posixPath;
}

- (NSString *)volumeMountPoint
{
  return _volumeMountPoint;
}

- (uint32_t)targetCNID
{
  return _targetCNID;
}

@end
