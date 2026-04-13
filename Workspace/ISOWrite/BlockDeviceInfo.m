/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "BlockDeviceInfo.h"
#import <sys/stat.h>
#import <sys/param.h>
#if defined(__FreeBSD__) || defined(__OpenBSD__) || defined(__NetBSD__) || defined(__DragonFly__)
#import <sys/mount.h>
#endif
#if defined(__has_include)
# if __has_include(<sys/sysmacros.h>)
#  import <sys/sysmacros.h>
# else
#  import <sys/types.h>
#  import <sys/param.h>
# endif
#else
# import <sys/types.h>
# import <sys/param.h>
#endif
#import <sys/ioctl.h>
#ifdef __linux__
#import <linux/fs.h>
#endif
#if defined(__FreeBSD__) || defined(__DragonFly__)
#import <sys/disk.h>
#import <sys/sysctl.h>
#endif
#import <fcntl.h>
#import <unistd.h>
#import <errno.h>

@implementation PartitionInfo

@synthesize devicePath = _devicePath;
@synthesize label = _label;
@synthesize fsType = _fsType;
@synthesize mountPoint = _mountPoint;
@synthesize size = _size;
@synthesize partitionNumber = _partitionNumber;
@synthesize isMounted = _isMounted;

- (void)dealloc
{
  [_devicePath release];
  [_label release];
  [_fsType release];
  [_mountPoint release];
  [super dealloc];
}

- (NSString *)sizeDescription
{
  if (_size >= 1000000000000ULL) {
    return [NSString stringWithFormat:@"%.1f TB", (double)_size / 1000000000000.0];
  } else if (_size >= 1000000000ULL) {
    return [NSString stringWithFormat:@"%.1f GB", (double)_size / 1000000000.0];
  } else if (_size >= 1000000ULL) {
    return [NSString stringWithFormat:@"%.1f MB", (double)_size / 1000000.0];
  } else if (_size >= 1000ULL) {
    return [NSString stringWithFormat:@"%.1f KB", (double)_size / 1000.0];
  }
  return [NSString stringWithFormat:@"%llu bytes", _size];
}

- (NSComparisonResult)gw_partitionSortCompare:(PartitionInfo *)other
{
  if (!other) {
    return NSOrderedDescending;
  }

  if (_partitionNumber < other.partitionNumber) {
    return NSOrderedAscending;
  }
  if (_partitionNumber > other.partitionNumber) {
    return NSOrderedDescending;
  }

  if (_devicePath && other.devicePath) {
    return [_devicePath compare:other.devicePath];
  }
  if (_devicePath) {
    return NSOrderedDescending;
  }
  if (other.devicePath) {
    return NSOrderedAscending;
  }

  return NSOrderedSame;
}

@end


@implementation BlockDeviceInfo

+ (NSString *)normalizedMountPath:(NSString *)path
{
  if (!path || [path length] == 0) {
    return nil;
  }

  NSString *normalized = [path stringByStandardizingPath];
  if ([normalized length] > 1 && [normalized hasSuffix:@"/"]) {
    normalized = [normalized substringToIndex:([normalized length] - 1)];
  }

  return normalized;
}

+ (NSString *)unescapeMountPathField:(NSString *)mountField
{
  if (!mountField) {
    return nil;
  }

  NSString *value = [mountField stringByReplacingOccurrencesOfString:@"\\040" withString:@" "];
  value = [value stringByReplacingOccurrencesOfString:@"\\011" withString:@"\t"];
  value = [value stringByReplacingOccurrencesOfString:@"\\012" withString:@"\n"];
  value = [value stringByReplacingOccurrencesOfString:@"\\134" withString:@"\\"];
  return value;
}

@synthesize devicePath = _devicePath;
@synthesize deviceName = _deviceName;
@synthesize model = _model;
@synthesize vendor = _vendor;
@synthesize serial = _serial;
@synthesize size = _size;
@synthesize partitionTableType = _partitionTableType;
@synthesize partitions = _partitions;
@synthesize isRemovable = _isRemovable;
@synthesize isReadOnly = _isReadOnly;
@synthesize isSystemDisk = _isSystemDisk;
@synthesize isValid = _isValid;

- (void)dealloc
{
  [_devicePath release];
  [_deviceName release];
  [_model release];
  [_vendor release];
  [_serial release];
  [_partitions release];
  [super dealloc];
}

+ (instancetype)infoForDevicePath:(NSString *)devicePath
{
  if (!devicePath || [devicePath length] == 0) {
    return nil;
  }
  
  BlockDeviceInfo *info = [[[BlockDeviceInfo alloc] init] autorelease];
  if (![info populateFromDevicePath:devicePath]) {
    return nil;
  }
  return info;
}

