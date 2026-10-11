/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 *
 * Assertions MI-INS-*: see Documentation/interop/assertions-p-inspector.md.
 * Headless: no window server is used.
 */
#import <Foundation/Foundation.h>
#import "Testing.h"
#import "GSFileMetadata.h"
#import "DSStore.h"
#include <arpa/inet.h>
#include "../../Inspector/FinderInfoModel.m"

@interface Recorder : NSObject <FinderInfoLocking>
@property BOOL state;
@property BOOL failNext;
@property (retain) NSMutableArray *log;
@end
@implementation Recorder
@synthesize state, failNext, log;
- (id)init { self = [super init]; log = [NSMutableArray new]; return self; }
- (void)dealloc { [log release]; [super dealloc]; }
- (BOOL)isImmutableAtPath:(NSString *)path { return state; }
- (BOOL)setImmutable:(BOOL)v atPath:(NSString *)path error:(NSError **)error
{
  if (failNext) {
    if (error) *error = [NSError errorWithDomain: @"t" code: 1 userInfo: nil];
    return NO;
  }
  [log addObject: [NSString stringWithFormat: @"set %d", v]];
  state = v;
  return YES;
}
@end

static NSString *tmpFile(NSString *tag)
{
  NSString *p = [NSString stringWithFormat: @"%@/fim-%@-%d",
                          NSTemporaryDirectory(), tag, (int)getpid()];
  [[NSFileManager defaultManager] removeFileAtPath: p handler: nil];
  [[NSFileManager defaultManager] createFileAtPath: p
                                          contents: [@"x" dataUsingEncoding: NSUTF8StringEncoding]
                                        attributes: nil];
  return p;
}

static NSData *rawFinderInfo(NSString *path)
{
  uint8_t buf[32];
  ssize_t n = gs_getxattr([path fileSystemRepresentation],
                          [GSXATTR_FINDERINFO UTF8String], buf, 32);
  return n == 32 ? [NSData dataWithBytes: buf length: 32] : nil;
}

static uint16_t flagWord(NSString *path)
{
  const uint8_t *b = [rawFinderInfo(path) bytes];
  return b ? (uint16_t)((b[8] << 8) | b[9]) : 0;
}

static BOOL xattrExists(NSString *path, NSString *name)
{
  return gs_getxattr([path fileSystemRepresentation], [name UTF8String], NULL, 0) >= 0;
}

