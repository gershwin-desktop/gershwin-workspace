/* t_ADPreserve.m - ObjectTesting coverage for rewriting an AppleDouble
 * sidecar without losing what this code does not understand, and for the
 * byte layout of the files it writes.
 *
 * Inputs are built byte by byte here, independent of the writer under test,
 * in the layout Mac OS X writes for a file with extended attributes.
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */
#import <Foundation/Foundation.h>
#import "Testing.h"
#import "GSAppleDouble.h"

static void
be32(NSMutableData *d, uint32_t v)
{
  uint8_t b[4] = { v >> 24, v >> 16, v >> 8, v };
  [d appendBytes: b length: 4];
}

static void
be16(NSMutableData *d, uint16_t v)
{
  uint8_t b[2] = { v >> 8, v };
  [d appendBytes: b length: 2];
}

static uint32_t
rd32(NSData *d, NSUInteger off)
{
  const uint8_t *p = [d bytes] + off;
  return ((uint32_t)p[0] << 24) | (p[1] << 16) | (p[2] << 8) | p[3];
}

static uint16_t
rd16(NSData *d, NSUInteger off)
{
  const uint8_t *p = [d bytes] + off;
  return (p[0] << 8) | p[1];
}

/* Entry 9 payload as Mac OS X lays it out: FinderInfo[32], 2 pad bytes,
 * ATTR header, 4-aligned records, then the values.  `base` is the absolute
 * file offset of the payload, because record offsets are absolute. */
static NSData *
macEntry9(NSData *finfo, NSArray *names, NSArray *values, uint32_t base,
          uint32_t padTo)
{
  NSMutableData *recs = [NSMutableData data];
  NSMutableData *vals = [NSMutableData data];
  uint32_t recsSize = 0;
  NSUInteger i;

  for (i = 0; i < [names count]; i++)
    {
      NSUInteger nl = [[names objectAtIndex: i] lengthOfBytesUsingEncoding:
                         NSUTF8StringEncoding] + 1;
      recsSize += (11 + nl + 3) & ~3;
    }
  uint32_t valStart = base + 34 + 36 + recsSize;
  for (i = 0; i < [names count]; i++)
    {
      NSString *n = [names objectAtIndex: i];
      NSData *v = [values objectAtIndex: i];
      NSUInteger nl = [n lengthOfBytesUsingEncoding: NSUTF8StringEncoding] + 1;
      NSUInteger rl = (11 + nl + 3) & ~3;
      be32(recs, valStart + (uint32_t)[vals length]);
      be32(recs, (uint32_t)[v length]);
      be16(recs, 0);
      uint8_t l = (uint8_t)nl;
      [recs appendBytes: &l length: 1];
      [recs appendData: [n dataUsingEncoding: NSUTF8StringEncoding]];
      NSUInteger pad = rl - 11 - (nl - 1);
      [recs appendData: [NSMutableData dataWithLength: pad]];
      [vals appendData: v];
    }
  NSMutableData *e = [NSMutableData data];
  [e appendData: finfo];
  be16(e, 0);
  be32(e, 0x41545452);
  be32(e, 0x3b9ac9ff);                       /* debug tag: a file id */
  uint32_t end = base + 34 + 36 + recsSize + (uint32_t)[vals length];
  be32(e, padTo ? base + padTo : end);       /* total_size */
  be32(e, valStart);                         /* data_start */
  be32(e, (uint32_t)[vals length]);          /* data_length */
  [e appendData: [NSMutableData dataWithLength: 14]];  /* reserved+flags */
  be16(e, (uint16_t)[names count]);
  [e appendData: recs];
  [e appendData: vals];
  if (padTo && [e length] < padTo)
    [e appendData: [NSMutableData dataWithLength: padTo - [e length]]];
  return e;
}