+ (instancetype)infoForMountPoint:(NSString *)mountPoint
{
  if (!mountPoint || [mountPoint length] == 0) {
    return nil;
  }
  
  /* Find the device for this mount point using /proc/mounts */
  NSString *devicePath = [self devicePathForMountPoint:mountPoint];
  if (!devicePath) {
    return nil;
  }
  
  /* Get the parent device if this is a partition */
  NSString *rawDevice = [self parentDeviceForPartition:devicePath];
  if (!rawDevice) {
    rawDevice = devicePath;
  }
  
  return [self infoForDevicePath:rawDevice];
}

+ (NSString *)devicePathForMountPoint:(NSString *)mountPoint
{
  NSString *normalizedMountPoint = [self normalizedMountPath:mountPoint];
  if (!normalizedMountPoint) {
    return nil;
  }

  /* Linux: prefer /proc/self/mountinfo (more reliable than /proc/mounts). */
  NSError *error = nil;
  NSString *mountInfo = [NSString stringWithContentsOfFile:@"/proc/self/mountinfo"
                                                  encoding:NSUTF8StringEncoding
                                                     error:&error];
  if (mountInfo && [mountInfo length] > 0) {
    NSArray *lines = [mountInfo componentsSeparatedByString:@"\n"];
    for (NSString *line in lines) {
      if ([line length] == 0) {
        continue;
      }

      NSRange sep = [line rangeOfString:@" - "];
      if (sep.location == NSNotFound) {
        continue;
      }

      NSString *left = [line substringToIndex:sep.location];
      NSString *right = [line substringFromIndex:(sep.location + 3)];

      NSArray *leftParts = [left componentsSeparatedByString:@" "];
      NSArray *rightParts = [right componentsSeparatedByString:@" "];
      if ([leftParts count] < 5 || [rightParts count] < 2) {
        continue;
      }

      NSString *mount = [self unescapeMountPathField:[leftParts objectAtIndex:4]];
      mount = [self normalizedMountPath:mount];
      if (![mount isEqualToString:normalizedMountPoint]) {
        continue;
      }

      NSString *source = [rightParts objectAtIndex:1];
      if ([source hasPrefix:@"/dev/"]) {
        return source;
      }
    }
  }

  /* Linux fallback: /proc/mounts */
  NSString *mounts = [NSString stringWithContentsOfFile:@"/proc/mounts"
                                               encoding:NSUTF8StringEncoding
                                                  error:&error];
  if (mounts && [mounts length] > 0) {
    NSArray *lines = [mounts componentsSeparatedByString:@"\n"];
    for (NSString *line in lines) {
      NSArray *parts = [line componentsSeparatedByString:@" "];
      if ([parts count] >= 2) {
        NSString *device = [parts objectAtIndex:0];
        NSString *mount = [self unescapeMountPathField:[parts objectAtIndex:1]];
        mount = [self normalizedMountPath:mount];

        if ([device hasPrefix:@"/dev/"] && [mount isEqualToString:normalizedMountPoint]) {
          return device;
        }
      }
    }
  }

#if defined(__FreeBSD__) || defined(__OpenBSD__) || defined(__NetBSD__) || defined(__DragonFly__)
  {
    struct statfs *mntbuf = NULL;
    int mountsCount = getmntinfo(&mntbuf, MNT_NOWAIT);
    if (mountsCount > 0 && mntbuf != NULL) {
      NSFileManager *fm = [NSFileManager defaultManager];
      int i;
      for (i = 0; i < mountsCount; i++) {
        NSString *mount = [fm stringWithFileSystemRepresentation:mntbuf[i].f_mntonname
                                                          length:strlen(mntbuf[i].f_mntonname)];
        NSString *from = [fm stringWithFileSystemRepresentation:mntbuf[i].f_mntfromname
                                                         length:strlen(mntbuf[i].f_mntfromname)];
        mount = [self normalizedMountPath:mount];
        if ([mount isEqualToString:normalizedMountPoint] && [from hasPrefix:@"/dev/"]) {
          return from;
        }
      }
    }
  }
#endif

  NSDebugLLog(@"gwspace", @"BlockDeviceInfo: Could not resolve device for mount point %@", normalizedMountPoint);
  return nil;
}

