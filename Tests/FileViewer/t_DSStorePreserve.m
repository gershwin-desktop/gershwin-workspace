/* t_DSStorePreserve.m - forward-compatibility / cooperative-editor tests.
 *
 * Behavioral contract under test: Workspace is a cooperative editor of
 * .DS_Store, not the owner of the file.  It may modify the records it
 * understands, but it must preserve, carry forward, and avoid overwriting
 * metadata created by Finder or any other application:
 *
 *   - unknown record types round-trip byte-identically
 *   - unknown blob bytes survive (never regenerated)
 *   - partially-understood records (icvo, fwi0, bwsp, lsvp, BKGD) keep every
 *     unknown field when a known field is modified
 *   - duplicate records survive unless the one is explicitly replaced
 *   - out-of-range / unexpected values are not clamped or normalized
 *   - the write is atomic (never a partially-written file)
 *
 * The units under test are compiled in-process (see GNUmakefile.preamble);
 * runs headless.
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

#import <Foundation/Foundation.h>
#import "Testing.h"

#import "../../DSStore/DSStore.h"
#import "../../DSStore/DSStoreEntry.h"
#include "../../Workspace/FileViewer/DSStoreInfo.m"

static NSString *tmpStorePath(NSString *tag)
{
  return [NSTemporaryDirectory()
           stringByAppendingPathComponent:
             [NSString stringWithFormat: @"t_preserve_%@_%d.DS_Store", tag, (int)getpid()]];
}

/* Write a fresh store containing the entries of @p builder, then run @p mutate
 * on a freshly-loaded copy, save it, reload and run @p verify on the result. */
static void roundTrip(NSArray *seedEntries,
                      void (^mutate)(DSStore *store),
                      void (^verify)(DSStore *store))
{
  NSString *path = tmpStorePath([NSString stringWithFormat: @"rt%lu",
                                   (unsigned long)[seedEntries hash]]);
  [[NSFileManager defaultManager] removeFileAtPath: path handler: nil];

  DSStore *w = [DSStore createStoreAtPath: path withEntries: nil];
  for (DSStoreEntry *e in seedEntries)
    [w setEntry: e];
  [w save];

  DSStore *r = [DSStore storeWithPath: path];
  [r load];
  mutate(r);
  [r save];

  DSStore *chk = [DSStore storeWithPath: path];
  [chk load];
  verify(chk);

  [[NSFileManager defaultManager] removeFileAtPath: path handler: nil];
}