int main(void)
{
  NSAutoreleasePool *arp = [NSAutoreleasePool new];
  NSString *p = tmpFile(@"a");
  NSError *err = nil;
  FinderInfoModel *m;

  /* Skip when the temp dir has no xattr support: nothing to assert then. */
  if (gs_setxattr([p fileSystemRepresentation], "user.gwprobe", "1", 1, 0) != 0) {
    NSLog(@"no user xattr support in temp dir; skipping");
    return 0;
  }
  gs_removexattr([p fileSystemRepresentation], "user.gwprobe");

  /* MI-INS-1: Hide extension is fdFlags 0x0010 in the big-endian word at 8-9. */
  m = [FinderInfoModel modelForPath: p];
  PASS(m.hideExtension == NO, "MI-INS-1 fresh file: extension not hidden");
  m.hideExtension = YES;
  PASS([m write: &err], "MI-INS-1 write");
  PASS((flagWord(p) & 0x0010) == 0x0010, "MI-INS-1 bit 0x0010 set on disk");
  PASS([rawFinderInfo(p) length] == 32, "MI-INS-1 FinderInfo stays 32 bytes");
  PASS([FinderInfoModel modelForPath: p].hideExtension == YES, "MI-INS-1 reads back");
  m.hideExtension = NO;
  [m write: NULL];
  PASS((flagWord(p) & 0x0010) == 0, "MI-INS-1 bit cleared");

  /* MI-INS-2: stationery 0x0800, invisible 0x4000, name locked 0x1000 */
  m = [FinderInfoModel modelForPath: p];
  m.stationery = YES; m.invisible = YES; m.nameLocked = YES;
  [m write: NULL];
  PASS((flagWord(p) & 0x5800) == 0x5800, "MI-INS-2 stationery+invisible+nameLocked bits");
  PASS((flagWord(p) & 0x0400) == 0, "MI-INS-2 no custom icon bit by accident");
  m = [FinderInfoModel modelForPath: p];
  PASS(m.stationery && m.invisible && m.nameLocked, "MI-INS-2 read back");
  m.stationery = NO; m.invisible = NO; m.nameLocked = NO;
  [m write: NULL];
  PASS((flagWord(p) & 0x5800) == 0, "MI-INS-2 cleared");

  /* MI-INS-3: type / creator are the first eight bytes, big-endian */
  m = [FinderInfoModel modelForPath: p];
  m.typeCode = @"TEXT"; m.creatorCode = @"ttxt";
  [m write: NULL];
  PASS(memcmp([rawFinderInfo(p) bytes], "TEXTttxt", 8) == 0, "MI-INS-3 bytes 0-7 are TEXTttxt");
  PASS_EQUAL([FinderInfoModel modelForPath: p].typeCode, @"TEXT", "MI-INS-3 type read back");
  PASS_EQUAL([FinderInfoModel modelForPath: p].creatorCode, @"ttxt", "MI-INS-3 creator read back");
  m.typeCode = @""; m.creatorCode = @"";
  [m write: NULL];
  PASS(memcmp([rawFinderInfo(p) bytes], "\0\0\0\0\0\0\0\0", 8) == 0, "MI-INS-3 empty means zero");

  /* MI-INS-4: invalid codes fail hard and change nothing */
  m = [FinderInfoModel modelForPath: p];
  m.typeCode = @"TOOLONG";
  err = nil;
  PASS([m write: &err] == NO && err != nil, "MI-INS-4 seven-char type rejected with error");
  PASS(![FinderInfoModel isValidCodeString: @"abc"], "MI-INS-4 three chars invalid");
  PASS(![FinderInfoModel isValidCodeString: @"abéd"], "MI-INS-4 non-ASCII invalid");
  PASS([FinderInfoModel isValidCodeString: @"    "], "MI-INS-4 four spaces valid");

  /* MI-INS-5: other FinderInfo bytes survive (fdLocation, 14-31) */
  {
    uint8_t seed[32]; int i;
    for (i = 0; i < 32; i++) seed[i] = (uint8_t)(0xA0 + i);
    seed[8] = 0; seed[9] = 0;
    gs_setxattr([p fileSystemRepresentation], [GSXATTR_FINDERINFO UTF8String], seed, 32, 0);
    [GSFileMetadata invalidateAllCachedMetadata];
    m = [FinderInfoModel modelForPath: p];
    m.hideExtension = YES;
    [m write: NULL];
    PASS(memcmp((const uint8_t *)[rawFinderInfo(p) bytes] + 10, seed + 10, 22) == 0,
         "MI-INS-5 bytes 10-31 untouched by flag edit");
  }

  /* MI-INS-6: label colour in bits 1-3 */
  m = [FinderInfoModel modelForPath: p];
  m.labelNumber = 5;
  [m write: NULL];
  /* Label 5 is Blue, which Finder stores as colour 4 (evidence E24). */
  PASS(((flagWord(p) >> 1) & 7) == 4, "MI-INS-6 label 5 (Blue) as Finder colour 4 in bits 1-3");
  PASS([FinderInfoModel modelForPath: p].labelNumber == 5, "MI-INS-6 read back");
  PASS((flagWord(p) & 0x0010) == 0x0010, "MI-INS-6 label edit keeps hidden-extension bit");

  /* MI-INS-7: comment is a binary plist string; clearing removes the xattr */
  m = [FinderInfoModel modelForPath: p];
  m.comment = @"Grüße";
  [m write: NULL];
  {
    char buf[256];
    ssize_t n = gs_getxattr([p fileSystemRepresentation],
                            [GSXATTR_FINDERCOMMENT UTF8String], buf, sizeof buf);
    PASS(n > 8 && memcmp(buf, "bplist00", 8) == 0, "MI-INS-7 comment stored as bplist00");
  }
  PASS_EQUAL([FinderInfoModel modelForPath: p].comment, @"Grüße", "MI-INS-7 unicode read back");
  m.comment = @"";
  [m write: NULL];
  PASS(!xattrExists(p, GSXATTR_FINDERCOMMENT), "MI-INS-7 empty comment removes the xattr");

  /* MI-INS-8: custom icon is a classic resource fork with icns -16455 */
  {
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc]
      initWithBitmapDataPlanes: NULL pixelsWide: 32 pixelsHigh: 32 bitsPerSample: 8
               samplesPerPixel: 4 hasAlpha: YES isPlanar: NO
                colorSpaceName: NSCalibratedRGBColorSpace bytesPerRow: 0 bitsPerPixel: 32];
    NSImage *img = [[NSImage alloc] initWithSize: NSMakeSize(32, 32)];
    NSData *icns;
    uint8_t rf[16384]; ssize_t n;

    [img addRepresentation: rep];
    icns = [FinderInfoIconBuilder icnsDataFromImage: img];
    PASS(icns != nil && memcmp([icns bytes], "icns", 4) == 0, "MI-INS-8 icns container magic");
    PASS(icns != nil && [icns length] >= 8
         && ntohl(*(uint32_t *)((const uint8_t *)[icns bytes] + 4)) == [icns length],
         "MI-INS-8 icns length field matches");
    {
      NSData *fork = [GSFileMetadata resourceForkWithICNS: icns];
      const uint8_t *f = [fork bytes];
      uint32_t dOff = ntohl(*(uint32_t *)f), mOff = ntohl(*(uint32_t *)(f + 4));
      uint32_t dLen = ntohl(*(uint32_t *)(f + 8)), mLen = ntohl(*(uint32_t *)(f + 12));
      PASS(dOff == 256 && mOff == dOff + dLen && [fork length] == mOff + mLen,
           "MI-INS-8 fork header offsets consistent");
      PASS(memcmp(f + mOff + 30, "icns", 4) == 0, "MI-INS-8 type list names icns");
      PASS(f[mOff + 38] == 0xBF && f[mOff + 39] == 0xB9, "MI-INS-8 resource id is -16455");
      PASS(memcmp(f + dOff + 4, "icns", 4) == 0, "MI-INS-8 data area holds the icns");
    }
    m = [FinderInfoModel modelForPath: p];
    PASS([m setCustomIconFromImage: img], "MI-INS-8 icon accepted");
    /* Where the fork lands depends on the file system (ext4 caps all
     * xattrs of a file near 4 KiB; GSFileMetadata then uses a sidecar), so
     * assert through the model, plus the on-disk bytes when they are there. */
    [m write: NULL];
    {
      FinderInfoModel *back = [FinderInfoModel modelForPath: p];
      PASS(back.hasCustomIcon, "MI-INS-8 custom icon flag reads back");
      PASS(back.customIconICNS != nil
           && memcmp([back.customIconICNS bytes], "icns", 4) == 0, "MI-INS-8 icns found again");
      n = gs_getxattr([p fileSystemRepresentation], [GSXATTR_RESOURCEFORK UTF8String], rf, sizeof rf);
      if (n > 0) {
        PASS((flagWord(p) & 0x0400) == 0x0400, "MI-INS-8 custom icon bit set on disk");
        PASS(n > 256 && rf[0] == 0 && rf[1] == 0 && rf[2] == 1 && rf[3] == 0,
             "MI-INS-8 on-disk fork starts with data offset 256");
      }
    }
    m = [FinderInfoModel modelForPath: p];
    [m clearCustomIcon];
    [m write: NULL];
    PASS(![FinderInfoModel modelForPath: p].hasCustomIcon, "MI-INS-9 clear drops the icon");
    PASS((flagWord(p) & 0x0400) == 0, "MI-INS-9 clear drops the bit");
    PASS(!xattrExists(p, GSXATTR_RESOURCEFORK), "MI-INS-9 clear removes the resource fork");
    [img release]; [rep release];
  }

  /* MI-INS-10: Locked goes through the locker; the file is unlocked for the
   * metadata write and locked again afterwards, in that order. */
  {
    Recorder *rec = [Recorder new];

    [FinderInfoModel setDefaultLocker: rec];
    rec.state = YES;
    m = [FinderInfoModel modelForPath: p];
    PASS(m.locked == YES, "MI-INS-10 locked state comes from the locker");
    m.hideExtension = YES;
    [rec.log removeAllObjects];
    PASS([m write: &err], "MI-INS-10 write of a locked file succeeds");
    PASS_EQUAL(rec.log, ([NSArray arrayWithObjects: @"set 0", @"set 1", nil]),
               "MI-INS-10 unlock before the write, lock again after");
    PASS((flagWord(p) & 0x0010) == 0x0010, "MI-INS-10 metadata written while unlocked");

    m = [FinderInfoModel modelForPath: p];
    m.locked = NO;
    [rec.log removeAllObjects];
    [m write: NULL];
    PASS_EQUAL(rec.log, ([NSArray arrayWithObjects: @"set 0", nil]),
               "MI-INS-10 unlocking leaves the file unlocked");
    PASS(rec.state == NO, "MI-INS-10 final state unlocked");

    m = [FinderInfoModel modelForPath: p];
    m.locked = YES;
    [rec.log removeAllObjects];
    [m write: NULL];
    PASS_EQUAL(rec.log, ([NSArray arrayWithObjects: @"set 1", nil]),
               "MI-INS-10 locking a plain file sets the flag once, after the write");

    rec.failNext = YES;
    m = [FinderInfoModel modelForPath: p];
    m.locked = NO;
    err = nil;
    PASS([m write: &err] == NO && err != nil, "MI-INS-10 a refused unlock is reported, not hidden");
    rec.failNext = NO;
    rec.state = NO;
    [FinderInfoModel setDefaultLocker: nil];
    [rec release];
  }

  /* MI-INS-11: folders do not get file-layout fields written */
  {
    NSString *d = [p stringByAppendingString: @"-dir"];
    uint8_t before[8], after[8];
    [[NSFileManager defaultManager] createDirectoryAtPath: d attributes: nil];
    m = [FinderInfoModel modelForPath: d];
    PASS(m.isDirectory, "MI-INS-11 directory detected");
    m.typeCode = @"TEXT"; m.stationery = YES; m.invisible = YES;
    [m write: NULL];
    memcpy(after, [rawFinderInfo(d) bytes], 8);
    memset(before, 0, 8);
    PASS(memcmp(before, after, 8) == 0, "MI-INS-11 folder bytes 0-7 (window rect) stay zero");
    PASS((flagWord(d) & 0x4000) && !(flagWord(d) & 0x0800), "MI-INS-11 invisible set, stationery ignored");
    [[NSFileManager defaultManager] removeFileAtPath: d handler: nil];
  }


  /* MI-INS-14: a folder's custom icon lives in an invisible "Icon\r" file
   * inside it (E18), plus kHasCustomIcon on the folder. */
  {
    NSString *d = [NSString stringWithFormat: @"%@/fim-icondir-%d", NSTemporaryDirectory(), (int)getpid()];
    NSString *iconFile = [d stringByAppendingString: @"/Icon\r"];
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc]
      initWithBitmapDataPlanes: NULL pixelsWide: 32 pixelsHigh: 32 bitsPerSample: 8
               samplesPerPixel: 4 hasAlpha: YES isPlanar: NO
                colorSpaceName: NSCalibratedRGBColorSpace bytesPerRow: 0 bitsPerPixel: 32];
    NSImage *img = [[NSImage alloc] initWithSize: NSMakeSize(32, 32)];
    FinderInfoModel *back;
    GSFileMetadata *imd;

    [img addRepresentation: rep];
    [[NSFileManager defaultManager] removeFileAtPath: d handler: nil];
    [[NSFileManager defaultManager] createDirectoryAtPath: d attributes: nil];
    m = [FinderInfoModel modelForPath: d];
    PASS([m setCustomIconFromImage: img], "MI-INS-14 folder icon accepted");
    PASS([m write: &err], "MI-INS-14 folder write succeeds");
    PASS((flagWord(d) & 0x0400) == 0x0400, "MI-INS-14 folder carries kHasCustomIcon");
    PASS([[NSFileManager defaultManager] fileExistsAtPath: iconFile],
         "MI-INS-14 Icon\\r file exists in the folder");
    PASS([[[NSFileManager defaultManager] fileAttributesAtPath: iconFile traverseLink: NO]
           fileSize] == 0, "MI-INS-14 Icon\\r data fork is empty");
    PASS((flagWord(iconFile) & 0x4000) == 0x4000, "MI-INS-14 Icon\\r is invisible");
    [GSFileMetadata invalidateAllCachedMetadata];
    imd = [GSFileMetadata metadataForFileAtPath: iconFile forceSidecar: NO];
    PASS([GSFileMetadata icnsDataFromResourceFork: [imd resourceFork]] != nil
         && memcmp([[GSFileMetadata icnsDataFromResourceFork: [imd resourceFork]] bytes], "icns", 4) == 0,
         "MI-INS-14 Icon\\r resource fork holds icns -16455");
    back = [FinderInfoModel modelForPath: d];
    PASS(back.hasCustomIcon && back.customIconICNS != nil, "MI-INS-14 folder icon read back");
    [back clearCustomIcon];
    PASS([back write: &err], "MI-INS-14 clearing the folder icon writes");
    PASS((flagWord(d) & 0x0400) == 0, "MI-INS-14 clear drops kHasCustomIcon on the folder");
    PASS(![[NSFileManager defaultManager] fileExistsAtPath: iconFile],
         "MI-INS-14 clear removes Icon\\r");
    PASS(![FinderInfoModel modelForPath: d].hasCustomIcon, "MI-INS-14 cleared folder reads plain");
    [[NSFileManager defaultManager] removeFileAtPath: d handler: nil];
    [img release]; [rep release];
  }

  /* MI-INS-15: the comment is also the item's cmmt record in the parent's
   * .DS_Store; every other record stays (E8). */
  {
    NSString *d = [NSString stringWithFormat: @"%@/fim-cmmt-%d", NSTemporaryDirectory(), (int)getpid()];
    NSString *f = [d stringByAppendingString: @"/doc.txt"];
    NSString *store = [d stringByAppendingString: @"/.DS_Store"];
    DSStore *s;

    [[NSFileManager defaultManager] removeFileAtPath: d handler: nil];
    [[NSFileManager defaultManager] createDirectoryAtPath: d attributes: nil];
    [[NSFileManager defaultManager] createFileAtPath: f contents: [NSData data] attributes: nil];
    m = [FinderInfoModel modelForPath: f];
    m.comment = @"first";
    PASS([m write: &err], "MI-INS-15 comment write without a store");
    s = [DSStore storeWithPath: store];
    PASS([s load], "MI-INS-15 a store was created");
    PASS_EQUAL([s commentsForFilename: @"doc.txt"], @"first", "MI-INS-15 cmmt record holds the comment");
    [s setIconLocationForFilename: @"doc.txt" x: 40 y: 50];
    [s setIconLocationForFilename: @"other.txt" x: 90 y: 60];
    [s setCommentsForFilename: @"other.txt" comments: @"theirs"];
    PASS([s save], "MI-INS-15 store saved with foreign records");

    m = [FinderInfoModel modelForPath: f];
    m.comment = @"second";
    PASS([m write: &err], "MI-INS-15 comment rewrite");
    s = [DSStore storeWithPath: store];
    [s load];
    PASS_EQUAL([s commentsForFilename: @"doc.txt"], @"second", "MI-INS-15 cmmt replaced");
    PASS_EQUAL([s commentsForFilename: @"other.txt"], @"theirs", "MI-INS-15 other item's cmmt kept");
    PASS([s iconLocationForFilename: @"doc.txt"].x == 40
         && [s iconLocationForFilename: @"other.txt"].x == 90, "MI-INS-15 Iloc records kept");

    m = [FinderInfoModel modelForPath: f];
    m.comment = @"";
    PASS([m write: &err], "MI-INS-15 comment cleared");
    s = [DSStore storeWithPath: store];
    [s load];
    PASS([s commentsForFilename: @"doc.txt"] == nil, "MI-INS-15 empty comment removes the cmmt record");
    PASS_EQUAL([s commentsForFilename: @"other.txt"], @"theirs", "MI-INS-15 clearing keeps the others");

    /* A store that cannot be read is an error, not silently replaced. */
    [@"junk" writeToFile: store atomically: NO];
    m = [FinderInfoModel modelForPath: f];
    m.comment = @"third";
    err = nil;
    PASS([m write: &err] == NO && err != nil, "MI-INS-15 unreadable store fails hard");
    [[NSFileManager defaultManager] removeFileAtPath: d handler: nil];
  }

  [[NSFileManager defaultManager] removeFileAtPath: p handler: nil];
  [GSFileMetadata invalidateAllCachedMetadata];
  [arp release];
  return 0;
}
