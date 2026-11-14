/* GWDestinationClassifier.m
 *
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

#if defined(__linux__) && !defined(_GNU_SOURCE)
#define _GNU_SOURCE
#endif

#import "GWDestinationClassifier.h"
#import "GWFileDataCopier.h"
#import <GNUstepBase/GNUstep.h>

#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/stat.h>
#include <sys/types.h>
#if defined(__linux__)
#include <sys/sysmacros.h>
#endif
#if defined(__FreeBSD__) || defined(__OpenBSD__) || defined(__NetBSD__) \
  || defined(__DragonFly__) || defined(__APPLE__)
#define GW_BSD_MOUNTS 1
#include <sys/param.h>
#include <sys/mount.h>
#include <sys/sysctl.h>
#if defined(__NetBSD__)
#include <sys/statvfs.h>
typedef struct statvfs gw_mount_t;
#define gw_mount_flags f_flag
#else
typedef struct statfs gw_mount_t;
#define gw_mount_flags f_flags
#endif
#endif

NSString * const GWCopyDestinationEnvironmentKey = @"GW_COPY_DESTINATION";

#if !defined(_WIN32)
static NSError *
flushError(NSString *path, int code)
{
  NSString *reason = [NSString stringWithFormat: @"%s", strerror(code)];

  return [NSError errorWithDomain: NSPOSIXErrorDomain
                             code: code
                         userInfo: @{ NSFilePathErrorKey: path,
                                      NSLocalizedDescriptionKey: reason }];
}
#endif

@implementation GWDestination

+ (instancetype)destinationWithKind:(GWDestinationKind)kind
                     filesystemType:(NSString *)type
                         mountPoint:(NSString *)mountPoint
{
  GWDestination *d = [[self alloc] init];

  d->_kind = kind;
  d->_filesystemType = [type copy];
  d->_mountPoint = [mountPoint copy];
  return AUTORELEASE(d);
}

- (void)dealloc
{
  RELEASE(_filesystemType);
  RELEASE(_mountPoint);
  [super dealloc];
}

@synthesize kind = _kind;
@synthesize filesystemType = _filesystemType;
@synthesize mountPoint = _mountPoint;

- (NSString *)description
{
  static const char *names[] = { "local", "removable", "network" };

  return [NSString stringWithFormat: @"<GWDestination %s %@ on %@>",
                   names[_kind], _filesystemType, _mountPoint];
}

- (BOOL)usesWriteWindows
{
  return _kind != GWDestinationLocal;
}

- (unsigned long long)windowCap
{
  NSString *t = [_filesystemType lowercaseString];

  /* SMB servers answer every flush with a round trip of their own, so
   * small windows cost a share far more than a local device. */
  if ([t isEqual: @"cifs"] || [t isEqual: @"smb3"] || [t isEqual: @"smbfs"])
    {
      return GW_COPY_CIFS_WINDOW_CAP;
    }
  return GW_COPY_WINDOW_CAP;
}

- (BOOL)needsFinalFlush
{
  return _kind == GWDestinationRemovable;
}

#if !defined(_WIN32) && !defined(__linux__)
static int
fsyncPath(NSString *path)
{
  int fd = open([path fileSystemRepresentation], O_RDONLY);
  int r;

  if (fd < 0)
    {
      return errno;
    }
  r = fsync(fd);
  r = (r == 0) ? 0 : errno;
  close(fd);
  return r;
}
#endif

