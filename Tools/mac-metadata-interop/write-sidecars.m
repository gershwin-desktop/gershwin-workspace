/* write-sidecars.m — create Gershwin-written metadata fixtures.
 *
 * Part of the reverse-interoperability check (Gershwin -> macOS): produces
 * a directory of data files plus ._ AppleDouble sidecars written by the
 * real GWMetadata sources (compiled in-process), and an EXPECTED.plist
 * describing exactly what was written.  Tools/mac-metadata-interop/
 * verify-reverse.sh ships this directory to a Mac, ingests the sidecars
 * with `dot_clean -m`, and verifies macOS ends up with the same metadata.
 *
 * Usage: write-sidecars <output-dir>
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

#import <Foundation/Foundation.h>
#include "GWMetaArchive.h"
#include "GWMetaXattr.h"
#include "GSAppleDouble.h"
#include "GSFileMetadata.h"
#include "GWMetaArchive.m"
#include "GWMetaXattr.m"
#include "GSAppleDouble.m"
#include "GSFileMetadata.m"

int
main(int argc, const char **argv)
{
  NSAutoreleasePool *arp = [NSAutoreleasePool new];

  if (argc < 2)
    {
      fprintf(stderr, "usage: write-sidecars <output-dir> [zip-path]\n");
      return 2;
    }
  NSString *dir = [NSString stringWithUTF8String: argv[1]];
  NSFileManager *fm = [NSFileManager defaultManager];
  [fm removeFileAtPath: dir handler: nil];
  if (![fm createDirectoryAtPath: dir withIntermediateDirectories: YES
                      attributes: nil error: NULL])
    {
      fprintf(stderr, "cannot create %s\n", [dir UTF8String]);
      return 2;
    }

  NSMutableDictionary *expected = [NSMutableDictionary dictionary];

  /* A helper writing one fixture: data file + forced ._ sidecar. */
  void (^writeFixture)(NSString *, NSData *, GSFileMetadata *) =
    ^(NSString *name, NSData *content, GSFileMetadata *md)
    {
      NSString *path = [dir stringByAppendingPathComponent: name];
      [fm createFileAtPath: path contents: content attributes: nil];
      NSMutableDictionary *rec = [NSMutableDictionary dictionary];
      if (md != nil)
        {
          /* Explicitly a ._ sidecar: that is the artifact we ship to
           * the Mac (Linux xattrs would not travel anyway). */
          BOOL ok = [md writeSidecarToFileAtPath: path error: NULL];
          if (!ok)
            {
              fprintf(stderr, "FAILED to write sidecar for %s\n",
                      [name UTF8String]);
              exit(2);
            }
          [rec setObject: [NSNumber numberWithBool: YES]
                  forKey: @"hasMetadata"];
          /* Record what is actually IN the FinderInfo bytes (big-endian
           * fdFlags per TN1150) rather than getter values - the getters
           * apply fallbacks (e.g. labelNumber from a colour tag) that
           * have no on-disk counterpart and would false-fail. */
          NSData *finfo = [md finderInfo];
          if (finfo && [finfo length] >= 32)
            {
              const uint8_t *b = [finfo bytes];
              uint16_t flags = (uint16_t)((b[8] << 8) | b[9]);
              [rec setObject:
                [NSNumber numberWithUnsignedInt:
                  ((uint32_t)b[0] << 24) | ((uint32_t)b[1] << 16)
                | ((uint32_t)b[2] << 8) | (uint32_t)b[3]]
                  forKey: @"typeCode"];
              [rec setObject:
                [NSNumber numberWithUnsignedInt:
                  ((uint32_t)b[4] << 24) | ((uint32_t)b[5] << 16)
                | ((uint32_t)b[6] << 8) | (uint32_t)b[7]]
                  forKey: @"creatorCode"];
              [rec setObject:
                [NSNumber numberWithInteger: (flags >> 1) & 0x7]
                  forKey: @"labelNumber"];
              [rec setObject:
                [NSNumber numberWithBool: (flags & (1 << 11)) != 0]
                  forKey: @"invisible"];
              [rec setObject:
                [NSNumber numberWithBool: (flags & (1 << 7)) != 0]
                  forKey: @"customIcon"];
            }
          NSArray *tags = [md userTags];
          if (tags)
            [rec setObject: tags forKey: @"userTags"];
          if ([md finderComment])
            [rec setObject: [md finderComment] forKey: @"finderComment"];
          if ([md quarantine])
            [rec setObject: [md quarantine] forKey: @"quarantine"];
          NSData *rf = [md resourceFork];
          if (rf && [rf length])
            {
              NSMutableString *hex = [NSMutableString string];
              const uint8_t *b = [rf bytes];
              for (NSUInteger i = 0; i < [rf length]; i++)
                [hex appendFormat: @"%02x", b[i]];
              [rec setObject: hex forKey: @"resourceForkHex"];
            }
        }
      else
        {
          [rec setObject: [NSNumber numberWithBool: NO]
                  forKey: @"hasMetadata"];
        }
      [expected setObject: rec forKey: name];
    };

  /* --- r1: FinderInfo only ------------------------------------------- */
  {
    GSFileMetadata *md = [[[GSFileMetadata alloc] init] autorelease];
    [md setTypeCode: 'TEXT'];
    [md setCreatorCode: 'ttxt'];
    [md setLabelNumber: 1];
    [md setInvisible: YES];
    writeFixture(@"r1_finderinfo.txt", [@"gershwin r1" 
      dataUsingEncoding: NSUTF8StringEncoding], md);
  }

  /* --- r2: custom icon bit + resource fork ---------------------------- */
  {
    GSFileMetadata *md = [[[GSFileMetadata alloc] init] autorelease];
    [md setCustomIcon: YES];
    [md setResourceFork: [NSData dataWithBytes: "CAFEBABE" length: 8]];
    writeFixture(@"r2_resourcefork.txt", [@"gershwin r2"
      dataUsingEncoding: NSUTF8StringEncoding], md);
  }

  /* --- r3: Finder tags ------------------------------------------------ */
  {
    GSFileMetadata *md = [[[GSFileMetadata alloc] init] autorelease];
    [md setUserTags: @[ @"Red", @"ProjectX" ]];
    writeFixture(@"r3_tags.txt", [@"gershwin r3"
      dataUsingEncoding: NSUTF8StringEncoding], md);
  }

  /* --- r4: Finder comment --------------------------------------------- */
  {
    GSFileMetadata *md = [[[GSFileMetadata alloc] init] autorelease];
    [md setFinderComment: @"gershwin wrote this"];
    writeFixture(@"r4_comment.txt", [@"gershwin r4"
      dataUsingEncoding: NSUTF8StringEncoding], md);
  }

  /* --- r5: everything combined ---------------------------------------- */
  {
    GSFileMetadata *md = [[[GSFileMetadata alloc] init] autorelease];
    [md setTypeCode: 'TEXT'];
    [md setCreatorCode: 'ttxt'];
    [md setLabelNumber: 1];
    [md setInvisible: YES];
    [md setCustomIcon: YES];
    [md setResourceFork: [NSData dataWithBytes: "DEADCODE" length: 8]];
    [md setUserTags: @[ @"Green", @"Release" ]];
    [md setFinderComment: @"combined from gershwin"];
    writeFixture(@"r5_combined.txt", [@"gershwin r5"
      dataUsingEncoding: NSUTF8StringEncoding], md);
  }

  /* --- r6: control ------------------------------------------------------ */
  writeFixture(@"r6_control.txt", [@"gershwin r6"
    dataUsingEncoding: NSUTF8StringEncoding], nil);

  /* --- r7: quarantine record -------------------------------------------- */
  {
    GSFileMetadata *md = [[[GSFileMetadata alloc] init] autorelease];
    [md setQuarantine:
      @"0083;6a8c59f3;Gershwin;12345678-90AB-CDEF-1234-567890ABCDEF"];
    writeFixture(@"r7_quarantine.txt", [@"gershwin r7"
      dataUsingEncoding: NSUTF8StringEncoding], md);
  }


  /* Manifest as XML plist - readable by macOS plutil/python everywhere. */
  NSData *manifest = [NSPropertyListSerialization
    dataFromPropertyList: expected
                  format: NSPropertyListXMLFormat_v1_0
        errorDescription: NULL];
  [manifest writeToFile: [dir stringByAppendingPathComponent:
                                    @"EXPECTED.plist"]
             atomically: YES];

  /* --- optional visual-check set (argv[3] == "with-visual") -------------
   * One file per Finder colour label, all VISIBLE, so a human can verify
   * the colours in Finder itself after dot_clean ingestion. */
  if (argc >= 4 && strcmp(argv[3], "with-visual") == 0)
    {
      struct { NSInteger label; const char *name; } vis[] = {
        { 1, "v1_label_red.txt" },
        { 2, "v2_label_orange.txt" },
        { 3, "v3_label_yellow.txt" },
        { 4, "v4_label_green.txt" },
        { 5, "v5_label_blue.txt" },
        { 6, "v6_label_purple.txt" },
        { 7, "v7_label_grey.txt" },
      };
      for (NSUInteger i = 0; i < sizeof(vis)/sizeof(vis[0]); i++)
        {
          GSFileMetadata *md = [[[GSFileMetadata alloc] init] autorelease];
          [md setTypeCode: 'TEXT'];
          [md setCreatorCode: 'ttxt'];
          [md setLabelNumber: vis[i].label];
          NSString *nm = [NSString stringWithUTF8String: vis[i].name];
          writeFixture(nm, [@"visual" dataUsingEncoding:
                              NSUTF8StringEncoding], md);
        }
    }

  /* --- optionally also emit a GWMetaArchive zip of the tree --------------
   * argv[2]: exercises the __MACOSX-companion writing path so the Mac can
   * verify zips Gershwin produces (ditto -x -k applies them natively). */
  if (argc >= 3)
    {
      NSString *zipPath = [NSString stringWithUTF8String: argv[2]];
      NSError *err = nil;
      if (![GWMetaArchive compressDirectory: dir
                                toArchiveAt: zipPath
                                      error: &err])
        {
          fprintf(stderr, "compressDirectory failed: %s\n",
                  err ? [[err description] UTF8String] : "?");
          return 2;
        }
      printf("wrote zip %s\n", [zipPath UTF8String]);
    }

  printf("wrote %lu fixtures to %s\n",
         (unsigned long)[expected count], [dir UTF8String]);
  [arp release];
  return 0;
}
