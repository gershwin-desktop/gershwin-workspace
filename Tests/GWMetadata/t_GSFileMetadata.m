/* t_GSFileMetadata.m — ObjectTesting coverage for the Finder-metadata model.
 *
 * Focuses on the fdLocation (icon position) guarantees the .DS_Store/xattr
 * persistence consolidation relies on: the FinderInfo byte layout, the
 * (-1,-1) "no position" sentinel, the xattr round-trip, and the AppleDouble
 * `._` sidecar fallback used on filesystems without extended attributes.
 *
 * The unit and its libc/Foundation-only dependencies are compiled in-process
 * (headless); only non-GUI code paths are exercised, though the tool links
 * gnustep-gui because GSFileMetadata references NSImage/NSColor elsewhere.
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

#import <Foundation/Foundation.h>
#import "Testing.h"

#include <unistd.h>

/* Dependencies (header-imported by GSFileMetadata) brought into this TU;
 * no static-symbol collisions across the three files. */
#include "GWMetaXattr.m"
#include "GSAppleDouble.m"
#include "GSFileMetadata.m"

int
main(void)
{
  NSAutoreleasePool *arp = [NSAutoreleasePool new];
  NSFileManager *fm = [NSFileManager defaultManager];

  /* --- fdLocation FinderInfo byte layout (v@10-11, h@12-13, big-endian) --- */
  {
    GSFileMetadata *md = [[[GSFileMetadata alloc] init] autorelease];
    [md setIconPosition: NSMakePoint(300, 200)];   /* x -> h, y -> v */
    NSData *fi = [md finderInfo];
    PASS(fi != nil && [fi length] >= 32,
         "setIconPosition synthesizes a 32-byte FinderInfo");
    const uint8_t *b = [fi bytes];
    int16_t v = (int16_t)((b[10] << 8) | b[11]);
    int16_t h = (int16_t)((b[12] << 8) | b[13]);
    PASS(v == 200 && h == 300,
         "fdLocation writes v(y) at bytes 10-11 and h(x) at 12-13, big-endian");
    PASS(NSEqualPoints([md iconPosition], NSMakePoint(300, 200)),
         "iconPosition getter round-trips the set value");
  }

  /* --- no-position sentinel --- */
  {
    GSFileMetadata *md = [[[GSFileMetadata alloc] init] autorelease];
    PASS(NSEqualPoints([md iconPosition], NSMakePoint(-1, -1)),
         "fresh metadata reports the no-position sentinel (-1,-1)");
  }

  /* --- flags / label round-trip (in memory) --- */
  {
    GSFileMetadata *md = [[[GSFileMetadata alloc] init] autorelease];
    [md setInvisible: YES];
    [md setLabelNumber: 6];
    PASS([md isInvisible], "invisible flag round-trips");
    PASS([md labelNumber] == 6, "label number round-trips");
  }

  /* --- ._ sidecar fallback (no-xattr filesystems) --- */
  {
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:
                       [NSString stringWithFormat: @"t_gsfm_%d.txt", (int)getpid()]];
    [fm removeFileAtPath: path handler: nil];
    [fm createFileAtPath: path contents: [NSData data] attributes: nil];

    GSFileMetadata *md = [[[GSFileMetadata alloc] init] autorelease];
    [md setIconPosition: NSMakePoint(42, 84)];
    [md setForceSidecar: YES];
    PASS([md writeToFileAtPath: path error: NULL],
         "writeToFileAtPath (forced sidecar) succeeds");

    NSString *sidecar = [GSFileMetadata sidecarPathForFilePath: path];
    PASS([fm fileExistsAtPath: sidecar], "a ._ sidecar file is created");

    [GSFileMetadata invalidateAllCachedMetadata];
    GSFileMetadata *rd = [GSFileMetadata metadataForFileAtPath: path
                                                  forceSidecar: YES];
    PASS(rd != nil && NSEqualPoints([rd iconPosition], NSMakePoint(42, 84)),
         "iconPosition round-trips through the ._ sidecar");

    [fm removeFileAtPath: sidecar handler: nil];
    [fm removeFileAtPath: path handler: nil];
  }

  /* --- xattr round-trip (guarded: skip where the fs has no xattr) --- */
  {
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:
                       [NSString stringWithFormat: @"t_gsfm_x_%d.txt", (int)getpid()]];
    [fm removeFileAtPath: path handler: nil];
    [fm createFileAtPath: path contents: [NSData data] attributes: nil];

    if (gs_xattr_supported([path fileSystemRepresentation]) == 1)
      {
        GSFileMetadata *md = [[[GSFileMetadata alloc] init] autorelease];
        [md setIconPosition: NSMakePoint(11, 22)];
        [md setForceSidecar: NO];
        PASS([md writeToFileAtPath: path error: NULL],
             "writeToFileAtPath (xattr) succeeds");

        [GSFileMetadata invalidateAllCachedMetadata];
        GSFileMetadata *rd = [GSFileMetadata metadataForFileAtPath: path];
        PASS(rd != nil && NSEqualPoints([rd iconPosition], NSMakePoint(11, 22)),
             "iconPosition round-trips through the xattr");
        PASS([fm fileExistsAtPath: [GSFileMetadata sidecarPathForFilePath: path]] == NO,
             "no ._ sidecar is written when xattr is available");
      }
    else
      {
        PASS(1, "xattr unsupported on this filesystem — skipping xattr round-trip");
      }
    [fm removeFileAtPath: path handler: nil];
  }

  /* --- AppleDouble encode/decode preserves fdLocation --- */
  {
    GSFileMetadata *md = [[[GSFileMetadata alloc] init] autorelease];
    [md setIconPosition: NSMakePoint(7, 9)];
    [md setLabelNumber: 4];
    NSData *blob = [md appleDoubleData];
    PASS(blob != nil && [blob length] > 0, "appleDoubleData emits a blob");
    GSFileMetadata *rd = [GSFileMetadata metadataFromAppleDoubleData: blob];
    PASS(rd != nil && NSEqualPoints([rd iconPosition], NSMakePoint(7, 9)),
         "iconPosition survives an AppleDouble encode/decode round-trip");
  }

  [arp release];
  return 0;
}