- (BOOL)flushItemsAtPaths:(NSArray *)items
              inDirectory:(NSString *)directory
                    error:(NSError **)error
{
#if defined(_WIN32)
  return YES;
#elif defined(__linux__)
  /* One syncfs() writes the small files of a whole operation in one go;
   * an fsync() per file made thousands of small files take seconds. */
  int fd = open([directory fileSystemRepresentation], O_RDONLY | O_DIRECTORY);
  int r;

  if (fd < 0)
    {
      if (error)
        {
          *error = flushError(directory, errno);
        }
      return NO;
    }
  r = syncfs(fd);
  if (r != 0)
    {
      int code = errno;

      close(fd);
      if (error)
        {
          *error = flushError(directory, code);
        }
      return NO;
    }
  close(fd);
  return YES;
#else
  /* The BSDs have no syncfs(), and their sync() only schedules the writes,
   * so every file and folder written gets its own fsync(). */
  NSFileManager *fm = [NSFileManager defaultManager];
  NSEnumerator *en = [items objectEnumerator];
  NSString *item;
  int r;

  while ((item = [en nextObject]) != nil)
    {
      NSMutableArray *paths = [NSMutableArray arrayWithObject: item];
      NSString *sidecar = [[item stringByDeletingLastPathComponent]
        stringByAppendingPathComponent:
          [@"._" stringByAppendingString: [item lastPathComponent]]];
      NSDirectoryEnumerator *walk;
      NSString *rel;
      NSUInteger i;
      BOOL isDir = NO;

      if ([fm fileExistsAtPath: sidecar])
        {
          [paths addObject: sidecar];
        }
      if ([fm fileExistsAtPath: item isDirectory: &isDir] && isDir)
        {
          walk = [fm enumeratorAtPath: item];
          while ((rel = [walk nextObject]) != nil)
            {
              NSString *type = [[walk fileAttributes] fileType];

              if ([type isEqual: NSFileTypeRegular]
                  || [type isEqual: NSFileTypeDirectory])
                {
                  [paths addObject: [item stringByAppendingPathComponent: rel]];
                }
            }
        }
      for (i = 0; i < [paths count]; i++)
        {
          NSString *p = [paths objectAtIndex: i];
          NSDictionary *attrs = [fm fileAttributesAtPath: p traverseLink: NO];

          if ([[attrs fileType] isEqual: NSFileTypeSymbolicLink])
            {
              continue;
            }
          r = fsyncPath(p);
          if (r != 0)
            {
              if (error)
                {
                  *error = flushError(p, r);
                }
              return NO;
            }
        }
    }
  r = fsyncPath(directory);
  if (r != 0)
    {
      if (error)
        {
          *error = flushError(directory, r);
        }
      return NO;
    }
  return YES;
#endif
}

@end


@implementation GWDestinationClassifier

+ (GWDestinationClassifier *)sharedClassifier
{
  static GWDestinationClassifier *shared = nil;

  @synchronized (self)
    {
      if (shared == nil)
        {
          shared = [[self alloc] initWithSysfsRoot: @"/sys"
                                     mountInfoPath: @"/proc/self/mountinfo"];
        }
    }
  return shared;
}

- (instancetype)initWithSysfsRoot:(NSString *)sysfsRoot
                    mountInfoPath:(NSString *)mountInfoPath
{
  self = [super init];
  if (self != nil)
    {
      _sysfsRoot = [sysfsRoot copy];
      _mountInfoPath = [mountInfoPath copy];
      _removableByDevice = [NSMutableDictionary new];
      _destinationByMount = [NSMutableDictionary new];
      _lock = [NSLock new];
    }
  return self;
}

- (void)dealloc
{
  RELEASE(_sysfsRoot);
  RELEASE(_mountInfoPath);
  RELEASE(_removableByDevice);
  RELEASE(_destinationByMount);
  RELEASE(_lock);
  [super dealloc];
}

+ (GWFilesystemClass)classOfFilesystemType:(NSString *)type
                                    source:(NSString *)source
{
  static NSSet *network = nil;
  static NSSet *virtual = nil;
  NSString *t = [type lowercaseString];

  if (network == nil)
    {
      network = [[NSSet alloc] initWithObjects:
        @"nfs", @"nfs4", @"cifs", @"smb3", @"smbfs", @"smb2", @"ceph",
        @"glusterfs", @"9p", @"afs", @"ncpfs", @"lustre", @"gpfs",
        @"fuse.sshfs", @"fusefs.sshfs", @"fuse.glusterfs", @"fuse.rclone",
        @"fusefs.rclone", @"davfs", nil];
      virtual = [[NSSet alloc] initWithObjects:
        @"tmpfs", @"ramfs", @"devtmpfs", @"proc", @"sysfs", @"overlay",
        @"procfs", @"devfs", @"mfs", @"fdescfs", @"nullfs", nil];
    }
  if ([network containsObject: t])
    {
      return GWFilesystemNetwork;
    }
  if ([virtual containsObject: t])
    {
      return GWFilesystemVirtual;
    }
  if ([t isEqual: @"fuse"] || [t hasPrefix: @"fuse."]
      || [t hasPrefix: @"fusefs."])
    {
      /* A FUSE filesystem without a block device behind it gets its data
       * from somewhere else, usually a server (rclone, sshfs, ...). */
      if ([source hasPrefix: @"/dev/"])
        {
          return GWFilesystemDeviceBacked;
        }
      return GWFilesystemNetwork;
    }
  return GWFilesystemDeviceBacked;
}