+ (NSString *)parentDeviceForPartition:(NSString *)partitionPath
{
  if (!partitionPath || ![partitionPath hasPrefix:@"/dev/"]) {
    return nil;
  }
  
  NSString *deviceName = [partitionPath lastPathComponent];

  /* FreeBSD/DragonFly style slices: da0s1 -> da0, mmcsd0s1 -> mmcsd0
     Also handle BSD disklabel partitions like da0s1a -> da0 */
  NSRange sRange = [deviceName rangeOfString:@"s" options:NSBackwardsSearch];
  if (sRange.location != NSNotFound && sRange.location > 0) {
    NSString *afterS = [deviceName substringFromIndex:(sRange.location + 1)];
    if ([afterS length] > 0) {
      NSCharacterSet *digits = [NSCharacterSet decimalDigitCharacterSet];
      NSUInteger idx = 0;
      while (idx < [afterS length] && [digits characterIsMember:[afterS characterAtIndex:idx]]) {
        idx++;
      }

      BOOL hasDigits = (idx > 0);
      BOOL suffixOK = NO;
      if (hasDigits) {
        if (idx == [afterS length]) {
          suffixOK = YES;
        } else if (idx + 1 == [afterS length]) {
          unichar c = [afterS characterAtIndex:idx];
          if (c >= 'a' && c <= 'h') {
            suffixOK = YES;
          }
        }
      }

      if (suffixOK) {
        NSString *parent = [deviceName substringToIndex:sRange.location];
        if ([parent length] > 0) {
          return [@"/dev/" stringByAppendingString:parent];
        }
      }
    }
  }

  /* BSD partition style: ada0p2 -> ada0 */
  NSRange bsdPRange = [deviceName rangeOfString:@"p" options:NSBackwardsSearch];
  if (bsdPRange.location != NSNotFound && bsdPRange.location > 0) {
    NSString *afterP = [deviceName substringFromIndex:(bsdPRange.location + 1)];
    NSCharacterSet *nonDigits = [[NSCharacterSet decimalDigitCharacterSet] invertedSet];
    if ([afterP length] > 0 && [afterP rangeOfCharacterFromSet:nonDigits].location == NSNotFound) {
      NSString *parent = [deviceName substringToIndex:bsdPRange.location];
      if ([parent length] > 0) {
        return [@"/dev/" stringByAppendingString:parent];
      }
    }
  }
  
  /* Handle NVMe, MMC, and pmem devices: nvme0n1p1 -> nvme0n1, mmcblk0p1 -> mmcblk0 */
  if ([deviceName hasPrefix:@"nvme"] || [deviceName hasPrefix:@"mmcblk"] || [deviceName hasPrefix:@"pmem"]) {
    NSRange pRange = [deviceName rangeOfString:@"p" options:NSBackwardsSearch];
    if (pRange.location != NSNotFound && pRange.location > 0) {
      /* Check if what follows 'p' is a number */
      NSString *afterP = [deviceName substringFromIndex:pRange.location + 1];
      NSCharacterSet *nonDigits = [[NSCharacterSet decimalDigitCharacterSet] invertedSet];
      if ([afterP rangeOfCharacterFromSet:nonDigits].location == NSNotFound) {
        NSString *parent = [deviceName substringToIndex:pRange.location];
        return [@"/dev/" stringByAppendingString:parent];
      }
    }
    return nil; /* Already a raw device */
  }
  
  /* Handle standard devices: sdb1 -> sdb, vda2 -> vda */
  NSMutableString *parent = [NSMutableString stringWithString:deviceName];
  while ([parent length] > 0) {
    unichar lastChar = [parent characterAtIndex:[parent length] - 1];
    if (lastChar >= '0' && lastChar <= '9') {
      [parent deleteCharactersInRange:NSMakeRange([parent length] - 1, 1)];
    } else {
      break;
    }
  }
  
  if ([parent length] < [deviceName length]) {
    NSString *candidate = [@"/dev/" stringByAppendingString:parent];
    struct stat st;
    if (stat([candidate UTF8String], &st) == 0) {
#ifdef __linux__
      if (S_ISBLK(st.st_mode)) {
        return candidate;
      }
#else
      if (S_ISBLK(st.st_mode) || S_ISCHR(st.st_mode)) {
        return candidate;
      }
#endif
    }
  }
  
  return nil; /* Already a raw device */
}

+ (BOOL)isRawBlockDevice:(NSString *)devicePath
{
  if (!devicePath || ![devicePath hasPrefix:@"/dev/"]) {
    return NO;
  }
  
  struct stat st;
  if (stat([devicePath UTF8String], &st) != 0) {
    return NO;
  }
  
  #ifdef __linux__
  if (!S_ISBLK(st.st_mode)) {
    return NO;
  }
  #else
  if (!S_ISBLK(st.st_mode) && !S_ISCHR(st.st_mode)) {
    return NO;
  }
  #endif
  
  /* Check if this is a partition or raw device */
  return [self parentDeviceForPartition:devicePath] == nil;
}

+ (BOOL)isPartition:(NSString *)devicePath
{
  if (!devicePath || ![devicePath hasPrefix:@"/dev/"]) {
    return NO;
  }
  
  struct stat st;
  if (stat([devicePath UTF8String], &st) != 0) {
    return NO;
  }
  
  #ifdef __linux__
  if (!S_ISBLK(st.st_mode)) {
    return NO;
  }
  #else
  if (!S_ISBLK(st.st_mode) && !S_ISCHR(st.st_mode)) {
    return NO;
  }
  #endif
  
  return [self parentDeviceForPartition:devicePath] != nil;
}

