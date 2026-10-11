/* t_MetadataCopier.m - ObjectTesting coverage for carrying extended
 * attributes and AppleDouble sidecars through copy, duplicate and a move
 * across filesystems.  Foundation only, headless.
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */
#import <Foundation/Foundation.h>
#import "Testing.h"
#import "GWMetadataCopier.h"
#import "GSAppleDouble.h"
#import "GWMetaXattr.h"

#include <sys/stat.h>
#include <unistd.h>
#include <errno.h>

/* A mover that behaves as if source and destination were on different
 * filesystems, as one machine rarely has two to hand. */
@interface CrossFSCopier : GWMetadataCopier
@end
@implementation CrossFSCopier
- (BOOL)isRenameFromPath:(NSString *)s toPath:(NSString *)d { return NO; }
@end

static NSFileManager *fm;
static NSString *root;

static NSData *
D(const char *s, NSUInteger n)
{
  return [NSData dataWithBytes: s length: n];
}

static NSString *
mk(NSString *name, NSString *content)
{
  NSString *p = [root stringByAppendingPathComponent: name];
  [fm createFileAtPath: p contents: [content dataUsingEncoding: NSUTF8StringEncoding]
            attributes: nil];
  return p;
}

static BOOL
setx(NSString *path, NSString *name, NSData *v)
{
  return gs_setxattr([path fileSystemRepresentation], [name UTF8String],
                     [v length] ? [v bytes] : "", [v length], 0) == 0;
}

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

static GSAppleDouble *
sidecarOf(NSString *path)
{
  NSData *d = [NSData dataWithContentsOfFile:
    [GWMetadataCopier sidecarPathForPath: path]];
  return d ? [[[GSAppleDouble alloc] initWithData: d] autorelease] : nil;
}