/* mountinfo escapes blanks, tabs, newlines and backslashes as \ooo. */
static NSString *
unescapeMountField(NSString *field)
{
  const char *s = [field UTF8String];
  NSMutableData *out = [NSMutableData dataWithCapacity: strlen(s)];

  while (*s)
    {
      if (s[0] == '\\' && s[1] >= '0' && s[1] <= '7' && s[2] >= '0'
          && s[2] <= '7' && s[3] >= '0' && s[3] <= '7')
        {
          char c = (char)(((s[1] - '0') << 6) | ((s[2] - '0') << 3)
                          | (s[3] - '0'));

          [out appendBytes: &c length: 1];
          s += 4;
        }
      else
        {
          [out appendBytes: s length: 1];
          s++;
        }
    }
  return AUTORELEASE([[NSString alloc] initWithData: out
                                           encoding: NSUTF8StringEncoding]);
}

+ (NSDictionary *)parseMountInfoLine:(NSString *)line
{
  NSArray *fields = [line componentsSeparatedByString: @" "];
  NSUInteger sep = [fields indexOfObject: @"-"];
  NSArray *dev;
  NSString *source;

  if (sep == NSNotFound || sep < 6 || [fields count] < sep + 3)
    {
      return nil;
    }
  dev = [[fields objectAtIndex: 2] componentsSeparatedByString: @":"];
  if ([dev count] != 2)
    {
      return nil;
    }
  source = unescapeMountField([fields objectAtIndex: sep + 2]);
  return @{ @"mountID": [NSNumber numberWithInt:
                           [[fields objectAtIndex: 0] intValue]],
            @"major": [NSNumber numberWithInt: [[dev objectAtIndex: 0] intValue]],
            @"minor": [NSNumber numberWithInt: [[dev objectAtIndex: 1] intValue]],
            @"mountPoint": unescapeMountField([fields objectAtIndex: 4]),
            @"type": unescapeMountField([fields objectAtIndex: sep + 1]),
            @"source": source };
}

+ (NSDictionary *)mountForPath:(NSString *)path inMounts:(NSArray *)mounts
{
  NSDictionary *best = nil;
  NSUInteger bestLength = 0;
  NSEnumerator *en = [mounts objectEnumerator];
  NSDictionary *m;

  while ((m = [en nextObject]) != nil)
    {
      NSString *mp = [m objectForKey: @"mountPoint"];
      NSUInteger len = [mp length];
      BOOL inside;

      if ([mp isEqual: @"/"])
        {
          inside = [path hasPrefix: @"/"];
        }
      else
        {
          inside = [path isEqual: mp]
            || [path hasPrefix: [mp stringByAppendingString: @"/"]];
        }
      /* ">=" so that of two mounts on one point the later, visible one
       * wins, as in the mount table's order. */
      if (inside && (best == nil || len >= bestLength))
        {
          best = m;
          bestLength = len;
        }
    }
  return best;
}

+ (NSString *)diskNameOfMountSource:(NSString *)source
{
  const char *s;
  const char *p;

  if (![source hasPrefix: @"/dev/"])
    {
      return nil;
    }
  s = [[source substringFromIndex: 5] UTF8String];
  p = s;
  while (*p >= 'a' && *p <= 'z')
    {
      p++;
    }
  if (p == s || !(*p >= '0' && *p <= '9'))
    {
      return nil;
    }
  while (*p >= '0' && *p <= '9')
    {
      p++;
    }
  return AUTORELEASE([[NSString alloc] initWithBytes: s
                                              length: p - s
                                            encoding: NSUTF8StringEncoding]);
}

+ (BOOL)isRemovableBSDDisk:(NSString *)disk daFlags:(NSString *)flags
{
  NSString *letters;
  NSUInteger i = 0;

  while (i < [disk length] && [[NSCharacterSet lowercaseLetterCharacterSet]
                                characterIsMember: [disk characterAtIndex: i]])
    {
      i++;
    }
  letters = [disk substringToIndex: i];
  /* SD cards, through the MMC stack or CAM. */
  if ([letters isEqual: @"mmcsd"] || [letters isEqual: @"sdda"])
    {
      return YES;
    }
  /* da(4) serves USB sticks and SAS or virtio disks alike; the inquiry's
   * removable-medium bit tells them apart. */
  if ([letters isEqual: @"da"])
    {
      return [flags rangeOfString: @"PACK_REMOVABLE"].location != NSNotFound;
    }
  return NO;
}