- (id)init
{
  self = [super init];
  if (self) {
    _partitions = [[NSMutableArray alloc] init];
    _partitionTableType = PartitionTableTypeUnknown;
    _isValid = NO;
  }
  return self;
}

- (BOOL)populateFromDevicePath:(NSString *)devicePath
{
  struct stat st;
  if (stat([devicePath UTF8String], &st) != 0) {
    NSDebugLLog(@"gwspace", @"BlockDeviceInfo: Cannot stat device %@: %s", devicePath, strerror(errno));
    return NO;
  }
  
#ifdef __linux__
  if (!S_ISBLK(st.st_mode)) {
    NSDebugLLog(@"gwspace", @"BlockDeviceInfo: %@ is not a block device", devicePath);
    return NO;
  }
#else
  /* On BSD, device nodes may be character devices */
  if (!S_ISBLK(st.st_mode) && !S_ISCHR(st.st_mode)) {
    NSDebugLLog(@"gwspace", @"BlockDeviceInfo: %@ is not a block or character device", devicePath);
    return NO;
  }
#endif
  
  _devicePath = [devicePath copy];
  _deviceName = [[devicePath lastPathComponent] copy];
  
  [self readDeviceSize];
  [self readSysfsAttributes];
  [self readPartitionTable];
  [self checkSystemDisk];
  [self readMountedPartitions];
  
  _isValid = YES;
  return YES;
}

- (void)readDeviceSize
{
  int fd = open([_devicePath UTF8String], O_RDONLY);
  if (fd < 0) {
    NSDebugLLog(@"gwspace", @"BlockDeviceInfo: Cannot open %@ for size query: %s", _devicePath, strerror(errno));
    /* On BSD, users may not have direct device node access; try sysctl fallback. */
#if defined(__FreeBSD__) || defined(__DragonFly__)
    NSString *devName = _deviceName;
    if (devName && [devName length] > 0) {
      NSUInteger idx = 0;
      while (idx < [devName length]) {
        unichar c = [devName characterAtIndex:idx];
        if (c >= '0' && c <= '9') {
          break;
        }
        idx++;
      }
      if (idx > 0 && idx < [devName length]) {
        NSString *prefix = [devName substringToIndex:idx];
        NSString *unit = [devName substringFromIndex:idx];
        NSString *oid = [NSString stringWithFormat:@"dev.%@.%@.mediasize", prefix, unit];
        uint64_t mediasize = 0;
        size_t len = sizeof(mediasize);
        if (sysctlbyname([oid UTF8String], &mediasize, &len, NULL, 0) == 0 && len == sizeof(mediasize)) {
          _size = (unsigned long long)mediasize;
          NSDebugLLog(@"gwspace", @"BlockDeviceInfo: Size via sysctl %@ = %llu", oid, _size);
        } else {
          NSDebugLLog(@"gwspace", @"BlockDeviceInfo: sysctl size fallback failed for %@: %s", oid, strerror(errno));
        }
      }
    }
#endif
    return;
  }
  
#ifdef __linux__
  unsigned long long size = 0;
  if (ioctl(fd, BLKGETSIZE64, &size) == 0) {
    _size = size;
  } else {
    NSDebugLLog(@"gwspace", @"BlockDeviceInfo: BLKGETSIZE64 failed for %@: %s", _devicePath, strerror(errno));
  }
#else
  /* BSD: Use DIOCGMEDIASIZE or fall back to stat */
  #ifdef DIOCGMEDIASIZE
  unsigned long long size = 0;
  if (ioctl(fd, DIOCGMEDIASIZE, &size) == 0) {
    _size = size;
  } else {
    struct stat st;
    if (fstat(fd, &st) == 0) {
      _size = st.st_size;
    } else {
      NSDebugLLog(@"gwspace", @"BlockDeviceInfo: Cannot get device size for %@: %s", _devicePath, strerror(errno));
    }
  }
  #else
  /* Fallback to stat for size */
  struct stat st;
  if (fstat(fd, &st) == 0) {
    _size = st.st_size;
  }
  #endif
#endif
  
  close(fd);
}

