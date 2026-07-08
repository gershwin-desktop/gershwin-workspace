/* GWVolumeID.m
 *
 * Stable volume identifier implementation.
 *
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-2.0-or-later
 */

#import "GWVolumeID.h"
#ifdef __linux__
#import <sys/statfs.h>
#import <mntent.h>       /* getmntent / setmntent — portable mount table */
#ifndef _PATH_MOUNTED
#define _PATH_MOUNTED "/etc/mtab"
#endif
#else
/* BSDs and macOS: struct statfs via <sys/param.h> + <sys/mount.h>;
 * getmntinfo() enumerates the mount table. */
#import <sys/param.h>
#import <sys/mount.h>
#endif
#import <sys/stat.h>
#import <string.h>
#import <unistd.h>

/* Portable statfs f_fsid access: Linux uses __val[], BSD uses val[] */
#ifdef __linux__
#  define FSID_VAL(buf, i) ((buf).f_fsid.__val[(i)])
#else
#  define FSID_VAL(buf, i) ((buf).f_fsid.val[(i)])
#endif

/* Well-known filesystem magic numbers (Linux <linux/magic.h>) */
#ifndef EXT4_SUPER_MAGIC
#define EXT4_SUPER_MAGIC    0xEF53
#endif
#ifndef NFS_SUPER_MAGIC
#define NFS_SUPER_MAGIC     0x6969
#endif
/* Linux SMB/CIFS share the same super-magic (0xFF534D42); the previous
 * SMB_SUPER_MAGIC constant was malformed and never matched f_type. */
#ifndef CIFS_SUPER_MAGIC
#define CIFS_SUPER_MAGIC    0xFF534D42
#endif
#ifndef FUSE_SUPER_MAGIC
#define FUSE_SUPER_MAGIC    0xBEEF
#endif
#ifndef PROC_SUPER_MAGIC
#define PROC_SUPER_MAGIC    0x9FA0
#endif
#ifndef TMPFS_SUPER_MAGIC
#define TMPFS_SUPER_MAGIC   0x01021994
#endif
#ifndef DEVPTS_SUPER_MAGIC
#define DEVPTS_SUPER_MAGIC  0x1CD1
#endif

static NSMutableDictionary *sVolumeIDCache = nil;

/* ------------------------------------------------------------------ */
#pragma mark - Internal helpers
/* ------------------------------------------------------------------ */

/**
 * Find the mount entry that owns @p path — the deepest mount point that is a
 * directory-boundary prefix of it — and return { mountPoint, source, fsType }.
 * Uses the portable mount-table APIs (getmntent on Linux, getmntinfo on the
 * BSDs) instead of parsing /proc directly.
 */
static NSDictionary *mountInfoForPath(NSString *path)
{
  if (!path || [path length] == 0) return nil;

  const char *cpath = [path fileSystemRepresentation];
  if (cpath == NULL) return nil;
  size_t plen = strlen(cpath);

  NSString *bestMount = nil, *bestSource = nil, *bestType = nil;
  size_t bestLen = 0;

#if defined(__linux__)
  FILE *mt = setmntent(_PATH_MOUNTED, "r");
  if (mt == NULL) return nil;
  struct mntent *me;
  while ((me = getmntent(mt)) != NULL)
    {
      const char *mp = me->mnt_dir;
      size_t mlen = strlen(mp);
      if (mlen > plen || strncmp(cpath, mp, mlen) != 0) continue;
      /* Directory boundary: whole-string match, root "/", or next char '/'. */
      if (mlen < plen && mlen > 1 && cpath[mlen] != '/') continue;
      if (mlen >= bestLen)
        {
          bestLen    = mlen;
          bestMount  = [NSString stringWithUTF8String: mp];
          bestSource = [NSString stringWithUTF8String: me->mnt_fsname];
          bestType   = [NSString stringWithUTF8String: me->mnt_type];
        }
    }
  endmntent(mt);
#else
  struct statfs *mnts = NULL;
  int n = getmntinfo(&mnts, MNT_NOWAIT);
  int i;
  for (i = 0; i < n; i++)
    {
      const char *mp = mnts[i].f_mntonname;
      size_t mlen = strlen(mp);
      if (mlen > plen || strncmp(cpath, mp, mlen) != 0) continue;
      if (mlen < plen && mlen > 1 && cpath[mlen] != '/') continue;
      if (mlen >= bestLen)
        {
          bestLen    = mlen;
          bestMount  = [NSString stringWithUTF8String: mp];
          bestSource = [NSString stringWithUTF8String: mnts[i].f_mntfromname];
          bestType   = [NSString stringWithUTF8String: mnts[i].f_fstypename];
        }
    }
#endif

  if (bestMount == nil) return nil;
  return [NSDictionary dictionaryWithObjectsAndKeys:
            bestMount, @"mountPoint",
            (bestSource ? bestSource : @""), @"source",
            (bestType ? bestType : @""), @"fsType",
            nil];
}

