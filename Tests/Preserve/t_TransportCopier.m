/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 */

/* Copies and moves onto volumes a Mac reads through "._" files (SMB, FAT,
 * exFAT, NTFS) must leave the metadata in sidecars even when the Linux mount
 * would accept attributes: the Mac never sees those.  The filesystem type of
 * the destination is injected, so the scratch disk plays the stick. */

#import <Foundation/Foundation.h>
#import "Testing.h"
#import "GWMetadataCopier.h"
#import "GSAppleDouble.h"
#import "GSFileMetadata.h"
#import "GWMetaXattr.h"
#include <unistd.h>

@interface CrossFSCopier : GWMetadataCopier
@end
@implementation CrossFSCopier
- (BOOL)isRenameFromPath:(NSString *)s toPath:(NSString *)d { return NO; }
@end

static NSFileManager *fm;
static NSString *root;
static NSString *stick;
static NSString *stickType = @"vfat";

static NSData *
D(const char *s, NSUInteger n)
{
  return [NSData dataWithBytes: s length: n];
}

static NSString *
mk(NSString *dir, NSString *name)
{
  NSString *p = [dir stringByAppendingPathComponent: name];
  [fm createFileAtPath: p contents: D("data", 4) attributes: nil];
  return p;
}

static void
setx(NSString *path, NSString *name, NSData *v)
{
  gs_setxattr(GW_FSREP(path), [name UTF8String],
              [v length] ? [v bytes] : "", [v length], 0);
}

static int
userXattrCount(NSString *path)
{
  gs_xattr_list_t *l = gs_xattr_list_for_path(GW_FSREP(path), "user.");
  int n = l ? l->count : -1;
  gs_xattr_list_free(l);
  return n;
}