- (void)readSysfsAttributes
{
#ifdef __linux__
  NSString *sysBlockPath = [NSString stringWithFormat:@"/sys/block/%@", _deviceName];
  NSFileManager *fm = [NSFileManager defaultManager];
  
  /* Check if removable */
  NSString *removablePath = [sysBlockPath stringByAppendingPathComponent:@"removable"];
  if ([fm fileExistsAtPath:removablePath]) {
    NSString *content = [NSString stringWithContentsOfFile:removablePath
                                                  encoding:NSUTF8StringEncoding
                                                     error:nil];
    _isRemovable = [content intValue] != 0;
  }
  
  /* Check if read-only */
  NSString *roPath = [sysBlockPath stringByAppendingPathComponent:@"ro"];
  if ([fm fileExistsAtPath:roPath]) {
    NSString *content = [NSString stringWithContentsOfFile:roPath
                                                  encoding:NSUTF8StringEncoding
                                                     error:nil];
    _isReadOnly = [content intValue] != 0;
  }
  
  /* Read device model and vendor */
  NSString *devicePath = [sysBlockPath stringByAppendingPathComponent:@"device"];
  
  NSString *modelPath = [devicePath stringByAppendingPathComponent:@"model"];
  if ([fm fileExistsAtPath:modelPath]) {
    NSString *content = [NSString stringWithContentsOfFile:modelPath
                                                  encoding:NSUTF8StringEncoding
                                                     error:nil];
    _model = [[content stringByTrimmingCharactersInSet:
               [NSCharacterSet whitespaceAndNewlineCharacterSet]] copy];
  }
  
  NSString *vendorPath = [devicePath stringByAppendingPathComponent:@"vendor"];
  if ([fm fileExistsAtPath:vendorPath]) {
    NSString *content = [NSString stringWithContentsOfFile:vendorPath
                                                  encoding:NSUTF8StringEncoding
                                                     error:nil];
    _vendor = [[content stringByTrimmingCharactersInSet:
                [NSCharacterSet whitespaceAndNewlineCharacterSet]] copy];
  }
#else
  /* BSD: Device attributes not available via sysfs, would need sysctl or ioctl */
  _isRemovable = NO;  /* Conservative default */
  _isReadOnly = NO;
#endif
}