int
main(void)
{
  NSAutoreleasePool *arp = [NSAutoreleasePool new];

  /* --- 1. unknown record types round-trip unchanged --- */
  {
    NSData *unk = [NSData dataWithBytes: "\x00\x01\x02\x03\xAA\xBB\xCC\xDD"
                                 length: 8];
    roundTrip(@[ [[[DSStoreEntry alloc]
                     initWithFilename: @"file.txt"
                                 code: @"zzzz"
                                 type: @"blob"
                                value: unk] autorelease] ],
      ^(DSStore *store) { /* no known-field change */ },
      ^(DSStore *store) {
        DSStoreEntry *e = [store entryForFilename: @"file.txt" code: @"zzzz"];
        PASS(e != nil, "unknown record type 'zzzz' is not discarded");
        PASS([[e value] isEqual: unk],
             "unknown record type 'zzzz' bytes are preserved verbatim");
        PASS([[e type] isEqualToString: @"blob"],
             "unknown record type 'zzzz' keeps its type tag");
      });
  }

  /* --- 2. unknown blob bytes in a KNOWN record (Iloc padding) survive --- */
  {
    /* Finder writes an Iloc whose trailing 8 bytes may carry meaningful data;
     * replacing only x/y must keep the tail untouched. */
    NSMutableData *iloc = [NSMutableData data];
    uint32_t xb = 0x00000014, yb = 0x00000028; /* 20, 40 big-endian */
    [iloc appendBytes: &xb length: 4];
    [iloc appendBytes: &yb length: 4];
    uint8_t tail[8] = { 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08 };
    [iloc appendBytes: tail length: 8];
    NSData *tailData = [NSData dataWithBytes: tail length: 8];

    roundTrip(@[ [[[DSStoreEntry alloc]
                     initWithFilename: @"f.txt"
                                 code: @"Iloc"
                                 type: @"blob"
                                value: iloc] autorelease] ],
      ^(DSStore *store) {
        DSStoreEntry *e = [store entryForFilename: @"f.txt" code: @"Iloc"];
        DSStoreEntry *moved = [DSStoreEntry iconLocationEntryForFile: @"f.txt"
                                                                   x: 99
                                                                   y: 77
                                                       preserving: e];
        [store setEntry: moved];
      },
      ^(DSStore *store) {
        DSStoreEntry *e = [store entryForFilename: @"f.txt" code: @"Iloc"];
        NSData *v = (NSData *)[e value];
        PASS([v length] == 16, "Iloc keeps its 16-byte shape");
        PASS((int)[e iconLocation].x == 99 && (int)[e iconLocation].y == 77,
             "Iloc x/y updated");
        NSData *gotTail = [v subdataWithRange: NSMakeRange(8, 8)];
        PASS([gotTail isEqual: tailData],
             "Iloc trailing bytes preserved (not regenerated)");
      });
  }

  /* --- 3. icvo: unknown trailing fields survive an icon-size change --- */
  {
    /* 20-byte icvo: "icvo" + 8 flags bytes + size(12-13) + "none"(14-17)
     * + 2 unknown trailing bytes.  Changing only the size must keep every
     * other byte. */
    NSMutableData *icvo = [NSMutableData data];
    [icvo appendBytes: "icvo" length: 4];
    uint8_t flags[8] = { 0xAA, 0xBB, 0xCC, 0xDD, 0x00, 0x00, 0x00, 0x00 };
    [icvo appendBytes: flags length: 8];
    uint16_t sizeBig = 64;
    [icvo appendBytes: &sizeBig length: 2];
    [icvo appendBytes: "grid" length: 4];
    uint16_t extra = 0x1234;
    [icvo appendBytes: &extra length: 2];
    NSData *flagsData = [NSData dataWithBytes: flags length: 8];
    NSData *extraData = [NSData dataWithBytes: &extra length: 2];

    roundTrip(@[ [[[DSStoreEntry alloc]
                     initWithFilename: @"."
                                 code: @"icvo"
                                 type: @"blob"
                                value: icvo] autorelease] ],
      ^(DSStore *store) {
        DSStoreEntry *e = [store entryForFilename: @"." code: @"icvo"];
        DSStoreEntry *changed = [DSStoreEntry iconSizeEntryForFile: @"."
                                                              size: 128
                                                  preserving: e];
        [store setEntry: changed];
      },
      ^(DSStore *store) {
        DSStoreEntry *e = [store entryForFilename: @"." code: @"icvo"];
        NSData *v = (NSData *)[e value];
        PASS([v length] == [icvo length],
             "icvo length preserved (no field dropped)");
        const uint8_t *b = [v bytes];
        PASS(b[12] == 0 && b[13] == 128, "icvo icon size updated to 128");
        NSData *gotFlags = [v subdataWithRange: NSMakeRange(4, 8)];
        PASS([gotFlags isEqual: flagsData], "icvo flags bytes preserved");
        PASS(memcmp(b + 14, "grid", 4) == 0,
             "icvo arrangement field preserved (not normalized to 'none')");
        NSData *gotExtra = [v subdataWithRange: NSMakeRange(18, 2)];
        PASS([gotExtra isEqual: extraData],
             "icvo unknown trailing bytes preserved");
      });
  }

  /* --- 4. fwi0: trailing flags survive a geometry update --- */
  {
    NSMutableData *fwi0 = [NSMutableData data];
    uint16_t top = 10, left = 20, bottom = 300, right = 500;
    [fwi0 appendBytes: &top length: 2];
    [fwi0 appendBytes: &left length: 2];
    [fwi0 appendBytes: &bottom length: 2];
    [fwi0 appendBytes: &right length: 2];
    [fwi0 appendBytes: "icnv" length: 4];
    uint32_t fflags = 0x01020304;
    [fwi0 appendBytes: &fflags length: 4];
    NSData *fflagsData = [NSData dataWithBytes: &fflags length: 4];

    roundTrip(@[ [[[DSStoreEntry alloc]
                     initWithFilename: @"."
                                 code: @"fwi0"
                                 type: @"blob"
                                value: fwi0] autorelease] ],
      ^(DSStore *store) {
        DSStoreEntry *e = [store entryForFilename: @"." code: @"fwi0"];
        DSStoreEntry *moved = [DSStoreEntry windowGeometryEntryForFile: @"."
                                                                  rect: NSMakeRect(30, 40, 600, 400)
                                                             viewStyle: @"Nlsv"
                                                            preserving: e];
        [store setEntry: moved];
      },
      ^(DSStore *store) {
        DSStoreEntry *e = [store entryForFilename: @"." code: @"fwi0"];
        NSData *v = (NSData *)[e value];
        PASS([v length] == 16, "fwi0 keeps 16 bytes");
        NSData *gotFlags = [v subdataWithRange: NSMakeRange(12, 4)];
        PASS([gotFlags isEqual: fflagsData],
             "fwi0 trailing flags preserved (not zeroed)");
        const uint8_t *b = [v bytes];
        PASS(memcmp(b + 8, "Nlsv", 4) == 0, "fwi0 view style updated");
      });
  }

  /* --- 5. bwsp: unknown plist keys survive a window-bounds update --- */
  {
    NSDictionary *finderBwsp = @{
      @"WindowBounds" : @"{{0, 0}, {800, 600}}",
      @"ToolbarVisible" : @YES,               /* unknown to Workspace */
      @"ShowToolbar" : @YES,                  /* unknown to Workspace */
      @"ShowStatusBar" : @NO,                 /* unknown to Workspace */
    };
    NSError *err = nil;
    NSData *bwspData = [NSPropertyListSerialization
                         dataWithPropertyList: finderBwsp
                                       format: NSPropertyListBinaryFormat_v1_0
                                      options: 0
                                        error: &err];

    roundTrip(@[ [[[DSStoreEntry alloc]
                     initWithFilename: @"."
                                 code: @"bwsp"
                                 type: @"blob"
                                value: bwspData] autorelease] ],
      ^(DSStore *store) {
        DSStoreEntry *e = [store entryForFilename: @"." code: @"bwsp"];
        DSStoreEntry *updated = [DSStoreEntry browserWindowEntryForFile: @"."
                                                          windowBounds: NSMakeRect(5, 5, 700, 500)
                                                          sidebarWidth: 180
                                                            preserving: e];
        [store setEntry: updated];
      },
      ^(DSStore *store) {
        DSStoreEntry *e = [store entryForFilename: @"." code: @"bwsp"];
        NSDictionary *parsed =
          [NSPropertyListSerialization propertyListWithData: (NSData *)[e value]
                                                    options: NSPropertyListImmutable
                                                     format: NULL
                                                      error: NULL];
        PASS([parsed isKindOfClass: [NSDictionary class]],
             "bwsp still decodes as a plist");
        PASS([[parsed objectForKey: @"ToolbarVisible"] boolValue],
             "bwsp unknown key ToolbarVisible preserved");
        PASS([[parsed objectForKey: @"ShowStatusBar"] boolValue] == NO,
             "bwsp unknown key ShowStatusBar preserved");
        PASS([[parsed objectForKey: @"SidebarWidth"] intValue] == 180,
             "bwsp SidebarWidth updated");
      });
  }

  /* --- 6. lsvp: unknown plist keys survive a sort-column update --- */
  {
    NSDictionary *finderLsvp = @{
      @"sortColumn" : @"name",
      @"ascending" : @YES,
      @"SomeFutureKey" : @[ @1, @2, @3 ],     /* unknown to Workspace */
    };
    NSArray *futureKeyArray = @[ @1, @2, @3 ];
    NSError *err = nil;
    NSData *lsvpData = [NSPropertyListSerialization
                         dataWithPropertyList: finderLsvp
                                       format: NSPropertyListBinaryFormat_v1_0
                                      options: 0
                                        error: &err];

    roundTrip(@[ [[[DSStoreEntry alloc]
                     initWithFilename: @"."
                                 code: @"lsvp"
                                 type: @"blob"
                                value: lsvpData] autorelease] ],
      ^(DSStore *store) {
        DSStoreEntry *e = [store entryForFilename: @"." code: @"lsvp"];
        DSStoreEntry *updated = [DSStoreEntry listViewEntryForFile: @"."
                                                        sortColumn: @"date"
                                                         ascending: NO
                                                          textSize: 12
                                                          iconSize: 0
                                                      columnWidths: @{ @"name" : @200 }
                                                     columnVisible: @{ @"name" : @YES }
                                                         preserving: e];
        [store setEntry: updated];
      },
      ^(DSStore *store) {
        DSStoreEntry *e = [store entryForFilename: @"." code: @"lsvp"];
        NSDictionary *parsed =
          [NSPropertyListSerialization propertyListWithData: (NSData *)[e value]
                                                    options: NSPropertyListImmutable
                                                     format: NULL
                                                      error: NULL];
        PASS([[parsed objectForKey: @"SomeFutureKey"] isEqual: futureKeyArray],
             "lsvp unknown key SomeFutureKey preserved");
        PASS([[parsed objectForKey: @"sortColumn"] isEqualToString: @"date"],
             "lsvp sortColumn updated");
      });
  }

  /* --- 7. out-of-range icon size is not clamped --- */
  {
    /* icvo size = 999 (unexpected but must survive unless the user changes
     * it).  Stored big-endian: 999 = 0x03E7 -> bytes 03 E7. */
    NSMutableData *icvo = [NSMutableData data];
    [icvo appendBytes: "icvo" length: 4];
    uint8_t zero[8] = { 0 };
    [icvo appendBytes: zero length: 8];
    uint8_t bigEndian999[2] = { 0x03, 0xE7 };
    [icvo appendBytes: bigEndian999 length: 2];
    [icvo appendBytes: "none" length: 4];
    NSData *size999Bytes = [NSData dataWithBytes: bigEndian999 length: 2];

    roundTrip(@[ [[[DSStoreEntry alloc]
                     initWithFilename: @"."
                                 code: @"icvo"
                                 type: @"blob"
                                value: icvo] autorelease] ],
      ^(DSStore *store) { /* no change at all */ },
      ^(DSStore *store) {
        DSStoreEntry *e = [store entryForFilename: @"." code: @"icvo"];
        NSData *v = (NSData *)[e value];
        NSData *gotSize = [v subdataWithRange: NSMakeRange(12, 2)];
        PASS([gotSize isEqual: size999Bytes],
             "out-of-range icvo size 999 survives load/save unchanged");
      });
  }

  /* --- 8. duplicate records survive unless explicitly replaced --- */
  {
    NSData *a = [NSData dataWithBytes: "\x01\x02\x03\x04" length: 4];
    NSData *b = [NSData dataWithBytes: "\x05\x06\x07\x08" length: 4];
    NSString *path = tmpStorePath(@"dup");

    [[NSFileManager defaultManager] removeFileAtPath: path handler: nil];
    /* Seed true duplicates directly (bypassing setEntry:, which dedups) as a
     * foreign Finder may have written them. */
    DSStoreEntry *ea = [[[DSStoreEntry alloc] initWithFilename: @"f"
                                                          code: @"qqqq"
                                                          type: @"blob"
                                                         value: a] autorelease];
    DSStoreEntry *eb = [[[DSStoreEntry alloc] initWithFilename: @"f"
                                                          code: @"qqqq"
                                                          type: @"blob"
                                                         value: b] autorelease];
    DSStore *w = [DSStore createStoreAtPath: path withEntries:
      [NSArray arrayWithObjects: ea, eb, nil]];
    [w save];

    DSStore *r = [DSStore storeWithPath: path];
    [r load];
    NSUInteger nBefore = 0;
    for (DSStoreEntry *e in [r entries])
      if ([[e filename] isEqualToString: @"f"] && [[e code] isEqualToString: @"qqqq"])
        nBefore++;
    [r save];

    DSStore *chk = [DSStore storeWithPath: path];
    [chk load];
    NSUInteger nAfter = 0;
    NSMutableSet *values = [NSMutableSet set];
    for (DSStoreEntry *e in [chk entries])
      if ([[e filename] isEqualToString: @"f"] && [[e code] isEqualToString: @"qqqq"])
        {
          nAfter++;
          [values addObject: [e value]];
        }
    PASS(nBefore == 2 && nAfter == 2,
         "duplicate records survive a no-op load/save");
    PASS([values count] == 2,
         "duplicate records keep both distinct values");

    [[NSFileManager defaultManager] removeFileAtPath: path handler: nil];
  }

  /* --- 9. atomic write: no temp file left behind, target intact --- */
  {
    NSString *path = tmpStorePath(@"atomic");
    [[NSFileManager defaultManager] removeFileAtPath: path handler: nil];

    DSStore *w = [DSStore createStoreAtPath: path withEntries: nil];
    [w setEntry: [DSStoreEntry iconLocationEntryForFile: @"f" x: 1 y: 2]];
    [w save];

    DSStore *r = [DSStore storeWithPath: path];
    [r load];
    [r setEntry: [DSStoreEntry iconLocationEntryForFile: @"f" x: 3 y: 4]];
    [r save];

    PASS([[NSFileManager defaultManager] fileExistsAtPath: path],
         "target .DS_Store exists after save");
    PASS(![[NSFileManager defaultManager] fileExistsAtPath:
            [path stringByAppendingString: @".tmp"]],
         "no .tmp file left behind (atomic rename used)");

    DSStore *chk = [DSStore storeWithPath: path];
    [chk load];
    PASS((int)[[chk entryForFilename: @"f" code: @"Iloc"] iconLocation].x == 3,
         "atomic-write content is the complete new file");

    [[NSFileManager defaultManager] removeFileAtPath: path handler: nil];
  }

  /* --- 10. integration: the full DSStoreInfo saveToPath: write path must
   * carry unknown records and partial icvo fields forward unchanged. --- */
  {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *dir = [NSTemporaryDirectory() stringByAppendingPathComponent:
                      [NSString stringWithFormat: @"t_preserve_integ_%d", (int)getpid()]];
    [fm removeFileAtPath: dir handler: nil];
    [fm createDirectoryAtPath: dir attributes: nil];
    [fm createFileAtPath: [dir stringByAppendingPathComponent: @"a.txt"]
                contents: [NSData data] attributes: nil];

    NSString *dsPath = [dir stringByAppendingPathComponent: @".DS_Store"];

    /* Seed: unknown record for a.txt + partial icvo (28-byte Finder shape). */
    NSData *unk = [NSData dataWithBytes: "\xDE\xAD\xBE\xEF" length: 4];
    NSMutableData *icvo = [NSMutableData data];
    [icvo appendBytes: "icvo" length: 4];
    uint8_t fz[8] = { 0xAA, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 };
    [icvo appendBytes: fz length: 8];
    uint16_t sz = 96;
    [icvo appendBytes: &sz length: 2];
    [icvo appendBytes: "auto" length: 4];
    uint8_t tail6[6] = { 0x10, 0x20, 0x30, 0x40, 0x50, 0x60 };
    [icvo appendBytes: tail6 length: 6];
    NSData *icvoSeed = [NSData dataWithData: icvo];

    DSStore *w = [DSStore createStoreAtPath: dsPath withEntries: nil];
    [w setEntry: [[[DSStoreEntry alloc] initWithFilename: @"a.txt"
                                                    code: @"qqqq"
                                                    type: @"blob"
                                                   value: unk] autorelease]];
    [w setEntry: [[[DSStoreEntry alloc] initWithFilename: @"."
                                                    code: @"icvo"
                                                    type: @"blob"
                                                   value: icvoSeed] autorelease]];
    [w save];

    /* Write through DSStoreInfo: change icon size to 128. */
    DSStoreInfo *info = [DSStoreInfo infoForDirectoryPath: dir];
    PASS(info != nil && info.loaded, "integration: DSStoreInfo loads the store");
    info.iconSize = 128;
    info.hasIconSize = YES;
    PASS([info saveToPath: dsPath], "integration: saveToPath succeeds");

    DSStore *chk = [DSStore storeWithPath: dsPath];
    [chk load];

    DSStoreEntry *unkE = [chk entryForFilename: @"a.txt" code: @"qqqq"];
    PASS(unkE != nil && [[unkE value] isEqual: unk],
         "integration: unknown record 'qqqq' survives the DSStoreInfo write");

    DSStoreEntry *icvoE = [chk entryForFilename: @"." code: @"icvo"];
    NSData *icvoV = (NSData *)[icvoE value];
    PASS([icvoV length] == 24, "integration: icvo keeps its 24-byte shape");
    const uint8_t *b = [icvoV bytes];
    PASS(b[12] == 0 && b[13] == 128, "integration: icvo size updated to 128");
    PASS(memcmp(b + 14, "auto", 4) == 0,
         "integration: icvo arrangement 'auto' preserved (not normalized)");
    NSData *gotTail = [icvoV subdataWithRange: NSMakeRange(18, 6)];
    NSData *wantTail = [NSData dataWithBytes: tail6 length: 6];
    PASS([gotTail isEqual: wantTail],
         "integration: icvo trailing bytes preserved by saveToPath:");

    [fm removeFileAtPath: dir handler: nil];
  }

  /* --- 11. integration: a directory-level unknown record (under ".") survives
   * a saveToPath: that changes a different directory field --- */
  {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *dir = [NSTemporaryDirectory() stringByAppendingPathComponent:
                      [NSString stringWithFormat: @"t_preserve_dirunk_%d", (int)getpid()]];
    [fm removeFileAtPath: dir handler: nil];
    [fm createDirectoryAtPath: dir attributes: nil];
    [fm createFileAtPath: [dir stringByAppendingPathComponent: @"a.txt"]
                contents: [NSData data] attributes: nil];

    NSString *dsPath = [dir stringByAppendingPathComponent: @".DS_Store"];
    NSData *unk = [NSData dataWithBytes: "\x11\x22\x33\x44\x55\x66" length: 6];

    /* Seed: unknown directory-level record + a view style. */
    {
      DSStore *store = [DSStore createStoreAtPath: dsPath withEntries: nil];
      [store load];
      [store setEntry: [[[DSStoreEntry alloc] initWithFilename: @"."
                                                          code: @"zzzz"
                                                          type: @"blob"
                                                         value: unk] autorelease]];
      [store setEntry: [DSStoreEntry viewStyleEntryForFile: @"." style: @"icnv"]];
      [store save];
    }

    /* Change only the icon size through DSStoreInfo. */
    DSStoreInfo *info = [DSStoreInfo infoForDirectoryPath: dir];
    info.iconSize = 96;
    info.hasIconSize = YES;
    PASS([info saveToPath: dsPath], "dir-unknown: saveToPath succeeds");

    DSStore *chk = [DSStore storeWithPath: dsPath];
    [chk load];
    DSStoreEntry *unkE = [chk entryForFilename: @"." code: @"zzzz"];
    PASS(unkE != nil && [[unkE value] isEqual: unk],
         "dir-unknown: unknown directory-level record survives saveToPath:");

    [fm removeFileAtPath: dir handler: nil];
  }

  [arp release];
  return 0;
}