/* t_IMetaWrite.m - write paths of GSFileMetadata: sidecar merge, removal of
 * emptied xattrs, classic resource fork for custom icons, Finder flags.
 * Headless.
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */
#import <Foundation/Foundation.h>
#import "Testing.h"
#import "GSFileMetadata.h"
#import "GWMetaXattr.h"
#import "GSAppleDouble.h"
#include <unistd.h>

static void be16(NSMutableData *d, uint16_t v)
{
  uint8_t b[2] = { v >> 8, v };
  [d appendBytes: b length: 2];
}

static void be32(NSMutableData *d, uint32_t v)
{
  uint8_t b[4] = { v >> 24, v >> 16, v >> 8, v };
  [d appendBytes: b length: 4];
}

/* A minimal icns container: header plus one element. */
static NSData *fakeICNS(void)
{
  NSMutableData *d = [NSMutableData data];
  [d appendBytes: "icns" length: 4];
  be32(d, 8 + 8 + 5);
  [d appendBytes: "ic07" length: 4];
  be32(d, 8 + 5);
  [d appendBytes: "PNG!!" length: 5];
  return d;
}

/* AppleDouble with FinderInfo (9) and an entry id nobody here manages. */
static NSData *sidecarWithUnknownEntry(void)
{
  NSMutableData *d = [NSMutableData data];
  uint8_t fi[32] = { 0 };

  be32(d, 0x00051607);
  be32(d, 0x00020000);
  [d appendBytes: "Mac OS X        " length: 16];
  be16(d, 2);
  be32(d, 9);      be32(d, 26 + 24); be32(d, 32);
  be32(d, 0x7777); be32(d, 26 + 24 + 32); be32(d, 6);
  [d appendBytes: fi length: 32];
  [d appendBytes: "UNKNWN" length: 6];
  return d;
}

static NSData *D2(const char *s)
{
  return [NSData dataWithBytes: s length: strlen(s)];
}

static BOOL hasXattr(NSString *path, NSString *name)
{
  return gs_getxattr([path fileSystemRepresentation], [name UTF8String],
                     NULL, 0) >= 0;
}

static NSData *xattrBytes(NSString *path, NSString *name)
{
  ssize_t n = gs_getxattr([path fileSystemRepresentation], [name UTF8String],
                          NULL, 0);
  if (n < 0)
    return nil;
  NSMutableData *d = [NSMutableData dataWithLength: n];
  gs_getxattr([path fileSystemRepresentation], [name UTF8String],
              [d mutableBytes], n);
  return d;
}

static void putXattr(NSString *path, NSString *name, NSData *v)
{
  gs_setxattr([path fileSystemRepresentation], [name UTF8String],
              [v bytes], [v length], 0);
}

static NSData *fileBytes(NSString *p)
{
  return [NSData dataWithContentsOfFile: p];
}

static BOOL contains(NSData *d, const char *needle)
{
  NSData *n = [NSData dataWithBytes: needle length: strlen(needle)];
  return d != nil && [d rangeOfData: n options: 0
                              range: NSMakeRange(0, [d length])].location
                     != NSNotFound;
}