- (void)readPartitionTable
{
#ifdef __linux__
  /* Use lsblk to get partition table type and partitions */
  NSTask *task = [[NSTask alloc] init];
  [task setLaunchPath:@"/bin/lsblk"];
  [task setArguments:@[@"-J", @"-o", @"NAME,SIZE,TYPE,FSTYPE,LABEL,MOUNTPOINT,PTTYPE", _devicePath]];
  
  NSPipe *outPipe = [NSPipe pipe];
  [task setStandardOutput:outPipe];
  [task setStandardError:[NSPipe pipe]];
  
  @try {
    [task launch];
    [task waitUntilExit];
  } @catch (NSException *e) {
    NSDebugLLog(@"gwspace", @"BlockDeviceInfo: lsblk failed: %@", e);
    [task release];
    return;
  }
  
  if ([task terminationStatus] != 0) {
    [task release];
    return;
  }
  
  NSData *data = [[outPipe fileHandleForReading] readDataToEndOfFile];
  [task release];
  
  if (!data || [data length] == 0) {
    return;
  }
  
  NSError *error = nil;
  NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
  if (error || !json) {
    NSDebugLLog(@"gwspace", @"BlockDeviceInfo: Failed to parse lsblk JSON: %@", error);
    return;
  }
  
  NSArray *blockdevices = [json objectForKey:@"blockdevices"];
  if (![blockdevices isKindOfClass:[NSArray class]] || [blockdevices count] == 0) {
    return;
  }
  
  NSDictionary *device = [blockdevices objectAtIndex:0];
  
  /* Parse partition table type */
  NSString *pttype = [device objectForKey:@"pttype"];
  if ([pttype isEqualToString:@"gpt"]) {
    _partitionTableType = PartitionTableTypeGPT;
  } else if ([pttype isEqualToString:@"dos"]) {
    _partitionTableType = PartitionTableTypeMBR;
  } else if (pttype == nil || [pttype isEqual:[NSNull null]]) {
    _partitionTableType = PartitionTableTypeNone;
  }
  
  /* Parse partitions (children) */
  NSArray *children = [device objectForKey:@"children"];
  if ([children isKindOfClass:[NSArray class]]) {
    NSUInteger partNum = 1;
    for (NSDictionary *child in children) {
      if (![[child objectForKey:@"type"] isEqualToString:@"part"]) {
        continue;
      }
      
      PartitionInfo *part = [[PartitionInfo alloc] init];
      
      NSString *name = [child objectForKey:@"name"];
      part.devicePath = [NSString stringWithFormat:@"/dev/%@", name];
      part.partitionNumber = partNum++;
      
      id label = [child objectForKey:@"label"];
      if (label && ![label isEqual:[NSNull null]]) {
        part.label = label;
      }
      
      id fstype = [child objectForKey:@"fstype"];
      if (fstype && ![fstype isEqual:[NSNull null]]) {
        part.fsType = fstype;
      }
      
      id mountpoint = [child objectForKey:@"mountpoint"];
      if (mountpoint && ![mountpoint isEqual:[NSNull null]]) {
        part.mountPoint = mountpoint;
        part.isMounted = YES;
      }
      
      /* Parse size from lsblk (comes as string like "10G") */
      id sizeStr = [child objectForKey:@"size"];
      if (sizeStr && [sizeStr isKindOfClass:[NSString class]]) {
        part.size = [self parseSizeString:sizeStr];
      }
      
      [_partitions addObject:part];
      [part release];
    }
  }
#else
  /* BSD: Populate partitions from /dev scan and mount table.
     We avoid requiring raw device reads (which may need privileges). */
  NSFileManager *fm = [NSFileManager defaultManager];
  NSMutableDictionary *byPath = [NSMutableDictionary dictionary];
  BOOL sawSliceStyle = NO;
  BOOL sawGPTStyle = NO;

  NSArray *devEntries = [fm contentsOfDirectoryAtPath:@"/dev" error:nil];
  for (NSString *name in devEntries) {
    if (![name hasPrefix:_deviceName]) {
      continue;
    }

    NSString *fullPath = [@"/dev" stringByAppendingPathComponent:name];
    NSString *parent = [[self class] parentDeviceForPartition:fullPath];
    if (!parent || ![parent isEqualToString:_devicePath]) {
      continue;
    }

    struct stat st;
    if (stat([fullPath UTF8String], &st) != 0) {
      continue;
    }
    if (!S_ISBLK(st.st_mode) && !S_ISCHR(st.st_mode)) {
      continue;
    }

    PartitionInfo *part = [[PartitionInfo alloc] init];
    part.devicePath = fullPath;
    part.partitionNumber = [[self class] bsdPartitionNumberForDeviceName:name];

    if ([name rangeOfString:@"p"].location != NSNotFound) {
      sawGPTStyle = YES;
    }
    if ([name rangeOfString:@"s"].location != NSNotFound) {
      sawSliceStyle = YES;
    }

    [byPath setObject:part forKey:fullPath];
    [part release];
  }

  /* Add mounted partitions that match this device but were not found in /dev scan. */
  struct statfs *mntbuf = NULL;
  int mntCount = getmntinfo(&mntbuf, MNT_NOWAIT);
  if (mntCount > 0 && mntbuf) {
    for (int i = 0; i < mntCount; i++) {
      const char *fromC = mntbuf[i].f_mntfromname;
      const char *toC = mntbuf[i].f_mntonname;
      if (!fromC || !toC) {
        continue;
      }

      NSString *from = [NSString stringWithUTF8String:fromC];
      if (!from || ![from hasPrefix:@"/dev/"]) {
        continue;
      }

      NSString *parent = [[self class] parentDeviceForPartition:from];
      if (!parent || ![parent isEqualToString:_devicePath]) {
        continue;
      }

      PartitionInfo *part = [byPath objectForKey:from];
      if (!part) {
        part = [[PartitionInfo alloc] init];
        part.devicePath = from;
        part.partitionNumber = [[self class] bsdPartitionNumberForDeviceName:[from lastPathComponent]];
        [byPath setObject:part forKey:from];
        [part release];
      }

      NSString *mountPoint = [NSString stringWithUTF8String:toC];
      if (mountPoint && [mountPoint length] > 0) {
        part.mountPoint = mountPoint;
        part.isMounted = YES;
      }
    }
  }

  /* Partition table heuristic based on naming */
  if (sawGPTStyle && !sawSliceStyle) {
    _partitionTableType = PartitionTableTypeGPT;
  } else if (sawSliceStyle && !sawGPTStyle) {
    _partitionTableType = PartitionTableTypeMBR;
  } else if ([byPath count] == 0) {
    _partitionTableType = PartitionTableTypeNone;
  } else {
    _partitionTableType = PartitionTableTypeUnknown;
  }

  /* Sort partitions by partitionNumber then devicePath (avoid blocks for compatibility) */
  NSMutableArray *sorted = [NSMutableArray arrayWithArray:[byPath allValues]];
  [sorted sortUsingSelector:@selector(gw_partitionSortCompare:)];

  [_partitions removeAllObjects];
  [_partitions addObjectsFromArray:sorted];
#endif
}

#ifndef __linux__
+ (NSUInteger)bsdPartitionNumberForDeviceName:(NSString *)name
{
  if (!name || [name length] == 0) {
    return 0;
  }

  /* Look for last 's' or 'p' and parse digits following it. */
  NSRange sRange = [name rangeOfString:@"s" options:NSBackwardsSearch];
  NSRange pRange = [name rangeOfString:@"p" options:NSBackwardsSearch];
  NSUInteger start = NSNotFound;
  if (sRange.location != NSNotFound && sRange.location + 1 < [name length]) {
    start = sRange.location + 1;
  }
  if (pRange.location != NSNotFound && pRange.location + 1 < [name length]) {
    if (start == NSNotFound || pRange.location > sRange.location) {
      start = pRange.location + 1;
    }
  }

  if (start == NSNotFound) {
    return 0;
  }

  NSUInteger idx = start;
  NSCharacterSet *digits = [NSCharacterSet decimalDigitCharacterSet];
  while (idx < [name length] && [digits characterIsMember:[name characterAtIndex:idx]]) {
    idx++;
  }

  if (idx == start) {
    return 0;
  }

  NSString *numStr = [name substringWithRange:NSMakeRange(start, idx - start)];
  return (NSUInteger)[numStr integerValue];
}
#endif

