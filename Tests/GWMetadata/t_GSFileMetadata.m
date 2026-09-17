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
#include <arpa/inet.h>

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

  /* --- user tags: read/write the _kMDItemUserTags xattr (see https://developer.apple.com/library/archive/technotes/tn/tn1150.html) ---
   * Tags are stored as a binary plist array of strings in
   * com.apple.metadata:_kMDItemUserTags, never inside .DS_Store. */
  {
    GSFileMetadata *md = [[[GSFileMetadata alloc] init] autorelease];
    NSArray *tags = @[ @"Red", @"Work" ];
    [md setUserTags: tags];
    PASS([[md userTags] isEqual: tags],
         "userTags round-trips through the setter/getter");

    /* The raw xattr value must be a binary plist array of strings. */
    NSData *raw = [md userTagsData];
    PASS(raw != nil && [raw length] > 0, "userTagsData emits a plist blob");
    NSArray *decoded =
      [NSPropertyListSerialization propertyListWithData: raw
                                                options: NSPropertyListImmutable
                                                 format: NULL
                                                  error: NULL];
    PASS([decoded isKindOfClass: [NSArray class]]
         && [decoded isEqual: tags],
         "userTags xattr value is a binary plist array of strings");

    /* AppleDouble must carry the tags too (foreign-filesystem fallback). */
    GSFileMetadata *viaAppleDouble =
      [GSFileMetadata metadataFromAppleDoubleData: [md appleDoubleData]];
    PASS(viaAppleDouble != nil
         && [[viaAppleDouble userTags] isEqual: tags],
         "userTags survive an AppleDouble encode/decode round-trip");
  }

  /* --- label <-> tag interop: setting a label writes the matching
   * _kMDItemUserTags entry, and reading prefers the tag (see TN1150 https://developer.apple.com/library/archive/technotes/tn/tn1150.html) */
  {
    GSFileMetadata *md = [[[GSFileMetadata alloc] init] autorelease];
    [md setLabelNumber: GSFileLabelRed];
    NSArray *tags = [md userTags];
    PASS([tags containsObject: @"Red"],
         "setLabelNumber writes the matching 'Red' _kMDItemUserTags tag");
    PASS([md labelNumber] == GSFileLabelRed,
         "labelNumber still reads the fdFlags label after tagging");

    /* Clearing the label clears the tag. */
    [md setLabelNumber: GSFileLabelNone];
    PASS([[md userTags] count] == 0 || ![[md userTags] containsObject: @"Red"],
         "clearing the label removes the 'Red' tag");
  }

  /* --- user tags xattr round-trip through a real file (see https://developer.apple.com/library/archive/technotes/tn/tn1150.html) --- */
  {
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:
                       [NSString stringWithFormat: @"t_gsfm_tags_%d.txt", (int)getpid()]];
    [fm removeFileAtPath: path handler: nil];
    [fm createFileAtPath: path contents: [NSData data] attributes: nil];

    if (gs_xattr_supported([path fileSystemRepresentation]) == 1)
      {
        NSArray *tagSet = @[ @"Blue", @"Project" ];
        GSFileMetadata *md = [[[GSFileMetadata alloc] init] autorelease];
        [md setUserTags: tagSet];
        PASS([md writeToFileAtPath: path error: NULL],
             "user tags write to the file xattr");

        [GSFileMetadata invalidateAllCachedMetadata];
        GSFileMetadata *rd = [GSFileMetadata metadataForFileAtPath: path];
        PASS(rd != nil && [[rd userTags] isEqual: tagSet],
             "user tags round-trip through the _kMDItemUserTags xattr");
        PASS(![fm fileExistsAtPath: [GSFileMetadata sidecarPathForFilePath: path]],
             "no ._ sidecar is created for tags when xattr is available");

        /* A position-only write must preserve the tags. */
        [rd setIconPosition: NSMakePoint(5, 6)];
        PASS([rd writeToFileAtPath: path error: NULL],
             "position-only write succeeds");
        [GSFileMetadata invalidateAllCachedMetadata];
        GSFileMetadata *rd2 = [GSFileMetadata metadataForFileAtPath: path];
        PASS([[rd2 userTags] isEqual: tagSet],
             "tags survive a position-only write");
      }
    else
      {
        PASS(1, "xattr unsupported on this filesystem — skipping tag xattr round-trip");
      }
    [fm removeFileAtPath: path handler: nil];
  }

  /* --- label fallback: a file tagged only via _kMDItemUserTags (no fdFlags
   * label bits) reports the matching label (see https://developer.apple.com/library/archive/technotes/tn/tn1150.html) --- */
  {
    GSFileMetadata *md = [[[GSFileMetadata alloc] init] autorelease];
    [md setUserTags: @[ @"Green" ]];
    PASS([md labelNumber] == GSFileLabelGreen,
         "labelNumber falls back to a _kMDItemUserTags colour when fdFlags has none");
    [md setUserTags: @[ @"Project", @"Orange" ]];
    PASS([md labelNumber] == GSFileLabelOrange,
         "labelNumber picks the standard colour tag among custom tags");
  }

  /* --- GSFileLabel encoding is the shared order (1=Red..7=Grey): the same
   * values as DSStoreLabelColor, so the .DS_Store lclr record and the
   * FinderInfo fdFlags label never disagree --- */
  {
    GSFileMetadata *md = [[[GSFileMetadata alloc] init] autorelease];

    struct { NSInteger label; NSString *name; } order[] = {
      { GSFileLabelRed,     @"Red" },
      { GSFileLabelOrange,  @"Orange" },
      { GSFileLabelYellow,  @"Yellow" },
      { GSFileLabelGreen,   @"Green" },
      { GSFileLabelBlue,    @"Blue" },
      { GSFileLabelPurple,  @"Purple" },
      { GSFileLabelGrey,    @"Gray" },
    };
    NSUInteger n = sizeof(order) / sizeof(order[0]);
    for (NSUInteger i = 0; i < n; i++)
      {
        GSFileMetadata *m = [[[GSFileMetadata alloc] init] autorelease];
        [m setLabelNumber: order[i].label];
        NSString *tag = [[m userTags] objectAtIndex: 0];
        BOOL ok = [tag isEqualToString: order[i].name]
                  && [m labelNumber] == order[i].label;
        PASS(ok, "label %ld maps to its Finder tag name and round-trips",
             (long)order[i].label);
      }

    /* The raw fdFlags label bits must equal the GSFileLabel value (the
     * shared encoding), so a label set here is readable by Finder. */
    [md setLabelNumber: GSFileLabelRed];
    PASS((([md finderFlags] >> 1) & 0x7) == GSFileLabelRed,
         "fdFlags label bits equal GSFileLabelRed (shared Finder encoding)");
  }

  /* --- custom icon: setting icon data writes it to the resource fork and
   * sets kHasCustomIcon (see TN1150, which notes custom icons for files use
   * the data or resource fork:
   * https://developer.apple.com/library/archive/technotes/tn/tn1150.html) --- */
  {
    /* A minimal but structurally valid icns file (total length patched at
     * the end so the header length field matches the actual byte count). */
    NSMutableData *icns = [NSMutableData data];
    [icns appendBytes: "icns" length: 4];
    uint32_t lenBE = 0;  /* placeholder; patched below */
    [icns appendBytes: &lenBE length: 4];
    /* ic07: 16x16 icon */
    [icns appendBytes: "ic07" length: 4];
    uint32_t e0 = htonl(8 + 8);
    [icns appendBytes: &e0 length: 4];
    [icns appendBytes: "ic08" length: 4];
    uint32_t e1 = htonl(8 + 8);
    [icns appendBytes: &e1 length: 4];
    lenBE = htonl((uint32_t)[icns length]);
    [icns replaceBytesInRange: NSMakeRange(4, 4) withBytes: &lenBE];

    GSFileMetadata *md = [[[GSFileMetadata alloc] init] autorelease];
    [md setCustomIconData: icns];
    PASS([md hasCustomIcon],
         "setCustomIconData sets the kHasCustomIcon FinderInfo flag");
    NSData *rf = [md resourceFork];
    PASS(rf != nil && [rf length] > 0,
         "setCustomIconData writes a resource fork");
    PASS([[md customIconData] isEqual: icns],
         "customIconData returns the exact icns bytes back");

    /* The resource fork must survive an AppleDouble encode/decode. */
    GSFileMetadata *viaAppleDouble =
      [GSFileMetadata metadataFromAppleDoubleData: [md appleDoubleData]];
    PASS(viaAppleDouble != nil && [[viaAppleDouble customIconData] isEqual: icns],
         "custom icon resource fork survives AppleDouble encode/decode");

    /* Clearing the custom icon removes the resource fork + flag. */
    [md clearCustomIcon];
    PASS(![md hasCustomIcon],
         "clearCustomIcon clears the kHasCustomIcon flag");
    PASS([[md resourceFork] length] == 0 || [md resourceFork] == nil,
         "clearCustomIcon drops the resource fork");
  }

  /* --- directory DInfo: view style + window bounds (spatial FinderInfo) --- */
  {
    GSFileMetadata *md = [[[GSFileMetadata alloc] init] autorelease];

    /* Default is unset. */
    PASS([md viewStyleCodeForDirectory] == nil,
         "viewStyleCodeForDirectory is nil on fresh metadata");
    PASS(NSEqualRects([md windowBoundsForDirectory], NSZeroRect),
         "windowBoundsForDirectory is NSZeroRect on fresh metadata");

    /* Set per-folder view + window geometry. */
    [md setViewStyleCodeForDirectory: @"Nlsv"];
    [md setWindowBoundsForDirectory: NSMakeRect(100, 120, 360, 340)];

    PASS([[md viewStyleCodeForDirectory] isEqualToString: @"Nlsv"],
         "viewStyleCodeForDirectory round-trips 'Nlsv'");

    /* frView must land at bytes 14-15 as big-endian 1 (list view). */
    const uint8_t *b = [[md finderInfo] bytes];
    uint16_t frView = (uint16_t)((b[14] << 8) | b[15]);
    PASS(frView == 1, "frView written at bytes 14-15 as big-endian 1");

    /* frRect (top,left,bottom,right) at bytes 0-7. */
    int16_t top    = (int16_t)((b[0] << 8) | b[1]);
    int16_t left   = (int16_t)((b[2] << 8) | b[3]);
    int16_t bottom = (int16_t)((b[4] << 8) | b[5]);
    int16_t right  = (int16_t)((b[6] << 8) | b[7]);
    PASS(top == 120 && left == 100 && bottom == 460 && right == 460,
         "frRect written at bytes 0-7 as big-endian (top,left,bottom,right)");

    PASS(NSEqualRects([md windowBoundsForDirectory],
                      NSMakeRect(100, 120, 360, 340)),
         "windowBoundsForDirectory round-trips the set rect");

    /* A different view code maps to a different frView. */
    [md setViewStyleCodeForDirectory: @"clmv"];
    PASS([[md viewStyleCodeForDirectory] isEqualToString: @"clmv"],
         "viewStyleCodeForDirectory round-trips 'clmv'");
    frView = (uint16_t)((((const uint8_t *)[[md finderInfo] bytes])[14] << 8)
                        | ((const uint8_t *)[[md finderInfo] bytes])[15]);
    PASS(frView == 2, "frView for 'clmv' is big-endian 2 (column view)");
  }

  [arp release];
  return 0;
}