/* The first line of a sysfs attribute, nil when there is none. */
static NSString *
readAttribute(NSString *path)
{
  NSString *s = [NSString stringWithContentsOfFile: path];

  return [s stringByTrimmingCharactersInSet:
              [NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

static NSString *
realPath(NSString *path)
{
#if defined(_WIN32)
  return [path stringByResolvingSymlinksInPath];
#else
  char buf[PATH_MAX];

  if (realpath([path fileSystemRepresentation], buf) == NULL)
    {
      return nil;
    }
  return [NSString stringWithUTF8String: buf];
#endif
}

- (BOOL)_isRemovableBlockDirectory:(NSString *)dir depth:(int)depth
{
  NSFileManager *fm = [NSFileManager defaultManager];
  NSString *devices = [_sysfsRoot stringByAppendingPathComponent: @"devices"];
  NSString *slaves;
  NSArray *under;
  NSString *dev;

  if (dir == nil || depth > 8)
    {
      return NO;
    }
  /* A partition's own directory has none of the disk's attributes. */
  if ([fm fileExistsAtPath: [dir stringByAppendingPathComponent: @"partition"]])
    {
      dir = [dir stringByDeletingLastPathComponent];
    }
  /* device-mapper (crypt, LVM) and md RAID: removable when any disk they
   * are built on is, since unplugging that one loses the data too. */
  slaves = [dir stringByAppendingPathComponent: @"slaves"];
  under = [fm directoryContentsAtPath: slaves];
  if ([under count] > 0)
    {
      NSEnumerator *en = [under objectEnumerator];
      NSString *name;

      while ((name = [en nextObject]) != nil)
        {
          NSString *s = realPath([slaves stringByAppendingPathComponent: name]);

          if ([self _isRemovableBlockDirectory: s depth: depth + 1])
            {
              return YES;
            }
        }
      return NO;
    }
  if ([readAttribute([dir stringByAppendingPathComponent: @"removable"])
        isEqual: @"1"])
    {
      return YES;
    }
  /* Many USB disks and card readers do not set the medium's removable
   * bit, but the kernel knows the port or slot they hang off is
   * removable; an SD card says so in its MMC card type. */
  dev = realPath([dir stringByAppendingPathComponent: @"device"]);
  while (dev != nil && [dev hasPrefix: devices] && [dev length] > [devices length])
    {
      if ([readAttribute([dev stringByAppendingPathComponent: @"removable"])
            isEqual: @"removable"])
        {
          return YES;
        }
      if ([readAttribute([dev stringByAppendingPathComponent: @"type"])
            isEqual: @"SD"])
        {
          return YES;
        }
      dev = [dev stringByDeletingLastPathComponent];
    }
  return NO;
}

- (BOOL)isRemovableDeviceMajor:(unsigned)major minor:(unsigned)minor
{
  NSString *key = [NSString stringWithFormat: @"%u:%u", major, minor];
  NSNumber *known;
  BOOL removable;

  [_lock lock];
  known = RETAIN([_removableByDevice objectForKey: key]);
  [_lock unlock];
  if (known != nil)
    {
      removable = [known boolValue];
      RELEASE(known);
      return removable;
    }
  removable = [self _isRemovableBlockDirectory:
    realPath([[_sysfsRoot stringByAppendingPathComponent: @"dev/block"]
               stringByAppendingPathComponent: key])
                                         depth: 0];
  [_lock lock];
  [_removableByDevice setObject: [NSNumber numberWithBool: removable]
                         forKey: key];
  [_lock unlock];
  return removable;
}

static GWDestinationKind
overriddenKind(GWDestinationKind kind)
{
  const char *force = getenv([GWCopyDestinationEnvironmentKey UTF8String]);

  if (force == NULL)
    {
      return kind;
    }
  if (strcmp(force, "removable") == 0)
    {
      return GWDestinationRemovable;
    }
  if (strcmp(force, "network") == 0)
    {
      return GWDestinationNetwork;
    }
  if (strcmp(force, "local") == 0)
    {
      return GWDestinationLocal;
    }
  return kind;
}

#if defined(__linux__)

- (GWDestination *)_destinationForMount:(NSDictionary *)m
{
  NSString *type = [m objectForKey: @"type"];
  NSString *source = [m objectForKey: @"source"];
  GWDestinationKind kind = GWDestinationLocal;

  switch ([[self class] classOfFilesystemType: type source: source])
    {
      case GWFilesystemNetwork:
        kind = GWDestinationNetwork;
        break;
      case GWFilesystemVirtual:
        kind = GWDestinationLocal;
        break;
      case GWFilesystemDeviceBacked:
        {
          unsigned maj = [[m objectForKey: @"major"] unsignedIntValue];
          unsigned min = [[m objectForKey: @"minor"] unsignedIntValue];
          struct stat st;

          /* btrfs and fuseblk show an anonymous device in the mount table;
           * the device node they were mounted from is the real disk. */
          if (maj == 0 && [source hasPrefix: @"/dev/"]
              && stat([source fileSystemRepresentation], &st) == 0
              && S_ISBLK(st.st_mode))
            {
              maj = major(st.st_rdev);
              min = minor(st.st_rdev);
            }
          if (maj != 0 && [self isRemovableDeviceMajor: maj minor: min])
            {
              kind = GWDestinationRemovable;
            }
        }
        break;
    }
  return [GWDestination destinationWithKind: kind
                             filesystemType: type
                                 mountPoint: [m objectForKey: @"mountPoint"]];
}

- (GWDestination *)destinationForDirectory:(NSString *)directory
{
  const char *path = [directory fileSystemRepresentation];
  long mountID = -1;
  unsigned devMajor = 0;
  unsigned devMinor = 0;
  NSString *key;
  GWDestination *d;
  NSString *text;
  NSEnumerator *en;
  NSString *line;
  NSDictionary *found = nil;

#if defined(STATX_MNT_ID)
  struct statx stx;

  /* DONT_SYNC: answering from what the kernel has, a network server is
   * never asked just to find out where the copy goes. */
  if (statx(AT_FDCWD, path, AT_STATX_DONT_SYNC | AT_NO_AUTOMOUNT,
            STATX_MNT_ID, &stx) == 0)
    {
      if (stx.stx_mask & STATX_MNT_ID)
        {
          mountID = (long)stx.stx_mnt_id;
        }
      devMajor = stx.stx_dev_major;
      devMinor = stx.stx_dev_minor;
    }
  else
#endif
    {
      struct stat st;

      if (stat(path, &st) != 0)
        {
          return [GWDestination destinationWithKind:
                                  overriddenKind(GWDestinationLocal)
                                     filesystemType: nil
                                         mountPoint: directory];
        }
      devMajor = major(st.st_dev);
      devMinor = minor(st.st_dev);
    }

  key = [NSString stringWithFormat: @"%ld/%u:%u", mountID, devMajor, devMinor];
  [_lock lock];
  d = RETAIN([_destinationByMount objectForKey: key]);
  [_lock unlock];
  if (d == nil)
    {
      text = [NSString stringWithContentsOfFile: _mountInfoPath];
      en = [[text componentsSeparatedByString: @"\n"] objectEnumerator];
      while ((line = [en nextObject]) != nil)
        {
          NSDictionary *m = [[self class] parseMountInfoLine: line];

          if (m == nil)
            {
              continue;
            }
          if (mountID >= 0)
            {
              if ([[m objectForKey: @"mountID"] longValue] == mountID)
                {
                  found = m;
                  break;
                }
            }
          else if ([[m objectForKey: @"major"] unsignedIntValue] == devMajor
                   && [[m objectForKey: @"minor"] unsignedIntValue] == devMinor)
            {
              /* The last of several mounts of one device is the one on
               * top. */
              found = m;
            }
        }
      if (found == nil)
        {
          d = RETAIN([GWDestination destinationWithKind: GWDestinationLocal
                                         filesystemType: nil
                                             mountPoint: directory]);
        }
      else
        {
          d = RETAIN([self _destinationForMount: found]);
          [_lock lock];
          [_destinationByMount setObject: d forKey: key];
          [_lock unlock];
        }
    }
  AUTORELEASE(d);
  if (overriddenKind([d kind]) != [d kind])
    {
      return [GWDestination destinationWithKind: overriddenKind([d kind])
                                 filesystemType: [d filesystemType]
                                     mountPoint: [d mountPoint]];
    }
  return d;
}

#elif defined(GW_BSD_MOUNTS)

static NSString *
daFlagsOfDisk(NSString *disk)
{
#if defined(__FreeBSD__)
  NSString *unit = [disk substringFromIndex: 2];
  NSString *name = [NSString stringWithFormat: @"kern.cam.da.%@.flags", unit];
  char buf[256];
  size_t len = sizeof(buf) - 1;

  if (sysctlbyname([name UTF8String], buf, &len, NULL, 0) != 0)
    {
      return nil;
    }
  buf[len] = 0;
  return [NSString stringWithUTF8String: buf];
#else
  return nil;
#endif
}

- (GWDestination *)destinationForDirectory:(NSString *)directory
{
  gw_mount_t *mnts = NULL;
  int count;
  int i;
  NSMutableArray *mounts = [NSMutableArray array];
  NSString *real = realPath(directory);
  NSDictionary *m;
  NSString *type;
  NSString *source;
  NSString *mountPoint;
  GWDestination *d;
  GWDestinationKind kind = GWDestinationLocal;

  /* MNT_NOWAIT: the kernel's copy of the mount table, so no NFS server
   * is asked. */
  count = getmntinfo(&mnts, MNT_NOWAIT);
  for (i = 0; i < count; i++)
    {
      [mounts addObject: @{
        @"mountPoint": [NSString stringWithUTF8String: mnts[i].f_mntonname],
        @"type": [NSString stringWithUTF8String: mnts[i].f_fstypename],
        @"source": [NSString stringWithUTF8String: mnts[i].f_mntfromname],
        @"local": [NSNumber numberWithBool:
#if defined(MNT_LOCAL)
                    (mnts[i].gw_mount_flags & MNT_LOCAL) != 0
#else
                    YES
#endif
                  ] }];
    }
  m = [[self class] mountForPath: (real != nil ? real : directory)
                        inMounts: mounts];
  if (m == nil)
    {
      return [GWDestination destinationWithKind:
                              overriddenKind(GWDestinationLocal)
                                 filesystemType: nil
                                     mountPoint: directory];
    }
  mountPoint = [m objectForKey: @"mountPoint"];
  [_lock lock];
  d = RETAIN([_destinationByMount objectForKey: mountPoint]);
  [_lock unlock];
  if (d == nil
      || ![[d filesystemType] isEqual: [m objectForKey: @"type"]])
    {
      RELEASE(d);
      type = [m objectForKey: @"type"];
      source = [m objectForKey: @"source"];
      switch ([[self class] classOfFilesystemType: type source: source])
        {
          case GWFilesystemNetwork:
            kind = GWDestinationNetwork;
            break;
          case GWFilesystemVirtual:
            kind = GWDestinationLocal;
            break;
          case GWFilesystemDeviceBacked:
            if (![[m objectForKey: @"local"] boolValue])
              {
                kind = GWDestinationNetwork;
              }
            else
              {
                NSString *t = [type lowercaseString];
                NSString *disk = [[self class] diskNameOfMountSource: source];

                /* FAT and exFAT sit on sticks and cards; fixed disks of a
                 * BSD system practically never carry them. */
                if ([t isEqual: @"msdosfs"] || [t isEqual: @"msdos"]
                    || [t isEqual: @"exfat"] || [t isEqual: @"fusefs.exfat"]
                    || (disk != nil
                        && [[self class] isRemovableBSDDisk: disk
                                                    daFlags:
                                                      daFlagsOfDisk(disk)]))
                  {
                    kind = GWDestinationRemovable;
                  }
              }
            break;
        }
      d = RETAIN([GWDestination destinationWithKind: kind
                                     filesystemType: type
                                         mountPoint: mountPoint]);
      [_lock lock];
      [_destinationByMount setObject: d forKey: mountPoint];
      [_lock unlock];
    }
  AUTORELEASE(d);
  if (overriddenKind([d kind]) != [d kind])
    {
      return [GWDestination destinationWithKind: overriddenKind([d kind])
                                 filesystemType: [d filesystemType]
                                     mountPoint: [d mountPoint]];
    }
  return d;
}

#else

- (GWDestination *)destinationForDirectory:(NSString *)directory
{
  return [GWDestination destinationWithKind: overriddenKind(GWDestinationLocal)
                             filesystemType: nil
                                 mountPoint: directory];
}

#endif

@end