static NSString *stringForFSMagic(long magic)
{
  switch (magic) {
    case EXT4_SUPER_MAGIC:   return @"ext4";
    case 0x00004D44:         return @"msdos";
    case 0x00004D47:         return @"minix";
    case 0xEF51:             return @"ext2";
    case NFS_SUPER_MAGIC:    return @"nfs";
    case CIFS_SUPER_MAGIC:   return @"cifs";
    case FUSE_SUPER_MAGIC:   return @"fuse";
    case 0x9123683E:         return @"btrfs";
    case 0x00000187:         return @"autofs";
    case TMPFS_SUPER_MAGIC:  return @"tmpfs";
    case 0x2BADDEAD:         return @"bfs";
    case 0x63677270:         return @"cgroup";
    case 0x73717368:         return @"shm";
    case DEVPTS_SUPER_MAGIC: return @"devpts";
    case PROC_SUPER_MAGIC:   return @"proc";
    case 0x62646576:         return @"bdev";
    case 0x64646170:         return @"dap";
    case 0x73727265:         return @"sysfs";
    case 0x858458f6:         return @"ramfs";
    case 0x0BD00BD0:         return @"hfs";
    case 0x482D4144:         return @"hfsplus";
    case 0x00000018:         return @"jffs2";
    case 0x6165676C:         return @"efivarfs";
    default:
      if (magic <= 0xFFFF) {
        return [NSString stringWithFormat:@"0x%04lX", magic];
      }
      return [NSString stringWithFormat:@"0x%08lX", magic];
  }
}

/* ------------------------------------------------------------------ */
#pragma mark - GWVolumeID implementation
/* ------------------------------------------------------------------ */

@implementation GWVolumeID

+ (void)initialize
{
  if (self == [GWVolumeID class]) {
    sVolumeIDCache = [[NSMutableDictionary alloc] init];
  }
}

+ (NSString *)volumeIDForPath:(NSString *)path
{
  if (!path) return nil;

  /* Resolve to absolute, real path */
  NSString *resolved = [[path stringByStandardizingPath] stringByResolvingSymlinksInPath];
  if (!resolved) resolved = path;

  /* Check cache */
  if (sVolumeIDCache) {
    NSString *cached = [sVolumeIDCache objectForKey:resolved];
    if (cached) return cached;
  }

  struct statfs buf;
  if (statfs([resolved UTF8String], &buf) != 0) {
    /* Fallback: hash the path itself */
    NSString *fallback = [NSString stringWithFormat:@"path_%lu",
                                   (unsigned long)[resolved hash]];
    if (sVolumeIDCache) {
      [sVolumeIDCache setObject:fallback forKey:resolved];
    }
    return fallback;
  }

  /* Build volume ID from f_fsid */
  int val0 = FSID_VAL(buf, 0);
  int val1 = FSID_VAL(buf, 1);
  NSString *volID = nil;

  if (val0 != 0 || val1 != 0) {
    volID = [NSString stringWithFormat:@"%08X%08X", val0, val1];
  }

  /* If f_fsid is all zeros, use mount source info */
  if (!volID || [volID isEqualToString:@"0000000000000000"]) {
    NSDictionary *mi = mountInfoForPath(resolved);
    NSString *source = [mi objectForKey:@"source"];
    if (source && [source length] > 0) {
      volID = [NSString stringWithFormat:@"src_%lu",
                         (unsigned long)[source hash]];
    } else {
      /* Last resort: hash the mount point */
      NSString *mp = [self mountPointForPath:resolved];
      volID = [NSString stringWithFormat:@"mp_%lu",
                         (unsigned long)[mp hash]];
    }
  }

  if (sVolumeIDCache) {
    [sVolumeIDCache setObject:volID forKey:resolved];
  }

  return volID;
}

