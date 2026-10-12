/* GWVolumeID.m
 *
 * Stable volume identifier implementation.
 *
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-2.0-or-later
 */

#import "GWVolumeID.h"
/* GNUstep's -fileSystemRepresentation returns UTF-16 on Windows, but the C
   library calls here take narrow strings, so use the UTF-8 form there. On
   the other platforms this is the plain -fileSystemRepresentation call. */
#ifdef _WIN32
#define GW_FSREP(path) [(path) UTF8String]
#else
#define GW_FSREP(path) [(path) fileSystemRepresentation]
#endif

#ifdef _WIN32
/* Windows (MinGW): no statfs() and no mount table.  Provide an inert
 * stand-in with the BSD field names so the non-Linux code paths below
 * compile; statfs() always fails, so callers use their fallbacks
 * (path hash volume IDs, no network/read-only detection). */
#import <errno.h>
struct statfs {
  long f_type;
  long f_flags;
  struct { int val[2]; } f_fsid;
  char f_fstypename[16];
  char f_mntfromname[1];
  char f_mntonname[1];
};
#define MNT_NOWAIT 0
static int statfs(const char *path, struct statfs *buf)
{
  (void)path;
  (void)buf;
  errno = ENOSYS;
  return -1;
}
static int getmntinfo(struct statfs **mntbufp, int flags)
{
  (void)flags;
  *mntbufp = NULL;
  return 0;
}
#elif defined(__linux__)
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

#if defined(__linux__)
/* The only mount-table file that also supports poll(2) POLLPRI: the fd
 * GWDesktopManager's mount-change watcher blocks on has to be this one,
 * not /etc/mtab, which is an ordinary (or symlinked) file with no such
 * notification. */
#define GW_LIVE_MOUNT_TABLE "/proc/self/mounts"
#endif

/* ------------------------------------------------------------------ */
#pragma mark - Internal helpers
/* ------------------------------------------------------------------ */

/**
 * Read every entry of the mount table at @p tablePath (Linux: getmntent;
 * nil means the live table, GW_LIVE_MOUNT_TABLE) or of the live kernel
 * table (BSDs: getmntinfo, @p tablePath ignored - there is no on-disk file
 * to point it at there). Returns one { mountPoint, source, fsType }
 * dictionary per entry, or nil if the table could not be opened. Never
 * calls statfs/statvfs/stat/access on any of the mount points it lists -
 * it only reads the table itself.
 */
static NSArray *allMountEntries(const char *tablePath)
{
#if defined(__linux__)
  const char *path = tablePath ? tablePath : GW_LIVE_MOUNT_TABLE;
  FILE *mt = setmntent(path, "r");
  if (mt == NULL) return nil;

  NSMutableArray *entries = [NSMutableArray array];
  struct mntent *me;
  while ((me = getmntent(mt)) != NULL)
    {
      [entries addObject:
        [NSDictionary dictionaryWithObjectsAndKeys:
          [NSString stringWithUTF8String: me->mnt_dir],    @"mountPoint",
          [NSString stringWithUTF8String: me->mnt_fsname], @"source",
          [NSString stringWithUTF8String: me->mnt_type],   @"fsType",
          nil]];
    }
  endmntent(mt);
  return entries;
#else
  struct statfs *mnts = NULL;
  int n = getmntinfo(&mnts, MNT_NOWAIT);
  if (n < 0) return nil;

  NSMutableArray *entries = [NSMutableArray arrayWithCapacity: n];
  int i;
  for (i = 0; i < n; i++)
    {
      [entries addObject:
        [NSDictionary dictionaryWithObjectsAndKeys:
          [NSString stringWithUTF8String: mnts[i].f_mntonname],   @"mountPoint",
          [NSString stringWithUTF8String: mnts[i].f_mntfromname], @"source",
          [NSString stringWithUTF8String: mnts[i].f_fstypename],  @"fsType",
          nil]];
    }
  return entries;
#endif
}

/**
 * Find the mount entry that owns @p path — the deepest mount point that is a
 * directory-boundary prefix of it — and return { mountPoint, source, fsType }.
 * Reuses allMountEntries() (getmntent on Linux, getmntinfo on the BSDs)
 * rather than walking the table a second time.
 */
static NSDictionary *mountInfoForPath(NSString *path)
{
  if (!path || [path length] == 0) return nil;

  const char *cpath = GW_FSREP(path);
  if (cpath == NULL) return nil;
  size_t plen = strlen(cpath);

  /* Existing per-path lookups have always read /etc/mtab (_PATH_MOUNTED) on
   * Linux; kept exactly as before so this refactor changes no behavior
   * here, only removes the duplicated getmntent loop. */
  NSArray *entries = allMountEntries(
#if defined(__linux__)
    _PATH_MOUNTED
#else
    NULL
#endif
  );
  if (entries == nil) return nil;

  NSString *bestMount = nil, *bestSource = nil, *bestType = nil;
  size_t bestLen = 0;

  for (NSDictionary *e in entries)
    {
      NSString *mpStr = [e objectForKey: @"mountPoint"];
      const char *mp = GW_FSREP(mpStr);
      size_t mlen = strlen(mp);
      if (mlen > plen || strncmp(cpath, mp, mlen) != 0) continue;
      /* Directory boundary: whole-string match, root "/", or next char '/'. */
      if (mlen < plen && mlen > 1 && cpath[mlen] != '/') continue;
      if (mlen >= bestLen)
        {
          bestLen    = mlen;
          bestMount  = mpStr;
          bestSource = [e objectForKey: @"source"];
          bestType   = [e objectForKey: @"fsType"];
        }
    }

  if (bestMount == nil) return nil;
  return [NSDictionary dictionaryWithObjectsAndKeys:
            bestMount, @"mountPoint",
            (bestSource ? bestSource : @""), @"source",
            (bestType ? bestType : @""), @"fsType",
            nil];
}