int
main(void)
{
  NSAutoreleasePool *arp = [NSAutoreleasePool new];
  fm = [NSFileManager defaultManager];
  root = [[NSTemporaryDirectory() stringByAppendingPathComponent:
    [NSString stringWithFormat: @"t_mdcopier_%d", (int)getpid()]] retain];
  [fm removeFileAtPath: root handler: nil];
  [fm createDirectoryAtPath: root attributes: nil];

  BOOL haveXattr = gs_xattr_supported([root fileSystemRepresentation]) == 1;
  GWMetadataCopier *copier = [[GWMetadataCopier new] autorelease];
  NSData *quarantine = D("0083;5f1e2a3b;Safari;", 22);
  NSMutableData *finfo = [NSMutableData dataWithLength: 32];
  memcpy([finfo mutableBytes], "TEXTttxt", 8);
  NSData *rsrc = D("\xca\xfe\xba\xbe", 4);
  NSData *blob = D("\x00\xff\x01\x00", 4);
  NSError *err = nil;

  if (haveXattr)
    {
      /* MI-PRS-11 */
      NSString *src = mk(@"a.txt", @"data");
      NSString *dst = [root stringByAppendingPathComponent: @"a_copy.txt"];
      setx(src, @"user.com.apple.quarantine", quarantine);
      setx(src, @"user.com.apple.FinderInfo", finfo);
      setx(src, @"user.com.apple.ResourceFork", rsrc);
      setx(src, @"user.org.example.blob", blob);
      setx(src, @"user.org.example.empty", [NSData data]);
      setx(src, @"user.com.apple.metadata:_kMDItemUserTags", D("bplist00", 8));

      PASS([copier copyItemAtPath: src toPath: dst handler: nil
                    metadataError: &err] && err == nil,
           "MI-PRS-11 copy of a file with attributes succeeds");
      PASS([getx(dst, @"user.com.apple.quarantine") isEqual: quarantine],
           "MI-PRS-11 com.apple.quarantine is carried by a copy");
      PASS([getx(dst, @"user.com.apple.ResourceFork") isEqual: rsrc]
           && [getx(dst, @"user.com.apple.FinderInfo") isEqual: finfo],
           "MI-PRS-11 resource fork and Finder info are carried by a copy");
      PASS([getx(dst, @"user.org.example.blob") isEqual: blob],
           "MI-PRS-11 an attribute of another program is carried byte for byte");
      NSData *emp = getx(dst, @"user.org.example.empty");
      PASS(emp != nil && [emp length] == 0,
           "MI-PRS-11 an attribute with an empty value is carried");
      PASS([getx(dst, @"user.com.apple.metadata:_kMDItemUserTags")
            isEqual: D("bplist00", 8)],
           "MI-PRS-11 tags (name with colon) are carried by a copy");
      PASS([fm fileExistsAtPath: [GWMetadataCopier sidecarPathForPath: dst]] == NO,
           "MI-PRS-11 no sidecar appears where attributes work");

      /* MI-PRS-12: duplicate is a copy inside one folder. */
      NSString *dup = [root stringByAppendingPathComponent: @"a_dup.txt"];
      err = nil;
      PASS([copier copyItemAtPath: src toPath: dup handler: nil
                    metadataError: &err]
           && [getx(dup, @"user.org.example.blob") isEqual: blob],
           "MI-PRS-12 duplicate carries all attributes");

      /* MI-PRS-13: a folder tree. */
      NSString *tree = [root stringByAppendingPathComponent: @"tree"];
      [fm createDirectoryAtPath: tree attributes: nil];
      [fm createDirectoryAtPath: [tree stringByAppendingPathComponent: @"sub"]
                     attributes: nil];
      NSString *deep = [tree stringByAppendingPathComponent: @"sub/f.txt"];
      [fm createFileAtPath: deep contents: nil attributes: nil];
      setx(deep, @"user.com.apple.quarantine", quarantine);
      setx([tree stringByAppendingPathComponent: @"sub"],
           @"user.org.example.dir", blob);
      setx(tree, @"user.org.example.top", blob);
      NSString *tcopy = [root stringByAppendingPathComponent: @"tree_copy"];
      err = nil;
      PASS([copier copyItemAtPath: tree toPath: tcopy handler: nil
                    metadataError: &err] && err == nil,
           "MI-PRS-13 copy of a folder tree succeeds");
      PASS([getx([tcopy stringByAppendingPathComponent: @"sub/f.txt"],
                 @"user.com.apple.quarantine") isEqual: quarantine],
           "MI-PRS-13 a file deep in a copied folder keeps its attributes");
      PASS([getx([tcopy stringByAppendingPathComponent: @"sub"],
                 @"user.org.example.dir") isEqual: blob]
           && [getx(tcopy, @"user.org.example.top") isEqual: blob],
           "MI-PRS-13 folders keep their own attributes");

      /* MI-PRS-14: read-only file. */
      NSString *ro = mk(@"ro.txt", @"x");
      setx(ro, @"user.org.example.blob", blob);
      chmod([ro fileSystemRepresentation], 0444);
      NSString *roCopy = [root stringByAppendingPathComponent: @"ro_copy.txt"];
      err = nil;
      PASS([copier copyItemAtPath: ro toPath: roCopy handler: nil
                    metadataError: &err] && err == nil
           && [getx(roCopy, @"user.org.example.blob") isEqual: blob],
           "MI-PRS-14 attributes reach a read-only copy");
      struct stat st;
      stat([roCopy fileSystemRepresentation], &st);
      PASS((st.st_mode & 0777) == 0444,
           "MI-PRS-14 the copy stays read-only");

      /* MI-PRS-15: symlink and file without metadata. */
      NSString *link = [root stringByAppendingPathComponent: @"link"];
      symlink("a.txt", [link fileSystemRepresentation]);
      err = nil;
      PASS([copier copyMetadataFromPath: link
                                 toPath: [root stringByAppendingPathComponent: @"a_copy.txt"]
                                  error: &err] && err == nil,
           "MI-PRS-15 a symbolic link carries no metadata and is skipped");
      NSString *plain = mk(@"plain.txt", @"p");
      NSString *plainCopy = [root stringByAppendingPathComponent: @"plain2.txt"];
      PASS([copier copyItemAtPath: plain toPath: plainCopy handler: nil
                    metadataError: &err]
           && ![fm fileExistsAtPath: [GWMetadataCopier sidecarPathForPath: plainCopy]],
           "MI-PRS-15 a file without metadata gets no sidecar");

      /* MI-PRS-16: cross-filesystem move. */
      CrossFSCopier *xfs = [[CrossFSCopier new] autorelease];
      NSString *msrc = mk(@"m.txt", @"move me");
      setx(msrc, @"user.com.apple.quarantine", quarantine);
      setx(msrc, @"user.org.example.blob", blob);
      NSString *mdst = [root stringByAppendingPathComponent: @"m_moved.txt"];
      err = nil;
      PASS([xfs moveItemAtPath: msrc toPath: mdst handler: nil
                 metadataError: &err] && err == nil,
           "MI-PRS-16 move across filesystems succeeds");
      PASS([getx(mdst, @"user.com.apple.quarantine") isEqual: quarantine]
           && [getx(mdst, @"user.org.example.blob") isEqual: blob],
           "MI-PRS-16 a move across filesystems carries all attributes");
      PASS(![fm fileExistsAtPath: msrc],
           "MI-PRS-16 the source is gone after a complete move");

      /* MI-PRS-17: a move that cannot carry the metadata keeps the source. */
      NSString *fsrc = mk(@"keep.txt", @"keep");
      setx(fsrc, @"user.org.example.blob", blob);
      NSString *fdst = [root stringByAppendingPathComponent: @"keep_moved.txt"];
      GWMetadataCopier *unsure = [[CrossFSCopier new] autorelease];
      unsure.xattrSupportProbe = ^int(NSString *p) { return -1; };
      err = nil;
      PASS(![unsure moveItemAtPath: fsrc toPath: fdst handler: nil
                     metadataError: &err] && err != nil,
           "MI-PRS-17 a move whose metadata cannot be carried fails with an error");
      PASS([fm fileExistsAtPath: fsrc],
           "MI-PRS-17 and leaves the source in place");

      /* MI-PRS-18: rename within a filesystem. */
      NSString *rsrcPath = mk(@"r.txt", @"r");
      setx(rsrcPath, @"user.org.example.blob", blob);
      NSString *rdst = [root stringByAppendingPathComponent: @"r2.txt"];
      PASS([copier moveItemAtPath: rsrcPath toPath: rdst handler: nil
                    metadataError: &err]
           && [getx(rdst, @"user.org.example.blob") isEqual: blob],
           "MI-PRS-18 a rename keeps the attributes");
    }

  /* --- destination without extended attributes: everything in a sidecar */
  GWMetadataCopier *noX = [[GWMetadataCopier new] autorelease];
  noX.xattrSupportProbe = ^int(NSString *p) { return 0; };

  if (haveXattr)
    {
      /* MI-PRS-19 */
      NSString *src = mk(@"s.txt", @"s");
      setx(src, @"user.com.apple.quarantine", quarantine);
      setx(src, @"user.com.apple.FinderInfo", finfo);
      setx(src, @"user.com.apple.ResourceFork", rsrc);
      setx(src, @"user.org.example.blob", blob);
      setx(src, @"user.com.apple.metadata:_kMDItemUserTags", D("bplist00", 8));
      NSString *dst = [root stringByAppendingPathComponent: @"s_fat.txt"];
      err = nil;
      PASS([noX copyItemAtPath: src toPath: dst handler: nil metadataError: &err]
           && err == nil,
           "MI-PRS-19 copy onto a filesystem without attributes succeeds");
      GSAppleDouble *ad = sidecarOf(dst);
      PASS(ad != nil, "MI-PRS-19 a ._ sidecar is written beside the copy");
      PASS([[ad finderInfo] isEqual: finfo] && [[ad resourceFork] isEqual: rsrc],
           "MI-PRS-19 Finder info and resource fork go into entries 9 and 2");
      NSDictionary *x = [ad extendedAttributes];
      PASS([[x objectForKey: @"com.apple.quarantine"] isEqual: quarantine]
           && [[x objectForKey: @"org.example.blob"] isEqual: blob]
           && [[x objectForKey: @"com.apple.metadata:_kMDItemUserTags"]
               isEqual: D("bplist00", 8)],
           "MI-PRS-19 every other attribute goes into the sidecar under its Mac name");
      PASS([x count] == 3,
           "MI-PRS-19 the sidecar holds exactly the attributes the source had");
      PASS(getx(dst, @"user.com.apple.quarantine") == nil,
           "MI-PRS-19 nothing was also written as an attribute");
    }

  {
    /* MI-PRS-20: source metadata lives in a sidecar. */
    NSString *src = mk(@"side.txt", @"s");
    GSAppleDouble *seed = [[[GSAppleDouble alloc] init] autorelease];
    [seed setFinderInfo: finfo];
    [seed setEntry: 0x9001 data: D("tags-in-foreign-entry", 21)];
    [seed setXattr: D("keep-me", 7) forKey: @"org.example.unknown"];
    NSData *seedData = [seed appleDoubleData];
    [seedData writeToFile: [GWMetadataCopier sidecarPathForPath: src]
               atomically: NO];
    NSString *dst = [root stringByAppendingPathComponent: @"side_fat.txt"];
    err = nil;
    PASS([noX copyItemAtPath: src toPath: dst handler: nil metadataError: &err]
         && err == nil,
         "MI-PRS-20 copy of a file whose metadata is in a sidecar succeeds");
    NSData *got = [NSData dataWithContentsOfFile:
      [GWMetadataCopier sidecarPathForPath: dst]];
    PASS(got != nil && [got isEqual: seedData],
         "MI-PRS-20 the sidecar is carried byte for byte to a destination without attributes");

    NSString *dst2 = [root stringByAppendingPathComponent: @"side_ext.txt"];
    PASS([copier copyItemAtPath: src toPath: dst2 handler: nil metadataError: &err]
         && [[NSData dataWithContentsOfFile:
               [GWMetadataCopier sidecarPathForPath: dst2]] isEqual: seedData],
         "MI-PRS-20 the sidecar is carried to a destination with attributes too");

    /* MI-PRS-21: source with both a sidecar and attributes. */
    if (haveXattr)
      {
        setx(src, @"user.com.apple.quarantine", quarantine);
        NSString *dst3 = [root stringByAppendingPathComponent: @"both_fat.txt"];
        err = nil;
        PASS([noX copyItemAtPath: src toPath: dst3 handler: nil
                   metadataError: &err] && err == nil,
             "MI-PRS-21 copy with attributes and a sidecar succeeds");
        GSAppleDouble *ad = sidecarOf(dst3);
        PASS([[ad dataForEntry: 0x9001] isEqual: D("tags-in-foreign-entry", 21)]
             && [[[ad extendedAttributes] objectForKey: @"org.example.unknown"]
                 isEqual: D("keep-me", 7)],
             "MI-PRS-21 entries and attributes only the sidecar had are kept");
        PASS([[[ad extendedAttributes] objectForKey: @"com.apple.quarantine"]
              isEqual: quarantine],
             "MI-PRS-21 the attributes of the source are merged into it");
      }
  }

  if (haveXattr)
    {
      /* MI-PRS-23 */
      NSString *src = mk(@"big.txt", @"b");
      setx(src, @"user.com.apple.quarantine", quarantine);
      setx(src, @"user.org.example.big", blob);
      setx(src, @"user.com.apple.ResourceFork", rsrc);
      NSString *dst = [root stringByAppendingPathComponent: @"big_copy.txt"];
      GWMetadataCopier *tooBig = [[GWMetadataCopier new] autorelease];
      int (^real)(NSString *, NSString *, NSData *) = [tooBig.xattrSetter retain];
      /* Fail the third store, whatever the attribute order, so that two
       * attributes are always on the item when the failure comes. */
      __block int calls = 0;
      tooBig.xattrSetter = ^int(NSString *p, NSString *n, NSData *v) {
        return (++calls == 3) ? E2BIG : real(p, n, v);
      };
      err = nil;
      PASS([tooBig copyItemAtPath: src toPath: dst handler: nil metadataError: &err]
           && err == nil,
           "MI-PRS-23 an attribute that does not fit does not fail the copy");
      GSAppleDouble *ad = sidecarOf(dst);
      PASS(calls == 3, "MI-PRS-23 the failure came after two attributes were stored");
      PASS([[[ad extendedAttributes] objectForKey: @"org.example.big"] isEqual: blob]
           && [[[ad extendedAttributes] objectForKey: @"com.apple.quarantine"]
               isEqual: quarantine] && [[ad resourceFork] isEqual: rsrc],
           "MI-PRS-23 then all metadata of the item is in the sidecar");
      PASS(getx(dst, @"user.com.apple.quarantine") == nil
           && getx(dst, @"user.com.apple.ResourceFork") == nil,
           "MI-PRS-23 and no partial set of attributes is left on the item");

      NSString *dst2 = [root stringByAppendingPathComponent: @"big_copy2.txt"];
      tooBig.xattrSetter = ^int(NSString *p, NSString *n, NSData *v) {
        return EACCES;
      };
      err = nil;
      [tooBig copyItemAtPath: src toPath: dst2 handler: nil metadataError: &err];
      PASS(err != nil && ![fm fileExistsAtPath:
                           [GWMetadataCopier sidecarPathForPath: dst2]],
           "MI-PRS-23 any other error still fails hard, without a sidecar");
      [real release];
    }

  /* MI-PRS-22: the listing the copier is built on. */
  {
    NSString *bare = mk(@"bare.txt", @"b");
    gs_xattr_list_t *l = gs_xattr_list_for_path([bare fileSystemRepresentation],
                                                "user.");
    PASS(l != NULL && l->count == 0,
         "MI-PRS-22 a file without attributes lists as empty, not as a failure");
    gs_xattr_list_free(l);
    if (haveXattr)
      {
        setx(bare, @"user.org.example.empty", [NSData data]);
        setx(bare, @"user.org.example.blob", blob);
        l = gs_xattr_list_for_path([bare fileSystemRepresentation], "user.");
        PASS(l != NULL && l->count == 2,
             "MI-PRS-22 every user attribute is listed, empty values included");
        gs_xattr_list_free(l);
      }
    l = gs_xattr_list_for_path([[root stringByAppendingPathComponent: @"nope"]
                                 fileSystemRepresentation], "user.");
    PASS(l == NULL, "MI-PRS-22 a missing file is a failure, not an empty list");
  }

  [fm removeFileAtPath: root handler: nil];
  [arp release];
  return 0;
}