+ (NSString *)cacheDirectory
{
  NSString *home = NSHomeDirectory();
  NSString *dir = [home stringByAppendingPathComponent:
                    @"Library/Caches/com.apple.finder"];

  NSFileManager *fm = [NSFileManager defaultManager];
  BOOL isDir = NO;
  if (![fm fileExistsAtPath:dir isDirectory:&isDir]) {
    NSError *err = nil;
    if (![fm createDirectoryAtPath:dir
       withIntermediateDirectories:YES
                        attributes:nil
                             error:&err]) {
      NSDebugLLog(@"gwspace", @"GWVolumeID: Failed to create cache dir %@: %@",
                  dir, err);
      return nil;
    }
  } else if (!isDir) {
    NSDebugLLog(@"gwspace", @"GWVolumeID: Cache path exists but is not a directory: %@", dir);
    return nil;
  }

  return dir;
}

+ (NSString *)cacheFilePathForPath:(NSString *)path
{
  NSString *volID = [self volumeIDForPath:path];
  if (!volID) return nil;

  NSString *cacheDir = [self cacheDirectory];
  if (!cacheDir) return nil;

  return [cacheDir stringByAppendingPathComponent:
           [volID stringByAppendingString:@".DS_Store"]];
}

+ (BOOL)isNetworkMount:(NSString *)path
{
  if (!path) return NO;

  NSString *resolved = [[path stringByStandardizingPath] stringByResolvingSymlinksInPath];
  if (!resolved) resolved = path;

  struct statfs buf;
  if (statfs([resolved UTF8String], &buf) != 0) return NO;

#ifdef __linux__
  /* Linux: statfs provides f_type (numeric magic) */
  long type = (long)buf.f_type;

  /* Direct network filesystem detection (SMB and CIFS share this magic) */
  if (type == NFS_SUPER_MAGIC)      return YES;
  if (type == CIFS_SUPER_MAGIC)     return YES;

  /* FUSE: check mount source for network indicators */
  if (type == FUSE_SUPER_MAGIC) {
    NSDictionary *mi = mountInfoForPath(resolved);
    NSString *source = [mi objectForKey:@"source"];
    NSString *fsType = [mi objectForKey:@"fsType"];

    if ([source hasPrefix:@"sshfs"] ||
        [source hasPrefix:@"gvfsd"] ||
        [source hasPrefix:@"sftp"] ||
        [source rangeOfString:@"@"]
          .location != NSNotFound) {
      return YES;
    }
    if ([fsType rangeOfString:@"fuse."
                      options: NSCaseInsensitiveSearch]
          .location != NSNotFound) {
      return YES;
    }
  }
#else
  /* BSDs and macOS: statfs has f_fstypename (string) instead of f_type */
  {
    NSString *fstype = [NSString stringWithUTF8String:buf.f_fstypename];
    if ([fstype isEqualToString:@"nfs"])   return YES;
    if ([fstype isEqualToString:@"smbfs"]) return YES;
    if ([fstype isEqualToString:@"cifs"])  return YES;
    if ([fstype isEqualToString:@"fuse"])  return YES;
  }
#endif

  return NO;
}

+ (BOOL)isReadOnlyVolume:(NSString *)path
{
  if (!path) return NO;

  NSString *resolved = [[path stringByStandardizingPath] stringByResolvingSymlinksInPath];
  if (!resolved) resolved = path;

  struct statfs buf;
  if (statfs([resolved UTF8String], &buf) != 0) return NO;

  /* On Linux, MS_RDONLY is bit 0 of f_flags */
  return (buf.f_flags & 1) != 0;
}

+ (NSString *)filesystemTypeForPath:(NSString *)path
{
  if (!path) return nil;

  NSString *resolved = [[path stringByStandardizingPath] stringByResolvingSymlinksInPath];
  if (!resolved) resolved = path;

  struct statfs buf;
  if (statfs([resolved UTF8String], &buf) != 0) return nil;

#ifdef __linux__
  /* Linux: statfs provides f_type (numeric magic) */
  return stringForFSMagic((long)buf.f_type);
#else
  /* BSDs and macOS: return f_fstypename string directly */
  return [NSString stringWithUTF8String:buf.f_fstypename];
#endif
}

+ (NSString *)mountSourceForPath:(NSString *)path
{
  if (!path) return nil;

  NSString *resolved = [[path stringByStandardizingPath] stringByResolvingSymlinksInPath];
  if (!resolved) resolved = path;

  NSDictionary *mi = mountInfoForPath(resolved);
  return [mi objectForKey:@"source"];
}

+ (NSString *)mountPointForPath:(NSString *)path
{
  if (!path) return nil;

  NSString *resolved = [[path stringByStandardizingPath] stringByResolvingSymlinksInPath];
  if (!resolved) resolved = path;

  NSDictionary *mi = mountInfoForPath(resolved);
  return [mi objectForKey:@"mountPoint"];
}

+ (void)flushCache
{
  [sVolumeIDCache removeAllObjects];
}

@end
