/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 */

/* On volumes a Mac reads but whose native attributes it does not see (FAT,
 * exFAT, SMB, NTFS), Mac OS X keeps Finder metadata in "._" files.  Saving
 * there must write the sidecar, and reading there must take what a Mac left
 * in it.  The filesystem type is injected so the tests run on any disk. */

#import <Foundation/Foundation.h>
#import "Testing.h"
#import "GSAppleDouble.h"
#import "GSFileMetadata.h"
#import "GWMetaXattr.h"
#include <unistd.h>
#include <string.h>

static NSString *gFsType = nil;

static NSString *
scratchDir(void)
{
  NSString *d = [NSTemporaryDirectory() stringByAppendingPathComponent:
    [NSString stringWithFormat: @"t_TransportPolicy-%d", (int)getpid()]];
  NSFileManager *fm = [NSFileManager defaultManager];
  [fm removeFileAtPath: d handler: nil];
  [fm createDirectoryAtPath: d withIntermediateDirectories: YES
                 attributes: nil error: NULL];
  return d;
}

static NSString *
freshFile(NSString *dir, NSString *name)
{
  NSString *p = [dir stringByAppendingPathComponent: name];
  [[NSFileManager defaultManager] removeFileAtPath: p handler: nil];
  [[NSFileManager defaultManager] removeFileAtPath:
    [GSFileMetadata sidecarPathForFilePath: p] handler: nil];
  [[@"data" dataUsingEncoding: NSUTF8StringEncoding] writeToFile: p
                                                      atomically: NO];
  [GSFileMetadata invalidateAllCachedMetadata];
  return p;
}

static int
appleXattrCount(NSString *path)
{
  gs_xattr_list_t *l = gs_xattr_list_for_path(GW_FSREP(path), "user.com.apple.");
  int n = l ? l->count : -1;
  gs_xattr_list_free(l);
  return n;
}

static BOOL
wants(const char *fstype)
{
  return gs_fs_type_wants_appledouble(fstype) == 1;
}