/* A whole file: header, descriptors in the given order, payloads. */
static NSData *
macFile(NSArray *ids, NSArray *payloads)
{
  NSMutableData *d = [NSMutableData data];
  NSUInteger n = [ids count], i;
  be32(d, 0x00051607);
  be32(d, 0x00020000);
  [d appendBytes: "Mac OS X        " length: 16];
  be16(d, (uint16_t)n);
  uint32_t off = 26 + 12 * (uint32_t)n;
  for (i = 0; i < n; i++)
    {
      be32(d, [[ids objectAtIndex: i] unsignedIntValue]);
      be32(d, off);
      be32(d, (uint32_t)[[payloads objectAtIndex: i] length]);
      off += (uint32_t)[[payloads objectAtIndex: i] length];
    }
  for (i = 0; i < n; i++)
    [d appendData: [payloads objectAtIndex: i]];
  return d;
}

static NSData *
bytes(const char *s, NSUInteger n)
{
  return [NSData dataWithBytes: s length: n];
}

int
main(void)
{
  NSAutoreleasePool *arp = [NSAutoreleasePool new];
  NSMutableData *fi = [NSMutableData dataWithLength: 32];
  memcpy([fi mutableBytes], "TEXTttxt", 8);
  NSData *unknownA = bytes("\x01\x02\x03\x00\xff", 5);
  NSData *unknownB = bytes("foreign-writer-entry", 20);

  /* MI-PRS-1 */
  {
    NSData *file = macFile(@[ @0x9001 ], @[ unknownA ]);
    GSAppleDouble *ad = [[[GSAppleDouble alloc] initWithData: file] autorelease];
    GSAppleDouble *re = [[[GSAppleDouble alloc]
      initWithData: [ad appleDoubleData]] autorelease];
    PASS([ad appleDoubleData] != nil,
         "MI-PRS-1 a sidecar holding only an unknown entry is rewritten, not dropped");
    PASS([[re dataForEntry: 0x9001] isEqual: unknownA],
         "MI-PRS-1 the unknown entry data survives byte for byte");
  }

  /* MI-PRS-2 */
  {
    NSData *e9 = macEntry9(fi, @[ @"com.apple.TextEncoding" ],
                           @[ bytes("utf-8;134217984", 15) ], 26 + 12 * 4, 0);
    NSData *file = macFile(@[ @9, @2, @0x9002, @0x7777 ],
      @[ e9, bytes("RSRC", 4), unknownA, unknownB ]);
    GSAppleDouble *ad = [[[GSAppleDouble alloc] initWithData: file] autorelease];
    GSAppleDouble *re = [[[GSAppleDouble alloc]
      initWithData: [ad appleDoubleData]] autorelease];
    PASS([[re dataForEntry: 0x9002] isEqual: unknownA]
         && [[re dataForEntry: 0x7777] isEqual: unknownB],
         "MI-PRS-2 unknown entry ids next to FinderInfo and ATTR survive byte for byte");
    PASS([[re finderInfo] isEqual: fi]
         && [[re resourceFork] isEqual: bytes("RSRC", 4)],
         "MI-PRS-2 FinderInfo and resource fork survive alongside unknown entries");
  }

  /* MI-PRS-3 */
  {
    NSData *e9 = macEntry9(fi,
      @[ @"com.apple.quarantine", @"com.example.Unknown", @"user.empty" ],
      @[ bytes("0083;5f1e2a3b;Safari;", 22), bytes("\x00\x01\xfe\xff", 4),
         [NSData data] ],
      26 + 12 * 2, 0);
    NSData *file = macFile(@[ @9, @2 ], @[ e9, [NSData data] ]);
    GSAppleDouble *ad = [[[GSAppleDouble alloc] initWithData: file] autorelease];
    GSAppleDouble *re = [[[GSAppleDouble alloc]
      initWithData: [ad appleDoubleData]] autorelease];
    NSDictionary *x = [re extendedAttributes];
    PASS([[x objectForKey: @"com.example.Unknown"] isEqual:
          bytes("\x00\x01\xfe\xff", 4)],
         "MI-PRS-3 an ATTR name this code does not know keeps its bytes");
    PASS([[x objectForKey: @"com.apple.quarantine"] isEqual:
          bytes("0083;5f1e2a3b;Safari;", 22)],
         "MI-PRS-3 com.apple.quarantine value is carried unchanged");
    PASS([x objectForKey: @"user.empty"] != nil
         && [[x objectForKey: @"user.empty"] length] == 0,
         "MI-PRS-3 a zero-length ATTR value is kept as an empty attribute");
    PASS([x count] == 3, "MI-PRS-3 no ATTR record is added or lost");
  }

  /* MI-PRS-4 */
  {
    /* Entry 9 longer than 32 bytes whose tail is not an ATTR blob. */
    NSMutableData *e9 = [NSMutableData dataWithData: fi];
    [e9 appendData: bytes("not-an-attr-blob-at-all", 23)];
    NSData *file = macFile(@[ @9, @2 ], @[ e9, [NSData data] ]);
    GSAppleDouble *ad = [[[GSAppleDouble alloc] initWithData: file] autorelease];
    GSAppleDouble *re = [[[GSAppleDouble alloc]
      initWithData: [ad appleDoubleData]] autorelease];
    NSData *out = [re appleDoubleData];
    PASS([out rangeOfData: bytes("not-an-attr-blob-at-all", 23)
                  options: 0 range: NSMakeRange(0, [out length])].location
         != NSNotFound,
         "MI-PRS-4 bytes after FinderInfo that are not an ATTR blob are kept");
  }

  /* MI-PRS-5: re-parse of the rewrite equals the parse of the original. */
  {
    NSData *e9 = macEntry9(fi, @[ @"com.apple.metadata:_kMDItemUserTags",
                                  @"com.apple.metadata:kMDItemWhereFroms" ],
                           @[ bytes("bplist00", 8), bytes("x", 1) ],
                           26 + 12 * 3, 0);
    NSData *file = macFile(@[ @9, @2, @0x9003 ],
                           @[ e9, bytes("fork", 4), unknownB ]);
    GSAppleDouble *a = [[[GSAppleDouble alloc] initWithData: file] autorelease];
    GSAppleDouble *b = [[[GSAppleDouble alloc]
      initWithData: [a appleDoubleData]] autorelease];
    PASS([[a extendedAttributes] isEqual: [b extendedAttributes]]
         && [[a finderInfo] isEqual: [b finderInfo]]
         && [[a resourceFork] isEqual: [b resourceFork]]
         && [[a dataForEntry: 0x9003] isEqual: [b dataForEntry: 0x9003]],
         "MI-PRS-5 parse, rewrite, parse is the identity on every entry");
  }

  /* MI-PRS-6..9: layout of what we write, for a file with xattrs. */
  {
    GSAppleDouble *ad = [[[GSAppleDouble alloc] init] autorelease];
    [ad setFinderInfo: fi];
    [ad setResourceFork: bytes("RSRC", 4)];
    [ad setXattr: bytes("0083;5f1e2a3b;Safari;", 22)
          forKey: @"com.apple.quarantine"];
    [ad setXattr: bytes("v", 1) forKey: @"com.apple.TextEncoding"];
    NSData *d = [ad appleDoubleData];

    PASS(rd32(d, 0) == 0x00051607 && rd32(d, 4) == 0x00020000
         && memcmp((const char *)[d bytes] + 8, "Mac OS X        ", 16) == 0,
         "MI-PRS-6 header: AppleDouble magic, version 2, Mac OS X filler");
    PASS(rd16(d, 24) == 2 && rd32(d, 26) == 9 && rd32(d, 38) == 2,
         "MI-PRS-7 two entries, FinderInfo (9) first, resource fork (2) second");
    uint32_t o9 = rd32(d, 30), l9 = rd32(d, 34), o2 = rd32(d, 42);
    PASS(o9 == 26 + 24 && o2 == o9 + l9,
         "MI-PRS-7 entry 9 follows the descriptors and entry 2 follows entry 9");
    PASS(rd32(d, o9 + 34) == 0x41545452,
         "MI-PRS-8 ATTR magic sits 32 FinderInfo bytes + 2 pad bytes into entry 9");
    uint32_t total = rd32(d, o9 + 34 + 8), dstart = rd32(d, o9 + 34 + 12);
    uint32_t dlen = rd32(d, o9 + 34 + 16);
    uint16_t n = rd16(d, o9 + 34 + 34);
    PASS(n == 2 && total == o9 + l9,
         "MI-PRS-8 ATTR header: record count, total_size is the absolute end of entry 9");
    /* records: 11 + name (with NUL) rounded up to 4 */
    uint32_t r1 = o9 + 34 + 36;
    uint32_t r2 = r1 + ((11 + 22 + 1 + 3) & ~3u);   /* TextEncoding sorts first */
    uint32_t r3 = r2 + ((11 + 20 + 1 + 3) & ~3u);   /* quarantine */
    PASS(dstart == r3 && rd32(d, r1) == dstart,
         "MI-PRS-9 records are 4-byte aligned and data_start is the absolute first value offset");
    PASS(dlen == 1 + 22 && rd32(d, r2) == dstart + 1,
         "MI-PRS-9 data_length covers all values; record offsets are absolute");
    PASS(dstart + dlen == o9 + l9,
         "MI-PRS-9 without padding the values end exactly at the end of entry 9");
  }

  /* MI-PRS-10: the merge a metadata writer uses on an existing sidecar. */
  {
    NSData *e9 = macEntry9(fi, @[ @"com.apple.metadata:_kMDItemUserTags",
                                  @"com.example.Unknown" ],
                           @[ bytes("bplist00", 8), bytes("keep", 4) ],
                           26 + 12 * 3, 0);
    NSData *old = macFile(@[ @9, @2, @0x9004 ],
                          @[ e9, bytes("oldfork", 7), unknownA ]);
    NSSet *managed = [NSSet setWithObjects:
      @"com.apple.metadata:_kMDItemUserTags", nil];
    GSAppleDouble *f = [[[GSAppleDouble alloc] init] autorelease];
    NSMutableData *newfi = [NSMutableData dataWithLength: 32];
    memcpy([newfi mutableBytes], "APPLmine", 8);
    [f setFinderInfo: newfi];
    NSData *merged = [GSAppleDouble appleDoubleDataByUpdatingSidecar: old
                                                         withContent: [f appleDoubleData]
                                                   managedXattrNames: managed];
    GSAppleDouble *m = [[[GSAppleDouble alloc] initWithData: merged] autorelease];
    PASS([[m finderInfo] isEqual: newfi] && [[m resourceFork] length] == 0,
         "MI-PRS-10 FinderInfo and resource fork come from the new content");
    PASS([[m extendedAttributes] objectForKey: @"com.apple.metadata:_kMDItemUserTags"] == nil,
         "MI-PRS-10 a managed attribute the new content lacks is removed");
    PASS([[[m extendedAttributes] objectForKey: @"com.example.Unknown"]
          isEqual: bytes("keep", 4)],
         "MI-PRS-10 an unmanaged attribute of the old sidecar survives the rewrite");
    PASS([[m dataForEntry: 0x9004] isEqual: unknownA],
         "MI-PRS-10 an unknown entry of the old sidecar survives the rewrite");
    PASS([GSAppleDouble appleDoubleDataByUpdatingSidecar: nil
                                             withContent: nil
                                       managedXattrNames: managed] == nil,
         "MI-PRS-10 nothing old and nothing new leaves nothing to write");
  }

  [arp release];
  return 0;
}