int main(void)
{
  NSAutoreleasePool *arp = [NSAutoreleasePool new];
  NSFileManager *fm = [NSFileManager defaultManager];
  NSString *dir = [NSTemporaryDirectory() stringByAppendingPathComponent:
    [NSString stringWithFormat: @"imeta-%d", (int)getpid()]];
  [fm removeFileAtPath: dir handler: nil];
  [fm createDirectoryAtPath: dir attributes: nil];

  /* --- MI-META-1: sidecar rewrite keeps unknown entries --- */
  {
    NSString *f = [dir stringByAppendingPathComponent: @"a.txt"];
    NSString *sc = [GSFileMetadata sidecarPathForFilePath: f];
    [fm createFileAtPath: f contents: [NSData data] attributes: nil];
    [sidecarWithUnknownEntry() writeToFile: sc atomically: NO];

    GSFileMetadata *md = [GSFileMetadata metadataForFileAtPath: f
                                                  forceSidecar: YES];
    PASS(md != nil, "sidecar with unknown entry is readable");
    [md setLabelNumber: GSFileLabelRed];
    NSError *err = nil;
    PASS([md writeSidecarToFileAtPath: f error: &err],
         "sidecar rewrite succeeds");
    NSData *after = fileBytes(sc);
    PASS(contains(after, "UNKNWN"),
         "MI-META-1 unknown AppleDouble entry survives a rewrite");
    GSFileMetadata *again = [GSFileMetadata metadataForFileAtPath: f
                                                     forceSidecar: YES];
    PASS([again labelNumber] == GSFileLabelRed,
         "the managed change is in the rewritten sidecar");
  }

  /* --- MI-META-2: emptied comment leaves no xattr and no sidecar record --- */
  {
    NSString *f = [dir stringByAppendingPathComponent: @"b.txt"];
    [fm createFileAtPath: f contents: [NSData data] attributes: nil];
    GSFileMetadata *md = [[[GSFileMetadata alloc] init] autorelease];
    [md setFinderComment: @"hello"];
    [md setLabelNumber: GSFileLabelBlue];
    PASS([md writeToFileAtPath: f error: NULL], "write with comment");
    PASS(hasXattr(f, GSXATTR_FINDERCOMMENT), "comment xattr written");
    [md setFinderComment: nil];
    PASS([md writeToFileAtPath: f error: NULL], "write without comment");
    PASS(!hasXattr(f, GSXATTR_FINDERCOMMENT),
         "MI-META-2 nil comment removes the comment xattr");
    [md setFinderComment: @"again"];
    [md writeToFileAtPath: f error: NULL];
    [md setFinderComment: @""];
    [md writeToFileAtPath: f error: NULL];
    PASS(!hasXattr(f, GSXATTR_FINDERCOMMENT),
         "MI-META-2 empty comment removes the comment xattr");

    /* same through the sidecar */
    GSFileMetadata *sm = [[[GSFileMetadata alloc] init] autorelease];
    [sm setFinderComment: @"side"];
    [sm writeSidecarToFileAtPath: f error: NULL];
    NSString *sc = [GSFileMetadata sidecarPathForFilePath: f];
    PASS(contains(fileBytes(sc), "kMDItemFinderComment"), "comment in sidecar");
    [sm setFinderComment: nil];
    [sm setLabelNumber: GSFileLabelRed];
    [sm writeSidecarToFileAtPath: f error: NULL];
    PASS(!contains(fileBytes(sc), "kMDItemFinderComment"),
         "MI-META-2 nil comment leaves the sidecar without the record");
  }

  /* --- MI-META-3/4: custom icon is a classic resource fork --- */
  {
    NSData *icns = fakeICNS();
    GSFileMetadata *md = [[[GSFileMetadata alloc] init] autorelease];
    [md setCustomIconData: icns];
    NSData *fork = [md resourceFork];
    PASS(fork != nil && ![fork isEqual: icns],
         "MI-META-3 the stored fork is not the raw icns bytes");
    PASS([fork length] == 256 + 4 + [icns length] + 50,
         "fork is header + 256 byte gap + length-prefixed data + 50 byte map");
    PASS([md hasCustomIcon], "custom icon flag set");
    PASS_EQUAL([md customIconData], icns,
               "MI-META-3 icns round-trips through the resource fork");

    /* Reading accepts the old form: raw icns as the whole fork. */
    GSFileMetadata *old = [[[GSFileMetadata alloc] init] autorelease];
    [old setResourceFork: icns];
    [old setCustomIcon: YES];
    PASS_EQUAL([old customIconData], icns,
               "MI-META-4 raw icns in the fork is still read");

    /* A fork without resource -16455 has no custom icon. */
    NSMutableData *other = [[fork mutableCopy] autorelease];
    const uint8_t *h = [other bytes];
    uint32_t mapOff = (h[4] << 24) | (h[5] << 16) | (h[6] << 8) | h[7];
    uint8_t *m = [other mutableBytes] + mapOff + 28 + 2 + 8;
    m[0] = 0; m[1] = 1;   /* id 1 */
    GSFileMetadata *wrong = [[[GSFileMetadata alloc] init] autorelease];
    [wrong setResourceFork: other];
    [wrong setCustomIcon: YES];
    PASS([wrong customIconData] == nil,
         "MI-META-3 an icns resource with another id is not the custom icon");

    /* clear removes the fork xattr on disk */
    NSString *f = [dir stringByAppendingPathComponent: @"c.txt"];
    [fm createFileAtPath: f contents: [NSData data] attributes: nil];
    [md writeToFileAtPath: f error: NULL];
    PASS(hasXattr(f, GSXATTR_RESOURCEFORK), "fork xattr written");
    [md clearCustomIcon];
    PASS([md writeToFileAtPath: f error: NULL], "write after clear");
    PASS(!hasXattr(f, GSXATTR_RESOURCEFORK),
         "MI-META-5 clearCustomIcon then write removes the ResourceFork xattr");

    /* and the sidecar carries no fork either */
    GSFileMetadata *sm = [[[GSFileMetadata alloc] init] autorelease];
    [sm setCustomIconData: icns];
    [sm setLabelNumber: GSFileLabelRed];
    [sm writeSidecarToFileAtPath: f error: NULL];
    PASS([[GSFileMetadata metadataForFileAtPath: f forceSidecar: YES]
           customIconData] != nil, "icon in the sidecar");
    [sm clearCustomIcon];
    [sm writeSidecarToFileAtPath: f error: NULL];
    PASS([[[GSFileMetadata metadataForFileAtPath: f forceSidecar: YES]
           resourceFork] length] == 0,
         "MI-META-5 clearCustomIcon then sidecar write drops the fork");
  }

  /* --- MI-META-6: Finder flag names --- */
  {
    GSFileMetadata *md = [[[GSFileMetadata alloc] init] autorelease];
    PASS(![md isExtensionHidden], "extension not hidden by default");
    [md setExtensionHidden: YES];
    PASS([md isExtensionHidden] && ([md finderFlags] & 0x0010) == 0x0010,
         "MI-META-6 extensionHidden is fdFlags 0x0010");
    PASS(![md isNameLocked], "name not locked");
    [md setNameLocked: YES];
    PASS([md isNameLocked] && ([md finderFlags] & 0x1000) == 0x1000,
         "MI-META-6 nameLocked is fdFlags 0x1000");
    [md setExtensionHidden: NO];
    PASS(![md isExtensionHidden] && [md isNameLocked],
         "flags are independent");
  }

  /* --- MI-META-9: fields nobody changed stay as they are on disk --- */
  {
    NSData *fork = [@"FORKDATA" dataUsingEncoding: NSASCIIStringEncoding];
    /* Not what -setFinderComment: would write, so a rewrite shows. */
    NSData *comment = [NSPropertyListSerialization
      dataWithPropertyList: @"kept comment"
                    format: NSPropertyListXMLFormat_v1_0
                   options: 0 error: NULL];
    NSData *tags = [NSPropertyListSerialization
      dataWithPropertyList: [NSArray arrayWithObjects: @"Foo", @"Bar", nil]
                    format: NSPropertyListXMLFormat_v1_0
                   options: 0 error: NULL];
    NSData *quar = [@"0001;5f000000;App;" dataUsingEncoding:
                      NSASCIIStringEncoding];
    NSString *f = [dir stringByAppendingPathComponent: @"d.txt"];
    [fm createFileAtPath: f contents: [NSData data] attributes: nil];
    putXattr(f, GSXATTR_RESOURCEFORK, fork);
    putXattr(f, GSXATTR_FINDERCOMMENT, comment);
    putXattr(f, GSXATTR_USERTAGS, tags);
    putXattr(f, GSXATTR_QUARANTINE, quar);

    GSFileMetadata *fresh = [[[GSFileMetadata alloc] init] autorelease];
    [fresh setLabelNumber: GSFileLabelRed];
    PASS([fresh writeToFileAtPath: f error: NULL], "write fresh object");
    PASS_EQUAL(xattrBytes(f, GSXATTR_RESOURCEFORK), fork,
               "MI-META-9 fresh object leaves the ResourceFork xattr");
    PASS_EQUAL(xattrBytes(f, GSXATTR_FINDERCOMMENT), comment,
               "MI-META-9 fresh object leaves the comment xattr");
    {
      /* The label is a tag too: it is added, the other tags are not lost. */
      NSArray *t = [NSPropertyListSerialization
        propertyListWithData: xattrBytes(f, GSXATTR_USERTAGS) options: 0
                      format: NULL error: NULL];
      NSArray *want = [NSArray arrayWithObjects: @"Foo", @"Bar", @"Red", nil];
      PASS_EQUAL(t, want,
                 "MI-META-9 fresh object keeps the other tags and adds its label");
    }
    PASS_EQUAL(xattrBytes(f, GSXATTR_QUARANTINE), quar,
               "MI-META-9 fresh object leaves the quarantine xattr");

    /* A loaded object that only changes the label rewrites nothing else. */
    [GSFileMetadata invalidateAllCachedMetadata];
    GSFileMetadata *loaded = [GSFileMetadata metadataForFileAtPath: f];
    GSFileMetadata *edit = [[loaded copy] autorelease];
    [edit setLabelNumber: GSFileLabelBlue];
    [edit writeToFileAtPath: f error: NULL];
    PASS_EQUAL(xattrBytes(f, GSXATTR_FINDERCOMMENT), comment,
               "MI-META-9 loaded object keeps the comment bytes");
    PASS_EQUAL(xattrBytes(f, GSXATTR_RESOURCEFORK), fork,
               "MI-META-9 loaded object keeps the fork bytes");
    PASS_EQUAL(xattrBytes(f, GSXATTR_QUARANTINE), quar,
               "MI-META-9 loaded object keeps the quarantine bytes");

    /* An explicit change still removes. */
    GSFileMetadata *clr = [[[GSFileMetadata alloc] init] autorelease];
    [clr setFinderComment: nil];
    [clr setQuarantine: nil];
    [clr writeToFileAtPath: f error: NULL];
    PASS(!hasXattr(f, GSXATTR_FINDERCOMMENT) && !hasXattr(f, GSXATTR_QUARANTINE),
         "MI-META-9 an explicit nil removes just that field");
    PASS_EQUAL(xattrBytes(f, GSXATTR_RESOURCEFORK), fork,
               "MI-META-9 other fields still untouched");

    /* Sidecar: same contract. */
    NSString *g = [dir stringByAppendingPathComponent: @"e.txt"];
    [fm createFileAtPath: g contents: [NSData data] attributes: nil];
    GSFileMetadata *full = [[[GSFileMetadata alloc] init] autorelease];
    [full setResourceFork: fork];
    [full setFinderComment: @"kept comment"];
    [full setUserTagsData: tags];
    [full setQuarantine: @"0001;5f000000;App;"];
    [full setLabelNumber: GSFileLabelGreen];
    [full writeSidecarToFileAtPath: g error: NULL];
    GSFileMetadata *only = [[[GSFileMetadata alloc] init] autorelease];
    [only setLabelNumber: GSFileLabelRed];
    [only writeSidecarToFileAtPath: g error: NULL];
    GSFileMetadata *back = [GSFileMetadata metadataForFileAtPath: g
                                                    forceSidecar: YES];
    PASS_EQUAL([back resourceFork], fork, "MI-META-9 sidecar keeps the fork");
    PASS_EQUAL([back finderComment], @"kept comment",
               "MI-META-9 sidecar keeps the comment");
    PASS_EQUAL([back quarantine], @"0001;5f000000;App;",
               "MI-META-9 sidecar keeps the quarantine");
    PASS([back labelNumber] == GSFileLabelRed, "the label did change");
    PASS_EQUAL([back userTags],
               ([NSArray arrayWithObjects: @"Foo", @"Bar", @"Red", nil]),
               "MI-META-9 sidecar keeps the other tags and adds the label");
  }

  /* --- MI-META-10: FinderInfo bytes nobody changed stay as on disk --- */
  {
    uint8_t pat[32];
    for (int i = 0; i < 32; i++) pat[i] = (uint8_t)(0xA0 + i);
    pat[8] = 0x00; pat[9] = 0x10;   /* fdFlags: extension hidden only */
    NSData *fi = [NSData dataWithBytes: pat length: 32];
    NSString *f = [dir stringByAppendingPathComponent: @"fi.txt"];
    [fm createFileAtPath: f contents: [NSData data] attributes: nil];
    putXattr(f, GSXATTR_FINDERINFO, fi);

    GSFileMetadata *fresh = [[[GSFileMetadata alloc] init] autorelease];
    [fresh setLabelNumber: GSFileLabelRed];
    [fresh writeToFileAtPath: f error: NULL];
    uint8_t want[32];
    memcpy(want, pat, 32);
    want[9] = 0x10 | (GSFileLabelRed << 1);
    PASS_EQUAL(xattrBytes(f, GSXATTR_FINDERINFO),
               [NSData dataWithBytes: want length: 32],
               "MI-META-10 a label change touches only the label bits");

    /* Loaded object clearing a flag */
    [GSFileMetadata invalidateAllCachedMetadata];
    GSFileMetadata *l = [[[GSFileMetadata metadataForFileAtPath: f] copy]
                          autorelease];
    [l setExtensionHidden: NO];
    [l writeToFileAtPath: f error: NULL];
    want[9] = (GSFileLabelRed << 1);
    PASS_EQUAL(xattrBytes(f, GSXATTR_FINDERINFO),
               [NSData dataWithBytes: want length: 32],
               "MI-META-10 a cleared flag clears just that bit");

    /* Sidecar entry 9 */
    NSString *g = [dir stringByAppendingPathComponent: @"fi2.txt"];
    [fm createFileAtPath: g contents: [NSData data] attributes: nil];
    GSAppleDouble *ad = [[[GSAppleDouble alloc] init] autorelease];
    [ad setFinderInfo: fi];
    [[ad appleDoubleData] writeToFile: [GSFileMetadata sidecarPathForFilePath: g]
                           atomically: NO];
    GSFileMetadata *s = [[[GSFileMetadata alloc] init] autorelease];
    [s setLabelNumber: GSFileLabelRed];
    [s writeSidecarToFileAtPath: g error: NULL];
    GSFileMetadata *back = [GSFileMetadata metadataForFileAtPath: g
                                                    forceSidecar: YES];
    want[9] = 0x10 | (GSFileLabelRed << 1);
    PASS_EQUAL([[back finderInfo] subdataWithRange: NSMakeRange(0, 32)],
               [NSData dataWithBytes: want length: 32],
               "MI-META-10 sidecar entry 9 keeps the bytes nobody changed");
  }

  /* --- MI-META-11: an xattr write does not lose what the sidecar holds --- */
  {
    NSString *f = [dir stringByAppendingPathComponent: @"mig.txt"];
    [fm createFileAtPath: f contents: [NSData data] attributes: nil];
    NSString *sc = [GSFileMetadata sidecarPathForFilePath: f];
    GSAppleDouble *ad = [[[GSAppleDouble alloc] init] autorelease];
    uint8_t z[32] = { 0 };
    [ad setFinderInfo: [NSData dataWithBytes: z length: 32]];
    [ad setXattr: D2("VALUE") forKey: @"com.example.migrate"];
    [[ad appleDoubleData] writeToFile: sc atomically: NO];

    GSFileMetadata *fresh = [[[GSFileMetadata alloc] init] autorelease];
    [fresh setLabelNumber: GSFileLabelBlue];
    [fresh writeToFileAtPath: f error: NULL];
    PASS_EQUAL(xattrBytes(f, @"user.com.example.migrate"), D2("VALUE"),
               "MI-META-11 a sidecar attribute is moved to an xattr");
    PASS(![fm fileExistsAtPath: sc],
         "MI-META-11 a fully migrated sidecar is deleted");

    /* an entry xattrs cannot hold keeps the sidecar */
    NSString *g = [dir stringByAppendingPathComponent: @"keep.txt"];
    [fm createFileAtPath: g contents: [NSData data] attributes: nil];
    NSString *gsc = [GSFileMetadata sidecarPathForFilePath: g];
    [sidecarWithUnknownEntry() writeToFile: gsc atomically: NO];
    GSFileMetadata *f2 = [[[GSFileMetadata alloc] init] autorelease];
    [f2 setLabelNumber: GSFileLabelBlue];
    [f2 writeToFileAtPath: g error: NULL];
    PASS(contains(fileBytes(gsc), "UNKNWN"),
         "MI-META-11 a sidecar with an unknown entry is kept");

    /* an explicit removal is not undone by the sidecar */
    NSString *h = [dir stringByAppendingPathComponent: @"rm.txt"];
    [fm createFileAtPath: h contents: [NSData data] attributes: nil];
    GSAppleDouble *ad2 = [[[GSAppleDouble alloc] init] autorelease];
    [ad2 setFinderInfo: [NSData dataWithBytes: z length: 32]];
    [ad2 setXattr: D2("old") forKey: @"com.apple.quarantine"];
    [[ad2 appleDoubleData] writeToFile:
      [GSFileMetadata sidecarPathForFilePath: h] atomically: NO];
    GSFileMetadata *f3 = [[[GSFileMetadata alloc] init] autorelease];
    [f3 setQuarantine: nil];
    [f3 writeToFileAtPath: h error: NULL];
    PASS(!hasXattr(h, GSXATTR_QUARANTINE),
         "MI-META-11 a cleared field is not resurrected from the sidecar");
  }

  /* --- MI-META-12: a fresh object can clear what it did not read --- */
  {
    uint8_t pat[32];
    for (int i = 0; i < 32; i++) pat[i] = (uint8_t)(0xA0 + i);
    pat[8] = 0x40; pat[9] = 0x10 | (GSFileLabelRed << 1);   /* invisible, hidden ext, Red */
    NSString *f = [dir stringByAppendingPathComponent: @"clr.txt"];
    [fm createFileAtPath: f contents: [NSData data] attributes: nil];
    putXattr(f, GSXATTR_FINDERINFO, [NSData dataWithBytes: pat length: 32]);
    putXattr(f, GSXATTR_USERTAGS, [NSPropertyListSerialization
      dataWithPropertyList: [NSArray arrayWithObjects: @"Red", @"Foo", nil]
                    format: NSPropertyListBinaryFormat_v1_0 options: 0 error: NULL]);

    GSFileMetadata *a = [[[GSFileMetadata alloc] init] autorelease];
    [a setLabelNumber: GSFileLabelNone];
    [a writeToFileAtPath: f error: NULL];
    uint8_t want[32];
    memcpy(want, pat, 32);
    want[9] = 0x10;
    PASS_EQUAL(xattrBytes(f, GSXATTR_FINDERINFO),
               [NSData dataWithBytes: want length: 32],
               "MI-META-12 fresh label None clears the label, other bits stay");
    NSArray *tags = [NSPropertyListSerialization
      propertyListWithData: xattrBytes(f, GSXATTR_USERTAGS) options: 0
                    format: NULL error: NULL];
    PASS_EQUAL(tags, [NSArray arrayWithObject: @"Foo"],
               "MI-META-12 fresh label None removes the colour tag only");

    GSFileMetadata *b = [[[GSFileMetadata alloc] init] autorelease];
    [b setInvisible: NO];
    [b writeToFileAtPath: f error: NULL];
    want[8] = 0x00;
    PASS_EQUAL(xattrBytes(f, GSXATTR_FINDERINFO),
               [NSData dataWithBytes: want length: 32],
               "MI-META-12 fresh object clears kIsInvisible and nothing else");

    /* sidecar */
    NSString *g = [dir stringByAppendingPathComponent: @"clr2.txt"];
    [fm createFileAtPath: g contents: [NSData data] attributes: nil];
    GSAppleDouble *ad = [[[GSAppleDouble alloc] init] autorelease];
    [ad setFinderInfo: [NSData dataWithBytes: pat length: 32]];
    [[ad appleDoubleData] writeToFile: [GSFileMetadata sidecarPathForFilePath: g]
                           atomically: NO];
    GSFileMetadata *c = [[[GSFileMetadata alloc] init] autorelease];
    [c setInvisible: NO];
    [c writeSidecarToFileAtPath: g error: NULL];
    memcpy(want, pat, 32);
    want[8] = 0x00;
    PASS_EQUAL([[[GSFileMetadata metadataForFileAtPath: g forceSidecar: YES]
                  finderInfo] subdataWithRange: NSMakeRange(0, 32)],
               [NSData dataWithBytes: want length: 32],
               "MI-META-12 sidecar entry 9 clears just that bit");
  }

  [fm removeFileAtPath: dir handler: nil];
  [arp release];
  return 0;
}
