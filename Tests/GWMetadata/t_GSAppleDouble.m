/* t_GSAppleDouble.m — ObjectTesting coverage for the AppleDouble parser.
 *
 * Compiles the unit under test in-process (no framework/display needed) so
 * it runs headless via `gnustep-tests`.  Covers the CR-2 bounds-check fix:
 * a crafted descriptor whose 32-bit offset+length would wrap must be
 * rejected instead of triggering an out-of-bounds read.
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

#import <Foundation/Foundation.h>
#import "Testing.h"

/* Bring the implementation in directly — it depends only on Foundation. */
#include "GSAppleDouble.m"

static void
put_be16(uint8_t *p, uint16_t v)
{
  p[0] = (v >> 8) & 0xFF;
  p[1] = v & 0xFF;
}

static void
put_be32(uint8_t *p, uint32_t v)
{
  p[0] = (v >> 24) & 0xFF; p[1] = (v >> 16) & 0xFF;
  p[2] = (v >> 8)  & 0xFF; p[3] = v & 0xFF;
}

int
main(void)
{
  NSAutoreleasePool *arp = [NSAutoreleasePool new];

  /* --- Round-trip: a well-formed FinderInfo survives write then read --- */
  {
    uint8_t fi[32] = {0};
    fi[0] = 'T'; fi[1] = 'E'; fi[2] = 'X'; fi[3] = 'T';   /* type code */
    GSAppleDouble *ad = [[[GSAppleDouble alloc] init] autorelease];
    [ad setFinderInfo: [NSData dataWithBytes: fi length: 32]];
    NSData *blob = [ad appleDoubleData];
    PASS(blob != nil && [blob length] >= 38, "appleDoubleData emits a header + entry");

    GSAppleDouble *rd = [[[GSAppleDouble alloc] initWithData: blob] autorelease];
    PASS(rd != nil, "initWithData parses a well-formed blob");
    PASS_EQUAL([rd finderInfo], [NSData dataWithBytes: fi length: 32],
               "FinderInfo round-trips byte-for-byte");
  }

  /* --- Malformed input is rejected, not crashed on --- */
  PASS([[GSAppleDouble alloc] initWithData: [NSData data]] == nil,
       "empty data -> nil");
  {
    uint8_t junk[64] = {0};   /* zero magic */
    PASS([[GSAppleDouble alloc] initWithData:
            [NSData dataWithBytes: junk length: 64]] == nil,
         "bad magic -> nil");
  }

  /* --- CR-2: integer-overflow bounds bypass --- *
   * Header(26) + one 12-byte descriptor whose offset+length wraps uint32.
   * The old code computed dataOff + dataLen in 32 bits: 0xFFFFFFF0 + 0x20
   * == 0x10, which passed "> length" and then read from bytes + 0xFFFFFFF0.
   * The fix widens the sum to 64 bits, so the entry is skipped. */
  {
    NSMutableData *m = [NSMutableData dataWithLength: 38];
    uint8_t *b = [m mutableBytes];
    put_be32(b + 0, 0x00051607);   /* magic   */
    put_be32(b + 4, 0x00020000);   /* version */
    /* bytes 8..23 filler (already zero) */
    put_be16(b + 24, 1);           /* entryCount = 1 */
    put_be32(b + 26, 9);           /* entryID = FinderInfo */
    put_be32(b + 30, 0xFFFFFFF0);  /* offset (would wrap) */
    put_be32(b + 34, 0x00000020);  /* length */

    GSAppleDouble *ad = [[[GSAppleDouble alloc] initWithData: m] autorelease];
    /* Must not crash; the overflowing entry must be skipped, so no
     * FinderInfo is exposed. */
    PASS(ad != nil, "overflow descriptor: parser returns an object (no crash)");
    PASS([ad finderInfo] == nil,
         "overflow descriptor is skipped, not read out of bounds");
  }

  [arp release];
  return 0;
}
