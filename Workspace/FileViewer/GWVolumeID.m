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
#else
/* BSDs and macOS: struct statfs via <sys/param.h> + <sys/mount.h> */
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
#ifndef SMB_SUPER_MAGIC
#define SMB_SUPER_MAGIC     0x0000FF534D42ull
#endif
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
static NSString *sMountInfoPath = @"/proc/self/mountinfo";

/* ------------------------------------------------------------------ */
#pragma mark - Stable string hash (djb2, deterministic across runs)
/* ------------------------------------------------------------------ */

/**
 * djb2 hash over the UTF-8 bytes of str.  Unlike -[NSString hash] this
 * is stable across process restarts and platform implementations.
 */
static uint32_t stableHashForString(NSString *str)
{
  const char *utf8 = [str UTF8String];
  if (!utf8) return 0;
  uint32_t hash = 5381;
  unsigned char c;
  while ((c = (unsigned char)*utf8++))
    hash = ((hash << 5) + hash) + c;
  return hash;
}

/* ------------------------------------------------------------------ */
#pragma mark - Internal helpers
/* ------------------------------------------------------------------ */

/**
 * Parse /proc/self/mountinfo and find the entry that matches @p path.
 * Returns a dictionary with keys: mountPoint, source, fsType, options,
 * superOptions, major, minor, root.
 */
static NSDictionary *mountInfoForPath(NSString *path)
{
  if (!path || [path length] == 0) return nil;

  NSString *content = [NSString stringWithContentsOfFile:sMountInfoPath
                                                encoding:NSUTF8StringEncoding
                                                   error:NULL];
  if (!content) return nil;

  /* Find the longest matching mount point (deepest mount) */
  NSDictionary *best = nil;
  NSUInteger bestLen = 0;

  for (NSString *line in [content componentsSeparatedByString:@"\n"]) {
    if ([line length] == 0) continue;

    /* Format: id parent major:minor root mountPoint options - fsType source superOptions */
    NSArray *parts = [line componentsSeparatedByString:@" "];
    if ([parts count] < 10) continue;

    /* Find the separator '-' */
    NSUInteger dashIdx = NSNotFound;
    for (NSUInteger i = 0; i < [parts count]; i++) {
      if ([[parts objectAtIndex:i] isEqualToString:@"-"]) {
        dashIdx = i;
        break;
      }
    }
    if (dashIdx == NSNotFound || dashIdx + 3 >= [parts count]) continue;

    NSString *mountPoint = [parts objectAtIndex:4];
    NSUInteger mpLen = [mountPoint length];

    /* Skip entries whose mount point is not a prefix of path */
    if (mpLen > [path length]) continue;
    if (![path hasPrefix:mountPoint]) continue;
    /* Ensure a directory boundary: either same length or next char is '/' */
    if (mpLen < [path length]
        && [path characterAtIndex:mpLen] != '/') continue;

    /* Prefer the deepest (longest) match */
    if (mpLen > bestLen) {
      bestLen = mpLen;
      NSString *fsType  = [parts objectAtIndex:dashIdx + 1];
      NSString *source  = [parts objectAtIndex:dashIdx + 2];
      NSString *superOpts = (dashIdx + 3 < [parts count])
                              ? [parts objectAtIndex:dashIdx + 3] : @"";
      NSString *root    = [parts objectAtIndex:3];
      NSString *majMin  = [parts objectAtIndex:2];

      NSArray *mmParts = [majMin componentsSeparatedByString:@":"];
      NSString *major = ([mmParts count] >= 2) ? [mmParts objectAtIndex:0] : @"0";
      NSString *minor = ([mmParts count] >= 2) ? [mmParts objectAtIndex:1] : @"0";

      best = [NSDictionary dictionaryWithObjectsAndKeys:
                           mountPoint, @"mountPoint",
                           source, @"source",
                           fsType, @"fsType",
                           [parts objectAtIndex:5], @"options",
                           superOpts, @"superOptions",
                           root, @"root",
                           major, @"major",
                           minor, @"minor",
                           nil];
    }
  }

  return best;
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
    /* Fallback: stable hash of the path itself */
    NSString *fallback = [NSString stringWithFormat:@"path_%08X",
                                   stableHashForString(resolved)];
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
      volID = [NSString stringWithFormat:@"src_%08X",
                         stableHashForString(source)];
    } else {
      /* Last resort: hash the mount point */
      NSString *mp = [self mountPointForPath:resolved];
      volID = [NSString stringWithFormat:@"mp_%08X",
                         stableHashForString(mp)];
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

  /* Direct network filesystem detection */
  if (type == NFS_SUPER_MAGIC)      return YES;
  if (type == SMB_SUPER_MAGIC)      return YES;
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

#ifdef __linux__
  /* On Linux, MS_RDONLY is bit 0 of f_flags */
  return (buf.f_flags & 1) != 0;
#else
  /* On BSD/macOS, use the portable MNT_RDONLY constant */
  return (buf.f_flags & MNT_RDONLY) != 0;
#endif
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

#ifdef __linux__
  NSDictionary *mi = mountInfoForPath(resolved);
  return [mi objectForKey:@"source"];
#else
  struct statfs buf;
  if (statfs([resolved UTF8String], &buf) != 0) return nil;
  return [NSString stringWithUTF8String:buf.f_mntfromname];
#endif
}

+ (NSString *)mountPointForPath:(NSString *)path
{
  if (!path) return nil;

  NSString *resolved = [[path stringByStandardizingPath] stringByResolvingSymlinksInPath];
  if (!resolved) resolved = path;

#ifdef __linux__
  NSDictionary *mi = mountInfoForPath(resolved);
  return [mi objectForKey:@"mountPoint"];
#else
  struct statfs buf;
  if (statfs([resolved UTF8String], &buf) != 0) return nil;
  return [NSString stringWithUTF8String:buf.f_mntonname];
#endif
}

+ (void)flushCache
{
  [sVolumeIDCache removeAllObjects];
}

@end
