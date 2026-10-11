/* t_GWMetaArchive.m - archives exchanged with a Mac keep Finder metadata.
 *
 * Extraction: a zip the way Finder's "Compress" writes it (__MACOSX/._name
 * entries) and tar/ditto archives (._name beside the item) give the extracted
 * items their labels, comments, custom icons, resource forks and all other
 * attributes, and leave no __MACOSX folder or ._ file behind.  The AppleDouble
 * bytes are the real 10.6 files of evidence E15.
 *
 * Compression: every item with metadata gets a __MACOSX/._name entry laid out
 * as ditto -c -k --sequesterRsrc lays it out (entry 9 then entry 2).
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */
#import <Foundation/Foundation.h>
#import "Testing.h"
#import "GWMetaArchive.h"
#import "GSFileMetadata.h"
#import "GSAppleDouble.h"
#import "GWMetaXattr.h"

#include <archive.h>
#include <archive_entry.h>

static NSFileManager *fm;
static NSString *root;
static NSString *fixDir;

static NSData *
getx(NSString *path, NSString *name)
{
  const char *c = [path fileSystemRepresentation];
  ssize_t n = gs_getxattr(c, [name UTF8String], NULL, 0);
  if (n < 0)
    return nil;
  NSMutableData *d = [NSMutableData dataWithLength: n];
  if (n > 0 && gs_getxattr(c, [name UTF8String], [d mutableBytes], n) != n)
    return nil;
  return d;
}

static NSString *
fresh(NSString *name)
{
  NSString *p = [root stringByAppendingPathComponent: name];
  [fm removeFileAtPath: p handler: nil];
  [fm createDirectoryAtPath: p attributes: nil];
  return p;
}

static NSData *
fixture(NSString *name)
{
  return [NSData dataWithContentsOfFile: [fixDir stringByAppendingPathComponent: name]];
}

/* Entries to put into a test archive: path -> data (nil data = directory). */
static BOOL
writeArchive(NSString *path, BOOL zip, NSArray *names, NSArray *datas)
{
  struct archive *a = archive_write_new();
  NSUInteger i;
  if (zip)
    archive_write_set_format_zip(a);
  else
    archive_write_set_format_pax_restricted(a);
  archive_write_open_filename(a, [path fileSystemRepresentation]);
  for (i = 0; i < [names count]; i++)
    {
      id d = [datas objectAtIndex: i];
      struct archive_entry *e = archive_entry_new();
      archive_entry_set_pathname(e, [[names objectAtIndex: i] UTF8String]);
      if ([d isKindOfClass: [NSData class]])
        {
          archive_entry_set_filetype(e, AE_IFREG);
          archive_entry_set_perm(e, 0644);
          archive_entry_set_size(e, [d length]);
        }
      else
        {
          archive_entry_set_filetype(e, AE_IFDIR);
          archive_entry_set_perm(e, 0755);
        }
      archive_write_header(a, e);
      if ([d isKindOfClass: [NSData class]] && [d length])
        archive_write_data(a, [d bytes], [d length]);
      archive_entry_free(e);
    }
  archive_write_close(a);
  archive_write_free(a);
  return YES;
}

/* name -> data of every file entry of an archive; directories map to NSNull. */
static NSDictionary *
readArchive(NSString *path)
{
  NSMutableDictionary *out = [NSMutableDictionary dictionary];
  struct archive *a = archive_read_new();
  struct archive_entry *e;
  archive_read_support_format_all(a);
  archive_read_support_filter_all(a);
  if (archive_read_open_filename(a, [path fileSystemRepresentation], 10240) != ARCHIVE_OK)
    return out;
  while (archive_read_next_header(a, &e) == ARCHIVE_OK)
    {
      NSString *n = [NSString stringWithUTF8String: archive_entry_pathname(e)];
      if (archive_entry_filetype(e) == AE_IFDIR)
        {
          [out setObject: [NSNull null] forKey: n];
          continue;
        }
      NSMutableData *d = [NSMutableData data];
      char buf[4096];
      ssize_t r;
      while ((r = archive_read_data(a, buf, sizeof buf)) > 0)
        [d appendBytes: buf length: r];
      [out setObject: d forKey: n];
    }
  archive_read_free(a);
  return out;
}