static NSData *
fixture(NSString *name)
{
  return [NSData dataWithContentsOfFile: [[[fm currentDirectoryPath]
    stringByAppendingPathComponent:
      @"../GWMetadata/interop/fixtures/finder106/E35-nonhfs-fat32"]
    stringByAppendingPathComponent: name]];
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
  NSData *quarantine = D("0083;5f1e2a3b;Safari;", 21);
  NSMutableData *finfo = [NSMutableData dataWithLength: 32];
  NSData *rsrc = D("\xca\xfe\xba\xbe", 4);
  NSData *blob = D("\x00\xff\x01\x00", 4);
  NSData *tags = D("bplist00", 8);
  NSError *err;

  fm = [NSFileManager defaultManager];
  root = [[NSTemporaryDirectory() stringByAppendingPathComponent:
    [NSString stringWithFormat: @"t_transport_%d", (int)getpid()]] retain];
  stick = [[root stringByAppendingPathComponent: @"stick"] retain];
  [fm removeFileAtPath: root handler: nil];
  [fm createDirectoryAtPath: stick withIntermediateDirectories: YES
                 attributes: nil error: NULL];
  memcpy([finfo mutableBytes], "TEXTttxt", 8);

  /* Everything below "stick" is on the Mac-read volume. */
  [GSFileMetadata setFilesystemTypeProbe: ^NSString *(NSString *p) {
    return [p hasPrefix: stick] ? stickType : @"ext4";
  }];

  if (gs_xattr_supported(GW_FSREP(root)) != 1)
    {
      /* The point is attributes that the mount would take; without them
       * every copy takes the sidecar path already (t_MetadataCopier). */
      PASS(YES, "scratch disk has no attributes; transport cases skipped");
      [arp release];
      return 0;
    }

  GWMetadataCopier *copier = [[GWMetadataCopier new] autorelease];

  START_SET("copy onto a Mac-read volume")
    NSArray *types = [NSArray arrayWithObjects:
      @"vfat", @"exfat", @"cifs", @"smb3", @"ntfs3", @"fuseblk", nil];
    for (NSString *t in types)
      {
        stickType = t;
        NSString *src = mk(root, [t stringByAppendingString: @".txt"]);
        NSString *dst = [stick stringByAppendingPathComponent: [src lastPathComponent]];
        setx(src, @"user.com.apple.quarantine", quarantine);
        setx(src, @"user.com.apple.FinderInfo", finfo);
        setx(src, @"user.com.apple.ResourceFork", rsrc);
        setx(src, @"user.org.example.blob", blob);
        setx(src, @"user.com.apple.metadata:_kMDItemUserTags", tags);
        err = nil;
        PASS([copier copyItemAtPath: src toPath: dst handler: nil
                      metadataError: &err] && err == nil,
             "%s: copy succeeds", [t UTF8String]);
        PASS(userXattrCount(dst) == 0,
             "%s: no attribute on the copy", [t UTF8String]);
        GSAppleDouble *ad = sidecarOf(dst);
        NSDictionary *x = [ad extendedAttributes];
        PASS([[ad finderInfo] isEqual: finfo] && [[ad resourceFork] isEqual: rsrc],
             "%s: Finder info and fork in entries 9 and 2", [t UTF8String]);
        PASS([[x objectForKey: @"org.example.blob"] isEqual: blob]
             && [[x objectForKey: @"com.apple.metadata:_kMDItemUserTags"]
                  isEqual: tags],
             "%s: other attributes in ATTR under their Mac names", [t UTF8String]);
        PASS([x objectForKey: @"com.apple.quarantine"] == nil,
             "%s: the quarantine stays behind, as with Finder [O: E35]",
             [t UTF8String]);
        NSData *raw = [NSData dataWithContentsOfFile:
          [GWMetadataCopier sidecarPathForPath: dst]];
        const uint8_t *b = [raw bytes];
        PASS([raw length] == 3810 + [rsrc length] && b[36] == 0x0e && b[37] == 0xb0,
             "%s: the kernel's padded layout [O: E35]", [t UTF8String]);
      }
  END_SET("copy onto a Mac-read volume")

  START_SET("a sidecar of the source is merged, not duplicated as attributes")
    stickType = @"cifs";
    NSString *src = mk(root, @"both.txt");
    NSString *dst = [stick stringByAppendingPathComponent: @"both.txt"];
    GSAppleDouble *seed = [[[GSAppleDouble alloc] init] autorelease];
    [seed setXattr: D("old", 3) forKey: @"org.example.onlyinsidecar"];
    [[seed appleDoubleData] writeToFile:
      [GWMetadataCopier sidecarPathForPath: src] atomically: NO];
    setx(src, @"user.org.example.blob", blob);
    err = nil;
    PASS([copier copyItemAtPath: src toPath: dst handler: nil
                  metadataError: &err] && err == nil, "copy succeeds");
    NSDictionary *x = [sidecarOf(dst) extendedAttributes];
    PASS([[x objectForKey: @"org.example.onlyinsidecar"] isEqual: D("old", 3)]
         && [[x objectForKey: @"org.example.blob"] isEqual: blob]
         && userXattrCount(dst) == 0,
         "attribute and sidecar content end up in one sidecar");
  END_SET("a sidecar of the source is merged, not duplicated as attributes")

  START_SET("a quarantine alone makes no sidecar")
    stickType = @"vfat";
    NSString *src = mk(root, @"qonly.txt");
    setx(src, @"user.com.apple.quarantine", quarantine);
    NSString *dst = [stick stringByAppendingPathComponent: @"qonly.txt"];
    err = nil;
    PASS([copier copyItemAtPath: src toPath: dst handler: nil metadataError: &err]
         && err == nil && sidecarOf(dst) == nil && userXattrCount(dst) == 0,
         "nothing is written for it [O: E35, E16]");
  END_SET("a quarantine alone makes no sidecar")

  START_SET("a Mac-made sidecar travels byte for byte")
    stickType = @"msdos";
    NSString *src = mk(root, @"macmade.txt");
    NSString *dst = [stick stringByAppendingPathComponent: @"macmade.txt"];
    NSData *padded = fixture(@"fat-._b.txt");
    [padded writeToFile: [GWMetadataCopier sidecarPathForPath: src] atomically: NO];
    PASS([copier copyItemAtPath: src toPath: dst handler: nil metadataError: &err],
         "copy succeeds");
    PASS([[NSData dataWithContentsOfFile:
            [GWMetadataCopier sidecarPathForPath: dst]] isEqual: padded],
         "the sidecar is the same bytes on the stick");
  END_SET("a Mac-made sidecar travels byte for byte")

  START_SET("folder copy onto a Mac-read volume")
    stickType = @"exfat";
    NSString *folder = [root stringByAppendingPathComponent: @"Folder"];
    [fm createDirectoryAtPath: folder attributes: nil];
    NSString *inner = mk(folder, @"inner.txt");
    setx(folder, @"user.com.apple.FinderInfo", finfo);
    setx(inner, @"user.com.apple.metadata:_kMDItemUserTags", tags);
    NSString *dst = [stick stringByAppendingPathComponent: @"Folder"];
    PASS([copier copyItemAtPath: folder toPath: dst handler: nil
                  metadataError: &err], "copy succeeds");
    PASS([[sidecarOf(dst) finderInfo] isEqual: finfo]
         && userXattrCount(dst) == 0, "the folder's own sidecar sits beside it");
    NSString *dinner = [dst stringByAppendingPathComponent: @"inner.txt"];
    PASS([[[sidecarOf(dinner) extendedAttributes]
            objectForKey: @"com.apple.metadata:_kMDItemUserTags"] isEqual: tags]
         && userXattrCount(dinner) == 0, "every item inside gets one too");
  END_SET("folder copy onto a Mac-read volume")

  START_SET(".DS_Store on a Mac-read volume")
    stickType = @"vfat";
    NSString *src = mk(root, @"commented.txt");
    GSFileMetadata *md = [[[GSFileMetadata alloc] init] autorelease];
    md.finderComment = @"note";
    [md writeToFileAtPath: src error: NULL];
    [GSFileMetadata invalidateAllCachedMetadata];
    NSString *dst = [stick stringByAppendingPathComponent: @"commented.txt"];
    err = nil;
    PASS([copier copyItemAtPath: src toPath: dst handler: nil metadataError: &err]
         && err == nil, "copy succeeds");
    PASS([fm fileExistsAtPath: [stick stringByAppendingPathComponent: @".DS_Store"]],
         "the comment record goes into the stick's .DS_Store");
    PASS_EQUAL([NSData dataWithContentsOfFile:
                  [stick stringByAppendingPathComponent: @"._.DS_Store"]],
               fixture(@"fat-lf.._.DS_Store.bin"),
               "the store gets the invisible ._.DS_Store a Mac writes [O: E35]");
    PASS(userXattrCount([stick stringByAppendingPathComponent: @".DS_Store"]) == 0,
         "and no attribute");
  END_SET(".DS_Store on a Mac-read volume")

  START_SET("move onto a Mac-read volume")
    stickType = @"smbfs";
    NSString *src = mk(root, @"mv.txt");
    setx(src, @"user.com.apple.FinderInfo", finfo);
    NSString *dst = [stick stringByAppendingPathComponent: @"mv.txt"];
    GWMetadataCopier *mover = [[CrossFSCopier new] autorelease];
    err = nil;
    PASS([mover moveItemAtPath: src toPath: dst handler: nil metadataError: &err]
         && err == nil && ![fm fileExistsAtPath: src], "move completes");
    PASS([[sidecarOf(dst) finderInfo] isEqual: finfo] && userXattrCount(dst) == 0,
         "the metadata arrived in the sidecar");
  END_SET("move onto a Mac-read volume")

  START_SET("destination filesystem cannot be examined")
    stickType = nil;
    NSString *src = mk(root, @"unk.txt");
    setx(src, @"user.com.apple.FinderInfo", finfo);
    NSString *dst = [stick stringByAppendingPathComponent: @"unk.txt"];
    err = nil;
    [copier copyItemAtPath: src toPath: dst handler: nil metadataError: &err];
    PASS(err != nil && userXattrCount(dst) == 0 && sidecarOf(dst) == nil,
         "the copy reports the metadata as not carried and guesses nothing");
  END_SET("destination filesystem cannot be examined")

  START_SET("unlisted destination filesystem keeps attributes")
    stickType = @"0x12345678";
    NSString *src = mk(root, @"exotic.txt");
    setx(src, @"user.com.apple.FinderInfo", finfo);
    NSString *dst = [stick stringByAppendingPathComponent: @"exotic.txt"];
    err = nil;
    PASS([copier copyItemAtPath: src toPath: dst handler: nil metadataError: &err]
         && err == nil && userXattrCount(dst) == 1 && sidecarOf(dst) == nil,
         "a type we do not list is copied as before: attribute, no sidecar");
  END_SET("unlisted destination filesystem keeps attributes")

  START_SET("a share that refuses ._ files")
    stickType = @"cifs";
    NSString *src = mk(root, @"vetoed.txt");
    setx(src, @"user.com.apple.FinderInfo", finfo);
    NSString *dst = [stick stringByAppendingPathComponent: @"vetoed.txt"];
    /* Stands in for Samba's veto: the sidecar cannot be created. */
    [fm createDirectoryAtPath: [GWMetadataCopier sidecarPathForPath: dst]
                   attributes: nil];
    err = nil;
    [copier copyItemAtPath: src toPath: dst handler: nil metadataError: &err];
    PASS(err != nil && [[err localizedDescription]
           rangeOfString: @"fruit:veto_appledouble"].location != NSNotFound,
         "the copy fails and names the Samba option to change");
    PASS(userXattrCount(dst) == 0, "no attribute was written instead");
  END_SET("a share that refuses ._ files")

  START_SET("native destination is unchanged")
    NSString *src = mk(root, @"nat.txt");
    setx(src, @"user.com.apple.FinderInfo", finfo);
    NSString *dst = [root stringByAppendingPathComponent: @"nat_copy.txt"];
    PASS([copier copyItemAtPath: src toPath: dst handler: nil metadataError: &err]
         && userXattrCount(dst) == 1 && sidecarOf(dst) == nil,
         "ext4: attribute, no sidecar");
  END_SET("native destination is unchanged")

  [GSFileMetadata setFilesystemTypeProbe: nil];
  [fm removeFileAtPath: root handler: nil];
  [arp release];
  return 0;
}