/* Only Linux reports the filesystem as a numeric f_type; the BSDs name it
 * in f_fstypename. */
#ifdef __linux__
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
#endif /* __linux__ */

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

/* The id older versions named the cache file after, from f_fsid (or the
 * mount source / mount point when the file system reports none). */
static NSString *deviceVolumeID(NSString *resolved, struct statfs *buf)
{
  int val0 = FSID_VAL(*buf, 0);
  int val1 = FSID_VAL(*buf, 1);

  if (val0 != 0 || val1 != 0) {
    return [NSString stringWithFormat:@"%08X%08X", val0, val1];
  }
  NSString *source = [mountInfoForPath(resolved) objectForKey:@"source"];
  if ([source length] > 0) {
    return [NSString stringWithFormat:@"src_%lu", (unsigned long)[source hash]];
  }
  return [NSString stringWithFormat:@"mp_%lu",
                   (unsigned long)[[GWVolumeID mountPointForPath:resolved] hash]];
}

static NSString *resolvedPath(NSString *path)
{
  NSString *resolved = [[path stringByStandardizingPath] stringByResolvingSymlinksInPath];
  return resolved ? resolved : path;
}

+ (NSString *)volumeIDForPath:(NSString *)path
{
  if (!path) return nil;

  NSString *resolved = resolvedPath(path);
  NSString *volID = [sVolumeIDCache objectForKey:resolved];
  if (volID) return volID;

  struct statfs buf;
  if (statfs([resolved UTF8String], &buf) != 0) {
    volID = [NSString stringWithFormat:@"path_%lu", (unsigned long)[resolved hash]];
  } else {
    /* The file system's own identity first: f_fsid is made from the device
     * number, so removable media got another cache file after every insert
     * and the layout kept for it was never found again. */
    NSString *identity = [self filesystemIdentityForDevice:
                                 [mountInfoForPath(resolved) objectForKey:@"source"]
                                             inDirectories:
                                 [NSArray arrayWithObjects:@"/dev/disk/by-uuid",
                                          @"/dev/ufsid", @"/dev/gptid", nil]];
    volID = identity ? [@"uuid_" stringByAppendingString:identity]
                     : deviceVolumeID(resolved, &buf);
  }
  [sVolumeIDCache setObject:volID forKey:resolved];
  return volID;
}

+ (NSString *)filesystemIdentityForDevice:(NSString *)devicePath
                            inDirectories:(NSArray *)directories
{
  struct stat device;

  if (devicePath == nil || stat(GW_FSREP(devicePath), &device) != 0
      || !(S_ISBLK(device.st_mode) || S_ISCHR(device.st_mode))) {
    return nil;
  }
  for (NSString *dir in directories) {
    NSArray *names = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:dir error:NULL];
    for (NSString *name in [names sortedArrayUsingSelector:@selector(compare:)]) {
      struct stat entry;
      NSString *path = [dir stringByAppendingPathComponent:name];
      if (stat(GW_FSREP(path), &entry) == 0
          && (entry.st_mode & S_IFMT) == (device.st_mode & S_IFMT)
          && entry.st_rdev == device.st_rdev) {
        return name;
      }
    }
  }
  return nil;
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
      return nil;
    }
  } else if (!isDir) {
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

+ (void)adoptLegacyCacheFileForPath:(NSString *)path
{
  NSString *cachePath = [self cacheFilePathForPath:path];
  NSFileManager *fm = [NSFileManager defaultManager];
  struct statfs buf;

  if (![[self volumeIDForPath:path] hasPrefix:@"uuid_"] || cachePath == nil
      || [fm fileExistsAtPath:cachePath]
      || statfs([resolvedPath(path) UTF8String], &buf) != 0) {
    return;
  }
  NSString *legacy = [[cachePath stringByDeletingLastPathComponent]
                       stringByAppendingPathComponent:
                         [deviceVolumeID(resolvedPath(path), &buf)
                           stringByAppendingString:@".DS_Store"]];
  if ([fm fileExistsAtPath:legacy]) {
    [fm moveItemAtPath:legacy toPath:cachePath error:NULL];
  }
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

+ (NSArray *)mountedFilesystemsFromTable:(NSString *)tablePath
{
  const char *cpath = tablePath ? GW_FSREP(tablePath) : NULL;
  NSArray *entries = allMountEntries(cpath);
  return entries ? entries : [NSArray array];
}

+ (NSArray *)mountedFilesystems
{
  return [self mountedFilesystemsFromTable: nil];
}

@end