/* Every attribute of the AppleDouble must be on the extracted item, or, on a
 * volume without attributes, in its sidecar. */
static void
checkApplied(NSData *adData, NSString *path, const char *what)
{
  GSAppleDouble *ad = [[[GSAppleDouble alloc] initWithData: adData] autorelease];
  /* Probe the parent: the probe writes, and the item may be read-only. */
  BOOL xattrs = gs_xattr_supported([[path stringByDeletingLastPathComponent]
    fileSystemRepresentation]) == 1;

  /* A value too big for the volume's attributes (the 70 KB icon fork of
   * the real zips) puts everything into the sidecar, byte for byte. */
  NSData *side = [NSData dataWithContentsOfFile:
    [GSFileMetadata sidecarPathForFilePath: path]];
  if (!xattrs || side != nil)
    {
      PASS_EQUAL(side, adData, "%s: kept in the sidecar (no attributes or too big)", what);
      return;
    }
  if ([ad hasFinderInfo])
    PASS_EQUAL(getx(path, @"user.com.apple.FinderInfo"), [ad finderInfo],
               "%s: FinderInfo applied", what);
  if ([ad hasResourceFork] && [[ad resourceFork] length])
    PASS_EQUAL(getx(path, @"user.com.apple.ResourceFork"), [ad resourceFork],
               "%s: resource fork applied", what);
  NSDictionary *attrs = [ad extendedAttributes];
  for (NSString *k in [attrs allKeys])
    PASS_EQUAL(getx(path, [@"user." stringByAppendingString: k]),
               [attrs objectForKey: k], "%s: attribute %s applied", what,
               [k UTF8String]);
  PASS(![fm fileExistsAtPath: [GSFileMetadata sidecarPathForFilePath: path]],
       "%s: no sidecar left where attributes work", what);
}

static void
checkClean(NSString *dir, const char *what, BOOL sidecarsOK)
{
  PASS(![fm fileExistsAtPath: [dir stringByAppendingPathComponent: @"__MACOSX"]],
       "%s: no __MACOSX folder", what);
  NSString *rel;
  BOOL leftover = NO;
  NSDirectoryEnumerator *en = [fm enumeratorAtPath: dir];
  while ((rel = [en nextObject]) != nil)
    if ([[rel lastPathComponent] hasPrefix: @"._"])
      leftover = YES;
  PASS(!leftover || gs_xattr_supported([dir fileSystemRepresentation]) != 1
       || sidecarsOK, "%s: no ._ file left where attributes work", what);
}