int main(void)
{
  NSAutoreleasePool *arp = [NSAutoreleasePool new];
  NSString *dir = scratchDir();
  char name[64];

  START_SET("filesystem type decides where metadata goes")
    PASS(wants("vfat") && wants("msdos") && wants("msdosfs")
         && wants("exfat") && wants("fusefs.exfat"),
         "FAT and exFAT (Linux, FreeBSD, OpenBSD names) take sidecars");
    PASS(wants("cifs") && wants("smb3") && wants("smb2") && wants("smbfs"),
         "SMB mounts take sidecars");
    PASS(wants("ntfs") && wants("ntfs3") && wants("fuseblk")
         && wants("NTFS") && wants("FAT32") && wants("exFAT"),
         "NTFS and the Windows volume names take sidecars");
    PASS(!wants("ext4") && !wants("xfs") && !wants("btrfs") && !wants("zfs")
         && !wants("ufs") && !wants("ffs") && !wants("tmpfs")
         && !wants("nfs") && !wants("fuse.sshfs") && !wants(""),
         "native Unix filesystems keep attributes");
    PASS(gs_fs_type_name_for_magic(0x4d44UL, NULL, name, sizeof(name)) == 0
         && strcmp(name, "msdos") == 0, "Linux FAT magic is msdos");
    PASS(gs_fs_type_name_for_magic(0x65735546UL, "fuseblk", name,
                                   sizeof(name)) == 0
         && strcmp(name, "fuseblk") == 0, "FUSE takes its mountinfo type");
    PASS(gs_fs_type_name_for_magic(0x65735546UL, NULL, name, sizeof(name)) == 0
         && strcmp(name, "fuse") == 0 && !wants(name),
         "FUSE without a mountinfo entry is plain fuse, kept native");
    PASS(gs_fs_type_name_for_magic(0x12345678UL, NULL, name, sizeof(name)) == 0
         && !wants(name),
         "a magic we do not list is named (%s) and kept native", name);
    PASS(gs_fs_type_name(GW_FSREP(dir), name, sizeof(name)) == 0
         && name[0] != '\0',
         "the real probe names the scratch filesystem (%s)", name);
    PASS(gs_fs_type_name("/nonexistent-t_TransportPolicy", name,
                         sizeof(name)) == -1,
         "a path that cannot be examined is an error, not a guess");
  END_SET("filesystem type decides where metadata goes")

  [GSFileMetadata setFilesystemTypeProbe: ^NSString *(NSString *p) {
    return gFsType;
  }];

  START_SET("the policy reports per path")
    gFsType = @"vfat";
    PASS([GSFileMetadata storesMetadataInAppleDoubleAtPath: dir] == 1, "vfat: 1");
    gFsType = @"ext4";
    PASS([GSFileMetadata storesMetadataInAppleDoubleAtPath: dir] == 0, "ext4: 0");
    gFsType = nil;
    PASS([GSFileMetadata storesMetadataInAppleDoubleAtPath: dir] == -1,
         "filesystem cannot be examined: -1");
  END_SET("the policy reports per path")

  START_SET("saving on a Mac-read volume writes the sidecar, not attributes")
    gFsType = @"cifs";
    NSString *f = freshFile(dir, @"smb.txt");
    GSFileMetadata *md = [[[GSFileMetadata alloc] init] autorelease];
    NSData *fork = [@"forkbytes" dataUsingEncoding: NSUTF8StringEncoding];
    NSError *err = nil;
    md.typeCode = 0x54455854; /* TEXT */
    md.finderComment = @"over smb";
    md.quarantine = @"0001;5a000000;Safari;";
    md.resourceFork = fork;
    [md setLabelNumber: GSFileLabelRed];
    PASS([md writeToFileAtPath: f error: &err], "write succeeds");
    PASS(appleXattrCount(f) == 0, "no com.apple attribute on the item");
    NSData *raw = [NSData dataWithContentsOfFile:
      [GSFileMetadata sidecarPathForFilePath: f]];
    GSAppleDouble *ad = raw ? [[[GSAppleDouble alloc] initWithData: raw]
                                autorelease] : nil;
    PASS(ad != nil, "a ._ sidecar was written");
    const uint8_t *b = [raw bytes];
    PASS([raw length] > 38 && b[29] == 9, "entry 9 is the first entry");
    PASS([[ad resourceFork] isEqual: fork], "fork in entry 2");
    NSData *q = [[ad extendedAttributes] objectForKey: @"com.apple.quarantine"];
    PASS(q != nil && memcmp([q bytes], "q/", 2) == 0,
         "quarantine in ATTR with the q/ prefix 10.6 needs");
    PASS([[ad extendedAttributes] objectForKey:
           @"com.apple.metadata:kMDItemFinderComment"] != nil,
         "comment in ATTR");
    PASS([[ad extendedAttributes] objectForKey:
           @"com.apple.metadata:_kMDItemUserTags"] != nil,
         "label tag in ATTR");

    /* A second save must not migrate the sidecar into attributes and
     * delete it, as it does on a native disk. */
    md.finderComment = @"again";
    PASS([md writeToFileAtPath: f error: &err]
         && [[NSFileManager defaultManager] fileExistsAtPath:
              [GSFileMetadata sidecarPathForFilePath: f]]
         && appleXattrCount(f) == 0,
         "a later save keeps the sidecar and still writes no attribute");
  END_SET("saving on a Mac-read volume writes the sidecar, not attributes")

  START_SET("a share that refuses ._ files")
    gFsType = @"smb3";
    NSString *f = freshFile(dir, @"vetoed.txt");
    NSString *sc = [GSFileMetadata sidecarPathForFilePath: f];
    [[NSFileManager defaultManager] createDirectoryAtPath: sc attributes: nil];
    GSFileMetadata *md = [[[GSFileMetadata alloc] init] autorelease];
    NSError *err = nil;
    md.finderComment = @"x";
    PASS(![md writeToFileAtPath: f error: &err]
         && [[err localizedDescription] rangeOfString:
               @"fruit:veto_appledouble"].location != NSNotFound,
         "the save fails and names the Samba option to change");
    PASS(appleXattrCount(f) == 0, "no attribute was written instead");
    [[NSFileManager defaultManager] removeFileAtPath: sc handler: nil];
  END_SET("a share that refuses ._ files")

  START_SET("saving on a native disk is unchanged")
    gFsType = @"ext4";
    NSString *f = freshFile(dir, @"native.txt");
    GSFileMetadata *md = [[[GSFileMetadata alloc] init] autorelease];
    md.typeCode = 0x54455854;
    if (gs_xattr_supported(GW_FSREP(f)) == 1)
      {
        PASS([md writeToFileAtPath: f error: NULL]
             && appleXattrCount(f) > 0
             && ![[NSFileManager defaultManager] fileExistsAtPath:
                   [GSFileMetadata sidecarPathForFilePath: f]],
             "ext4: attributes, no sidecar");
      }
  END_SET("saving on a native disk is unchanged")

  START_SET("an unlisted filesystem keeps attributes")
    gFsType = @"0x12345678";
    NSString *f = freshFile(dir, @"exotic.txt");
    GSFileMetadata *md = [[[GSFileMetadata alloc] init] autorelease];
    md.typeCode = 0x54455854;
    if (gs_xattr_supported(GW_FSREP(f)) == 1)
      {
        PASS([md writeToFileAtPath: f error: NULL] && appleXattrCount(f) > 0,
             "unlisted type: saved as attributes like before");
      }
  END_SET("an unlisted filesystem keeps attributes")

  START_SET("a filesystem that cannot be examined fails the save")
    gFsType = nil;
    NSString *f = freshFile(dir, @"unknown.txt");
    GSFileMetadata *md = [[[GSFileMetadata alloc] init] autorelease];
    NSError *err = nil;
    md.typeCode = 0x54455854;
    PASS(![md writeToFileAtPath: f error: &err] && err != nil,
         "write refuses with an error");
    PASS(appleXattrCount(f) == 0 && ![[NSFileManager defaultManager]
           fileExistsAtPath: [GSFileMetadata sidecarPathForFilePath: f]],
         "and leaves nothing behind");
  END_SET("a filesystem that cannot be examined fails the save")

  START_SET("reading on a Mac-read volume merges the sidecar")
    NSString *f = freshFile(dir, @"fat.txt");
    /* A Mac wrote the sidecar; a Linux tool left an older attribute. */
    gFsType = @"ext4";
    GSFileMetadata *onMount = [[[GSFileMetadata alloc] init] autorelease];
    onMount.finderComment = @"stale comment from Linux";
    onMount.quarantine = @"0001;1;old;";
    BOOL haveXattrs = (gs_xattr_supported(GW_FSREP(f)) == 1)
      && [onMount writeToFileAtPath: f error: NULL];
    GSFileMetadata *mac = [[[GSFileMetadata alloc] init] autorelease];
    mac.finderComment = @"comment from the Mac";
    [mac setLabelNumber: GSFileLabelGreen];
    PASS([mac writeSidecarToFileAtPath: f error: NULL], "Mac sidecar staged");
    [GSFileMetadata invalidateAllCachedMetadata];

    gFsType = @"msdos";
    GSFileMetadata *got = [GSFileMetadata metadataForFileAtPath: f];
    PASS([got.finderComment isEqual: @"comment from the Mac"],
         "the sidecar's comment wins over a stale attribute");
    PASS([got labelNumber] == GSFileLabelGreen, "label from the sidecar");
    if (haveXattrs)
      {
        PASS([got.quarantine isEqual: @"0001;1;old;"],
             "what only the attribute has still shows");
      }
  END_SET("reading on a Mac-read volume merges the sidecar")

  START_SET("reading where the filesystem cannot be examined gives nothing")
    NSString *f = freshFile(dir, @"unk.txt");
    GSFileMetadata *mac = [[[GSFileMetadata alloc] init] autorelease];
    mac.finderComment = @"x";
    [mac writeSidecarToFileAtPath: f error: NULL];
    [GSFileMetadata invalidateAllCachedMetadata];
    gFsType = nil;
    PASS([GSFileMetadata metadataForFileAtPath: f forceSidecar: NO] == nil,
         "no guess when the filesystem cannot be told");
  END_SET("reading where the filesystem cannot be examined gives nothing")

  [GSFileMetadata setFilesystemTypeProbe: nil];
  [[NSFileManager defaultManager] removeFileAtPath: dir handler: nil];
  [arp release];
  return 0;
}