- (unsigned long long)parseSizeString:(NSString *)sizeStr
{
  if (!sizeStr || [sizeStr length] == 0) {
    return 0;
  }
  
  NSScanner *scanner = [NSScanner scannerWithString:sizeStr];
  double value = 0;
  [scanner scanDouble:&value];
  
  NSString *unit = [[sizeStr substringFromIndex:[scanner scanLocation]] uppercaseString];
  unit = [unit stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
  
  if ([unit hasPrefix:@"T"]) {
    return (unsigned long long)(value * 1000000000000.0);
  } else if ([unit hasPrefix:@"G"]) {
    return (unsigned long long)(value * 1000000000.0);
  } else if ([unit hasPrefix:@"M"]) {
    return (unsigned long long)(value * 1000000.0);
  } else if ([unit hasPrefix:@"K"]) {
    return (unsigned long long)(value * 1000.0);
  }
  
  return (unsigned long long)value;
}

- (void)readMountedPartitions
{
#ifdef __linux__
  /* Update mount status from /proc/mounts */
  NSError *error = nil;
  NSString *mounts = [NSString stringWithContentsOfFile:@"/proc/mounts"
                                               encoding:NSUTF8StringEncoding
                                                  error:&error];
  if (error || !mounts) {
    return;
  }

  NSArray *lines = [mounts componentsSeparatedByString:@"\n"];

  for (PartitionInfo *part in _partitions) {
    for (NSString *line in lines) {
      NSArray *parts = [line componentsSeparatedByString:@" "];
      if ([parts count] >= 2) {
        NSString *device = [parts objectAtIndex:0];
        NSString *mount = [parts objectAtIndex:1];
        mount = [mount stringByReplacingOccurrencesOfString:@"\\040" withString:@" "];

        if ([device isEqualToString:part.devicePath]) {
          part.mountPoint = mount;
          part.isMounted = YES;
          break;
        }
      }
    }
  }
#else
  struct statfs *mntbuf = NULL;
  int mntCount = getmntinfo(&mntbuf, MNT_NOWAIT);
  if (mntCount <= 0 || !mntbuf) {
    return;
  }

  for (PartitionInfo *part in _partitions) {
    for (int i = 0; i < mntCount; i++) {
      const char *fromC = mntbuf[i].f_mntfromname;
      const char *toC = mntbuf[i].f_mntonname;
      if (!fromC || !toC) {
        continue;
      }
      NSString *from = [NSString stringWithUTF8String:fromC];
      if (from && [from isEqualToString:part.devicePath]) {
        NSString *to = [NSString stringWithUTF8String:toC];
        part.mountPoint = to;
        part.isMounted = YES;
        break;
      }
    }
  }
#endif
}

- (void)checkSystemDisk
{
  /* Check if this device contains / or /boot */
  _isSystemDisk = NO;

#ifdef __linux__
  NSError *error = nil;
  NSString *mounts = [NSString stringWithContentsOfFile:@"/proc/mounts"
                                               encoding:NSUTF8StringEncoding
                                                  error:&error];
  if (error || !mounts) {
    return;
  }

  NSArray *lines = [mounts componentsSeparatedByString:@"\n"];

  for (NSString *line in lines) {
    NSArray *parts = [line componentsSeparatedByString:@" "];
    if ([parts count] >= 2) {
      NSString *device = [parts objectAtIndex:0];
      NSString *mount = [parts objectAtIndex:1];

      /* Check if device belongs to this block device */
      if ([device hasPrefix:_devicePath] ||
          [device hasPrefix:[NSString stringWithFormat:@"/dev/%@", _deviceName]]) {
        if ([mount isEqualToString:@"/"] || [mount isEqualToString:@"/boot"] ||
            [mount hasPrefix:@"/boot/"]) {
          _isSystemDisk = YES;
          return;
        }
      }
    }
  }

  /* Also check /proc/swaps for swap partitions on this device */
  NSString *swaps = [NSString stringWithContentsOfFile:@"/proc/swaps"
                                              encoding:NSUTF8StringEncoding
                                                 error:nil];
  if (swaps) {
    NSArray *swapLines = [swaps componentsSeparatedByString:@"\n"];
    for (NSString *line in swapLines) {
      if ([line hasPrefix:_devicePath] ||
          [line hasPrefix:[NSString stringWithFormat:@"/dev/%@", _deviceName]]) {
        _isSystemDisk = YES;
        return;
      }
    }
  }
#else
  struct statfs *mntbuf = NULL;
  int mntCount = getmntinfo(&mntbuf, MNT_NOWAIT);
  if (mntCount <= 0 || !mntbuf) {
    return;
  }

  for (int i = 0; i < mntCount; i++) {
    const char *fromC = mntbuf[i].f_mntfromname;
    const char *toC = mntbuf[i].f_mntonname;
    if (!fromC || !toC) {
      continue;
    }

    NSString *device = [NSString stringWithUTF8String:fromC];
    NSString *mount = [NSString stringWithUTF8String:toC];
    if (!device || !mount) {
      continue;
    }

    NSString *parent = [[self class] parentDeviceForPartition:device];
    BOOL belongs = (parent && [parent isEqualToString:_devicePath]);
    if (!belongs) {
      /* Some mounts may already be on the raw device (unusual), accept prefix match too. */
      belongs = ([device hasPrefix:_devicePath] || [device hasPrefix:[NSString stringWithFormat:@"/dev/%@", _deviceName]]);
    }

    if (belongs) {
      if ([mount isEqualToString:@"/"] || [mount isEqualToString:@"/boot"] || [mount hasPrefix:@"/boot/"]) {
        _isSystemDisk = YES;
        return;
      }
    }
  }
#endif
}

- (NSArray *)mountedPartitions
{
  NSMutableArray *mounted = [NSMutableArray array];
  for (PartitionInfo *part in _partitions) {
    if (part.isMounted) {
      [mounted addObject:part];
    }
  }
  return [[mounted copy] autorelease];
}

- (NSString *)sizeDescription
{
  if (_size >= 1000000000000ULL) {
    return [NSString stringWithFormat:@"%.1f TB", (double)_size / 1000000000000.0];
  } else if (_size >= 1000000000ULL) {
    return [NSString stringWithFormat:@"%.1f GB", (double)_size / 1000000000.0];
  } else if (_size >= 1000000ULL) {
    return [NSString stringWithFormat:@"%.1f MB", (double)_size / 1000000.0];
  } else if (_size >= 1000ULL) {
    return [NSString stringWithFormat:@"%.1f KB", (double)_size / 1000.0];
  }
  return [NSString stringWithFormat:@"%llu bytes", _size];
}

- (NSString *)partitionTableDescription
{
  switch (_partitionTableType) {
    case PartitionTableTypeGPT:
      return @"GPT";
    case PartitionTableTypeMBR:
      return @"MBR";
    case PartitionTableTypeNone:
      return @"None";
    default:
      return @"Unknown";
  }
}

- (NSString *)deviceSummary
{
  NSMutableString *summary = [NSMutableString string];
  
  [summary appendFormat:@"Device: %@\n", _devicePath];
  
  if (_vendor && [_vendor length] > 0) {
    [summary appendFormat:@"Vendor: %@\n", _vendor];
  }
  if (_model && [_model length] > 0) {
    [summary appendFormat:@"Model: %@\n", _model];
  }
  
  [summary appendFormat:@"Size: %@\n", [self sizeDescription]];
  [summary appendFormat:@"Partition Table: %@\n", [self partitionTableDescription]];
  [summary appendFormat:@"Partitions: %lu\n", (unsigned long)[_partitions count]];
  
  if (_isRemovable) {
    [summary appendString:@"Type: Removable\n"];
  }
  if (_isReadOnly) {
    [summary appendString:@"Status: Read-Only\n"];
  }
  if (_isSystemDisk) {
    [summary appendString:@"⚠️ Contains system partitions!\n"];
  }
  
  return [[summary copy] autorelease];
}

- (BOOL)hasPartitionsInUse
{
  for (PartitionInfo *part in _partitions) {
    if (part.isMounted) {
      return YES;
    }
  }
  return NO;
}

- (NSString *)safetyCheckForWriting
{
  if (_isReadOnly) {
    return @"Device is read-only and cannot be written to.";
  }
  
  if (_isSystemDisk) {
    return @"This device contains system partitions (/, /boot). Writing to it would destroy your operating system!";
  }
  
  /* Check if this is the root device by examining device major/minor */
  struct stat rootStat;
  if (stat("/", &rootStat) == 0) {
    struct stat devStat;
    if (stat([_devicePath UTF8String], &devStat) == 0) {
      /* Check if they share the same device major number (same disk) */
      if (major(rootStat.st_dev) == major(devStat.st_rdev)) {
        return @"This appears to be the system boot device. Writing to it would destroy your operating system!";
      }
    }
  }
  
  return nil; /* Safe to write */
}

@end