int main(void)
{
  NSAutoreleasePool *pool = [NSAutoreleasePool new];
  fm = [NSFileManager defaultManager];
  root = [NSTemporaryDirectory() stringByAppendingPathComponent:
            [NSString stringWithFormat: @"gw_archive_%d", (int)getpid()]];
  [fm removeFileAtPath: root handler: nil];
  [fm createDirectoryAtPath: root attributes: nil];
  fixDir = [[fm currentDirectoryPath] stringByAppendingPathComponent:
    @"../GWMetadata/interop/fixtures/finder106"];

  NSData *manyAD = fixture(@"E15-appledouble-ditto/many.txt.ad");
  NSData *rsrcAD = fixture(@"E15-appledouble-ditto/rsrc.txt.ad");
  NSData *dirAD = fixture(@"E15-appledouble-ditto/dir.ad");
  NSData *fiAD = fixture(@"E15-appledouble-ditto/fi.txt.ad");
  PASS(manyAD && rsrcAD && dirAD && fiAD, "E15 fixtures present");
  NSData *body = [@"hello" dataUsingEncoding: NSUTF8StringEncoding];

  /* --- Finder "Compress" zip: folder with files and a subfolder ---------- */
  {
    NSString *zip = [root stringByAppendingPathComponent: @"finder.zip"];
    writeArchive(zip, YES,
      @[ @"proj/", @"proj/many.txt", @"proj/rsrc.txt", @"proj/plain.txt",
         @"proj/sub/", @"proj/sub/fi.txt",
         @"__MACOSX/", @"__MACOSX/._proj", @"__MACOSX/proj/",
         @"__MACOSX/proj/._many.txt", @"__MACOSX/proj/._rsrc.txt",
         @"__MACOSX/proj/._sub", @"__MACOSX/proj/sub/._fi.txt" ],
      @[ [NSNull null], body, body, body, [NSNull null], body,
         [NSNull null], dirAD, [NSNull null], manyAD, rsrcAD, dirAD, fiAD ]);
    NSString *dest = fresh(@"out-zip");
    NSError *err = nil;
    PASS([GWMetaArchive extractArchive: zip toDir: dest error: &err],
         "MI-AR-1 Finder zip extracts (%s)", err ? [[err description] UTF8String] : "ok");
    PASS_EQUAL([NSData dataWithContentsOfFile:
                  [dest stringByAppendingPathComponent: @"many.txt"]], body,
               "MI-AR-1 data fork intact");
    checkApplied(manyAD, [dest stringByAppendingPathComponent: @"many.txt"], "MI-AR-2 many.txt");
    checkApplied(rsrcAD, [dest stringByAppendingPathComponent: @"rsrc.txt"], "MI-AR-3 rsrc.txt");
    checkApplied(dirAD, [dest stringByAppendingPathComponent: @"sub"], "MI-AR-4 folder");
    checkApplied(fiAD, [dest stringByAppendingPathComponent: @"sub/fi.txt"], "MI-AR-5 nested file");
    checkClean(dest, "MI-AR-6 zip", NO);
    PASS(getx([dest stringByAppendingPathComponent: @"plain.txt"],
                 @"user.com.apple.FinderInfo") == nil,
         "MI-AR-7 an item without companion gets no metadata");
  }

  /* --- two top-level items: the folder entry keeps its name and label ---- */
  {
    NSString *zip = [root stringByAppendingPathComponent: @"two.zip"];
    writeArchive(zip, YES,
      @[ @"a.txt", @"folder/", @"folder/b.txt",
         @"__MACOSX/._a.txt", @"__MACOSX/._folder" ],
      @[ body, [NSNull null], body, manyAD, dirAD ]);
    NSString *dest = fresh(@"out-two");
    PASS([GWMetaArchive extractArchive: zip toDir: dest error: NULL],
         "MI-AR-8 zip with two top-level items extracts");
    checkApplied(manyAD, [dest stringByAppendingPathComponent: @"a.txt"], "MI-AR-8 file");
    checkApplied(dirAD, [dest stringByAppendingPathComponent: @"folder"],
                 "MI-AR-8 folder entry that ends in a slash");
    checkClean(dest, "MI-AR-8", NO);
  }

  /* --- tar / ditto: ._name beside the item ------------------------------ */
  {
    NSString *tar = [root stringByAppendingPathComponent: @"mac.tar"];
    writeArchive(tar, NO,
      @[ @"many.txt", @"._many.txt", @"d/", @"d/rsrc.txt", @"d/._rsrc.txt",
         @"._d", @"._notmeta" ],
      @[ body, manyAD, [NSNull null], body, rsrcAD, dirAD, body ]);
    NSString *dest = fresh(@"out-tar");
    NSError *err = nil;
    PASS([GWMetaArchive extractArchive: tar toDir: dest error: &err],
         "MI-AR-9 tar with ._ entries extracts (%s)", err ? [[err description] UTF8String] : "ok");
    checkApplied(manyAD, [dest stringByAppendingPathComponent: @"many.txt"], "MI-AR-9 tar file");
    checkApplied(rsrcAD, [dest stringByAppendingPathComponent: @"d/rsrc.txt"], "MI-AR-9 tar nested");
    checkApplied(dirAD, [dest stringByAppendingPathComponent: @"d"], "MI-AR-9 tar folder");
    PASS([fm fileExistsAtPath: [dest stringByAppendingPathComponent: @"._notmeta"]],
         "MI-AR-10 a file named ._x that is not AppleDouble is extracted as a file");
    PASS(![fm fileExistsAtPath: [dest stringByAppendingPathComponent: @"._many.txt"]]
         || gs_xattr_supported([dest fileSystemRepresentation]) != 1,
         "MI-AR-9 companion consumed");
  }

  /* --- read-only file in the archive ------------------------------------ */
  {
    NSString *zip = [root stringByAppendingPathComponent: @"ro.zip"];
    struct archive *a = archive_write_new();
    archive_write_set_format_zip(a);
    archive_write_open_filename(a, [zip fileSystemRepresentation]);
    NSArray *n = @[ @"ro.txt", @"__MACOSX/._ro.txt" ];
    NSArray *dd = @[ body, manyAD ];
    NSArray *mode = @[ @0444, @0644 ];
    for (int i = 0; i < 2; i++)
      {
        struct archive_entry *e = archive_entry_new();
        archive_entry_set_pathname(e, [[n objectAtIndex: i] UTF8String]);
        archive_entry_set_filetype(e, AE_IFREG);
        archive_entry_set_perm(e, [[mode objectAtIndex: i] intValue]);
        archive_entry_set_size(e, [[dd objectAtIndex: i] length]);
        archive_write_header(a, e);
        archive_write_data(a, [[dd objectAtIndex: i] bytes], [[dd objectAtIndex: i] length]);
        archive_entry_free(e);
      }
    archive_write_close(a);
    archive_write_free(a);
    NSString *dest = fresh(@"out-ro");
    PASS([GWMetaArchive extractArchive: zip toDir: dest error: NULL],
         "MI-AR-11 read-only item extracts");
    NSString *f = [dest stringByAppendingPathComponent: @"ro.txt"];
    checkApplied(manyAD, f, "MI-AR-11 read-only file");
    PASS(([[[fm fileAttributesAtPath: f traverseLink: NO]
            objectForKey: NSFilePosixPermissions] intValue] & 0222) == 0,
         "MI-AR-11 it stays read-only");
  }

  /* --- compression ------------------------------------------------------- */
  {
    NSString *src = fresh(@"src");
    NSString *folder = [src stringByAppendingPathComponent: @"proj"];
    [fm createDirectoryAtPath: folder attributes: nil];
    NSString *labelled = [folder stringByAppendingPathComponent: @"labelled.txt"];
    NSString *plain = [folder stringByAppendingPathComponent: @"plain.txt"];
    NSString *sub = [folder stringByAppendingPathComponent: @"sub"];
    [body writeToFile: labelled atomically: NO];
    [body writeToFile: plain atomically: NO];
    [fm createDirectoryAtPath: sub attributes: nil];

    GSFileMetadata *md = [[GSFileMetadata alloc] init];
    [md setLabelNumber: 6];
    [md setFinderComment: @"a comment"];
    [md setResourceFork: [GSFileMetadata resourceForkWithICNS:
      [@"icnsxxxx" dataUsingEncoding: NSUTF8StringEncoding]]];
    [md setCustomIcon: YES];
    BOOL wrote = [md writeToFileAtPath: labelled error: NULL];
    [md release];
    BOOL xattrs = gs_xattr_supported([labelled fileSystemRepresentation]) == 1;
    PASS(wrote, "compress fixture written");
    gs_setxattr([labelled fileSystemRepresentation], "user.org.example.other",
                "value", 5, 0);
    GSFileMetadata *dm = [[GSFileMetadata alloc] init];
    [dm setLabelNumber: 2];
    [dm writeToFileAtPath: sub error: NULL];
    [dm release];

    NSString *zip = [root stringByAppendingPathComponent: @"made.zip"];
    NSError *err = nil;
    PASS([GWMetaArchive compressPaths: @[ folder ] toArchiveAt: zip error: &err],
         "MI-AR-12 compress (%s)", err ? [[err description] UTF8String] : "ok");
    NSDictionary *ents = readArchive(zip);
    PASS([ents objectForKey: @"proj/labelled.txt"] != nil, "MI-AR-12 data entry stored");
    if (xattrs)
      {
        NSData *ad = [ents objectForKey: @"__MACOSX/proj/._labelled.txt"];
        PASS(ad != nil, "MI-AR-13 __MACOSX/proj/._labelled.txt stored");
        const uint8_t *b = [ad bytes];
        PASS([ad length] > 50 && b[0] == 0 && b[1] == 5 && b[2] == 0x16 && b[3] == 7
             && b[25] == 2, "MI-AR-14 AppleDouble with 2 entries");
        PASS(b[26+3] == 9 && b[38+3] == 2, "MI-AR-14 entry 9 then entry 2 [F: E15, E17]");
        GSAppleDouble *p = [[[GSAppleDouble alloc] initWithData: ad] autorelease];
        PASS([[p finderInfo] length] == 32, "MI-AR-14 FinderInfo is 32 bytes");
        PASS_EQUAL([p finderInfo], getx(labelled, @"user.com.apple.FinderInfo"),
                   "MI-AR-15 FinderInfo (label, custom icon flag) stored");
        PASS_EQUAL([p resourceFork], getx(labelled, @"user.com.apple.ResourceFork"),
                   "MI-AR-15 resource fork (custom icon) stored");
        PASS_EQUAL([[p extendedAttributes] objectForKey: @"org.example.other"],
                   [@"value" dataUsingEncoding: NSUTF8StringEncoding],
                   "MI-AR-16 attributes GSFileMetadata does not model are stored");
        PASS([[p extendedAttributes] objectForKey:
                @"com.apple.metadata:kMDItemFinderComment"] != nil,
             "MI-AR-16 Finder comment stored");
        PASS([ents objectForKey: @"__MACOSX/proj/._sub"] != nil,
             "MI-AR-17 folder with a label gets a companion");
      }
    PASS([ents objectForKey: @"__MACOSX/proj/._plain.txt"] == nil,
         "MI-AR-18 item without metadata gets no companion");

    /* round trip */
    NSString *dest = fresh(@"out-round");
    PASS([GWMetaArchive extractArchive: zip toDir: [dest stringByAppendingPathComponent: @"x"]
                                 error: NULL], "MI-AR-19 own zip extracts");
    NSString *back = [dest stringByAppendingPathComponent: @"x/labelled.txt"];
    PASS_EQUAL(getx(back, @"user.com.apple.FinderInfo"),
               getx(labelled, @"user.com.apple.FinderInfo"), "MI-AR-19 round trip FinderInfo");
    PASS_EQUAL(getx(back, @"user.com.apple.ResourceFork"),
               getx(labelled, @"user.com.apple.ResourceFork"), "MI-AR-19 round trip fork");
    PASS_EQUAL(getx(back, @"user.org.example.other"),
               getx(labelled, @"user.org.example.other"), "MI-AR-19 round trip other attribute");
    PASS_EQUAL(getx([dest stringByAppendingPathComponent: @"x/sub"], @"user.com.apple.FinderInfo"),
               getx(sub, @"user.com.apple.FinderInfo"), "MI-AR-19 round trip folder label");
    checkClean(dest, "MI-AR-19", NO);
  }

  /* --- an all-zero companion carries nothing ----------------------------- */
  {
    NSMutableData *zero = [NSMutableData dataWithData: fiAD];
    GSAppleDouble *zp = [[[GSAppleDouble alloc] init] autorelease];
    [zp setFinderInfo: [NSMutableData dataWithLength: 32]];
    zero = [NSMutableData dataWithData: [zp appleDoubleData]];
    NSString *tar = [root stringByAppendingPathComponent: @"zero.tar"];
    writeArchive(tar, NO, @[ @"z.txt", @"._z.txt" ], @[ body, zero ]);
    NSString *dest = fresh(@"out-zero");
    PASS([GWMetaArchive extractArchive: tar toDir: dest error: NULL], "MI-AR-25 zero companion extracts");
    PASS(getx([dest stringByAppendingPathComponent: @"z.txt"], @"user.com.apple.FinderInfo") == nil,
         "MI-AR-25 an all-zero FinderInfo sets nothing");
  }

  /* --- real zips of 10.6 (E29) ------------------------------------------ */
  {
    NSString *z = [fixDir stringByAppendingPathComponent: @"E29-zips"];
    NSDictionary *finder = readArchive([z stringByAppendingPathComponent:
      @"proj-labelled-folder-finder.zip"]);
    NSData *projAD = [finder objectForKey: @"__MACOSX/._proj"];
    NSData *labeledAD = [finder objectForKey: @"__MACOSX/proj/._labeled.txt"];
    PASS(projAD && labeledAD, "E29 Finder zip fixture present");

    /* Workspace extracts into a folder it creates for the archive. */
    NSString *dest = fresh(@"out-e29");
    [fm removeFileAtPath: dest handler: nil];
    NSError *err = nil;
    PASS([GWMetaArchive extractArchive: [z stringByAppendingPathComponent:
            @"proj-labelled-folder-finder.zip"] toDir: dest error: &err],
         "MI-AR-20 real Finder zip extracts (%s)", err ? [[err description] UTF8String] : "ok");
    checkApplied(labeledAD, [dest stringByAppendingPathComponent: @"labeled.txt"],
                 "MI-AR-20 real labeled.txt");
    checkApplied(projAD, dest, "MI-AR-21 the labelled top folder: its label lands on the folder extracted into");
    PASS_EQUAL([NSData dataWithContentsOfFile:
                  [dest stringByAppendingPathComponent: @".DS_Store"]],
               [finder objectForKey: @"proj/.DS_Store"],
               "MI-AR-22 the zipped .DS_Store is the folder's own store and is extracted");
    checkApplied([finder objectForKey: @"__MACOSX/proj/._.DS_Store"],
                 [dest stringByAppendingPathComponent: @".DS_Store"],
                 "MI-AR-22 .DS_Store keeps the invisible flag Finder gave it");
    checkClean(dest, "MI-AR-20 real zip", YES);

    /* a folder that existed before is never relabelled */
    NSString *pre = fresh(@"out-e29-pre");
    PASS([GWMetaArchive extractArchive: [z stringByAppendingPathComponent:
            @"proj-labelled-folder-finder.zip"] toDir: pre error: NULL],
         "MI-AR-26 extracting into an existing folder works");
    PASS(getx(pre, @"user.com.apple.FinderInfo") == nil
         && ![fm fileExistsAtPath: [GSFileMetadata sidecarPathForFilePath: pre]],
         "MI-AR-26 an existing folder keeps its metadata untouched");

    /* extracting into a folder that already has a store keeps that store */
    NSString *dest2 = fresh(@"out-e29-existing");
    NSData *mine = [@"mine" dataUsingEncoding: NSUTF8StringEncoding];
    [mine writeToFile: [dest2 stringByAppendingPathComponent: @".DS_Store"] atomically: NO];
    PASS([GWMetaArchive extractArchive: [z stringByAppendingPathComponent:
            @"proj-labelled-folder-finder.zip"] toDir: dest2 error: NULL],
         "MI-AR-23 extracting into a folder with a store works");
    PASS_EQUAL([NSData dataWithContentsOfFile:
                  [dest2 stringByAppendingPathComponent: @".DS_Store"]], mine,
               "MI-AR-23 the folder's existing .DS_Store is kept");

    /* ditto --keepParent writes no ._proj: the folder gets nothing */
    NSString *dest3 = fresh(@"out-e29-ditto");
    PASS([GWMetaArchive extractArchive: [z stringByAppendingPathComponent:
            @"proj-ditto.zip"] toDir: dest3 error: NULL], "MI-AR-24 real ditto zip extracts");
    PASS(getx(dest3, @"user.com.apple.FinderInfo") == nil,
         "MI-AR-24 no top folder companion, no metadata on the folder");
    NSDictionary *dd = readArchive([z stringByAppendingPathComponent: @"proj-ditto.zip"]);
    checkApplied([dd objectForKey: @"__MACOSX/proj/._labeled.txt"],
                 [dest3 stringByAppendingPathComponent: @"labeled.txt"],
                 "MI-AR-24 real ditto labeled.txt");
    checkApplied([dd objectForKey: @"__MACOSX/proj/._subfolder"],
                 [dest3 stringByAppendingPathComponent: @"subfolder"],
                 "MI-AR-24 real ditto subfolder");
  }

  /* --- quarantine in a companion: 10.6 keeps it only with "q/" ---------- */
  {
    NSData *plainQ = [@"0000;4e8f1c2a;Safari;" dataUsingEncoding: NSUTF8StringEncoding];
    NSData *sideQ = [@"q/0000;4e8f1c2a;Safari;" dataUsingEncoding: NSUTF8StringEncoding];
    NSString *src = fresh(@"src-q");
    NSString *f = [src stringByAppendingPathComponent: @"dl.txt"];
    [body writeToFile: f atomically: NO];
    gs_setxattr([f fileSystemRepresentation], "user.com.apple.quarantine",
                [plainQ bytes], [plainQ length], 0);
    NSString *zip = [root stringByAppendingPathComponent: @"q.zip"];
    PASS([GWMetaArchive compressPaths: @[ f ] toArchiveAt: zip error: NULL],
         "MI-AR-27 file with quarantine compresses");
    NSData *ad = [readArchive(zip) objectForKey: @"__MACOSX/._dl.txt"];
    GSAppleDouble *p = ad ? [[[GSAppleDouble alloc] initWithData: ad] autorelease] : nil;
    PASS_EQUAL([[p extendedAttributes] objectForKey: @"com.apple.quarantine"], sideQ,
               "MI-AR-27 the companion holds the quarantine with the q/ prefix 10.6 needs [F: Referee]");

    /* a value that has the prefix already is not doubled */
    gs_setxattr([f fileSystemRepresentation], "user.com.apple.quarantine",
                [sideQ bytes], [sideQ length], 0);
    [GWMetaArchive compressPaths: @[ f ] toArchiveAt: zip error: NULL];
    ad = [readArchive(zip) objectForKey: @"__MACOSX/._dl.txt"];
    p = [[[GSAppleDouble alloc] initWithData: ad] autorelease];
    PASS_EQUAL([[p extendedAttributes] objectForKey: @"com.apple.quarantine"], sideQ,
               "MI-AR-27 the prefix is not doubled");

    /* extraction strips it into the plain xattr */
    GSAppleDouble *mk = [[[GSAppleDouble alloc] init] autorelease];
    [mk setXattr: sideQ forKey: @"com.apple.quarantine"];
    NSString *tar = [root stringByAppendingPathComponent: @"q.tar"];
    writeArchive(tar, NO, @[ @"dl.txt", @"._dl.txt" ], @[ body, [mk appleDoubleData] ]);
    NSString *dest = fresh(@"out-q");
    PASS([GWMetaArchive extractArchive: tar toDir: dest error: NULL], "MI-AR-28 extracts");
    NSString *g = [dest stringByAppendingPathComponent: @"dl.txt"];
    if (gs_xattr_supported([dest fileSystemRepresentation]) == 1)
      PASS_EQUAL(getx(g, @"user.com.apple.quarantine"), plainQ,
                 "MI-AR-28 the xattr holds the plain value, q/ stripped");
  }

  /* --- extracting onto a volume a Mac reads through ._ files ----------- */
  if (gs_xattr_supported([root fileSystemRepresentation]) == 1)
    {
      NSString *tar = [root stringByAppendingPathComponent: @"stick.tar"];
      writeArchive(tar, NO, @[ @"many.txt", @"._many.txt", @"d/", @"._d" ],
                   @[ body, manyAD, [NSNull null], dirAD ]);
      NSString *dest = fresh(@"out-stick");
      [GSFileMetadata setFilesystemTypeProbe: ^NSString *(NSString *path) {
        return [path hasPrefix: dest] ? @"exfat" : @"ext4";
      }];
      NSError *err = nil;
      PASS([GWMetaArchive extractArchive: tar toDir: dest error: &err],
           "MI-AR-29 tar extracts onto exFAT (%s)",
           err ? [[err description] UTF8String] : "ok");
      NSString *f = [dest stringByAppendingPathComponent: @"many.txt"];
      NSString *d = [dest stringByAppendingPathComponent: @"d"];
      PASS_EQUAL([NSData dataWithContentsOfFile:
                    [GSFileMetadata sidecarPathForFilePath: f]], manyAD,
                 "MI-AR-29 the file's companion stays its sidecar, byte for byte");
      PASS_EQUAL([NSData dataWithContentsOfFile:
                    [GSFileMetadata sidecarPathForFilePath: d]], dirAD,
                 "MI-AR-29 so does the folder's");
      PASS(getx(f, @"user.com.apple.FinderInfo") == nil
           && getx(d, @"user.com.apple.FinderInfo") == nil,
           "MI-AR-29 nothing becomes an attribute the Mac would not see");
      [GSFileMetadata setFilesystemTypeProbe: nil];
    }

  [fm removeFileAtPath: root handler: nil];
  [pool release];
  return 0;
}
