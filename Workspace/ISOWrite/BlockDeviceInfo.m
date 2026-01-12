/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "BlockDeviceInfo.h"
#import <sys/stat.h>
#import <sys/sysmacros.h>
#import <sys/ioctl.h>
#import <linux/fs.h>
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

@end


@implementation BlockDeviceInfo

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
  NSError *error = nil;
  NSString *mounts = [NSString stringWithContentsOfFile:@"/proc/mounts"
                                               encoding:NSUTF8StringEncoding
                                                  error:&error];
  if (error || !mounts) {
    NSLog(@"BlockDeviceInfo: Failed to read /proc/mounts: %@", error);
    return nil;
  }
  
  NSArray *lines = [mounts componentsSeparatedByString:@"\n"];
  for (NSString *line in lines) {
    NSArray *parts = [line componentsSeparatedByString:@" "];
    if ([parts count] >= 2) {
      NSString *device = [parts objectAtIndex:0];
      NSString *mount = [parts objectAtIndex:1];
      
      /* Handle escaped spaces in mount points */
      mount = [mount stringByReplacingOccurrencesOfString:@"\\040" withString:@" "];
      
      if ([mount isEqualToString:mountPoint]) {
        return device;
      }
    }
  }
  
  return nil;
}

+ (NSString *)parentDeviceForPartition:(NSString *)partitionPath
{
  if (!partitionPath || ![partitionPath hasPrefix:@"/dev/"]) {
    return nil;
  }
  
  NSString *deviceName = [partitionPath lastPathComponent];
  
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
    return [@"/dev/" stringByAppendingString:parent];
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
  
  if (!S_ISBLK(st.st_mode)) {
    return NO;
  }
  
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
  
  if (!S_ISBLK(st.st_mode)) {
    return NO;
  }
  
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
    NSLog(@"BlockDeviceInfo: Cannot stat device %@: %s", devicePath, strerror(errno));
    return NO;
  }
  
#ifdef __linux__
  if (!S_ISBLK(st.st_mode)) {
    NSLog(@"BlockDeviceInfo: %@ is not a block device", devicePath);
    return NO;
  }
#else
  /* On BSD, device nodes may be character devices */
  if (!S_ISBLK(st.st_mode) && !S_ISCHR(st.st_mode)) {
    NSLog(@"BlockDeviceInfo: %@ is not a block or character device", devicePath);
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
    NSLog(@"BlockDeviceInfo: Cannot open %@ for size query: %s", _devicePath, strerror(errno));
    return;
  }
  
  unsigned long long size = 0;
#ifdef __linux__
  if (ioctl(fd, BLKGETSIZE64, &size) == 0) {
    _size = size;
  } else {
    NSLog(@"BlockDeviceInfo: BLKGETSIZE64 failed for %@: %s", _devicePath, strerror(errno));
  }
#else
  /* BSD: Use DIOCGMEDIASIZE or fall back to stat */
  #ifdef DIOCGMEDIASIZE
  if (ioctl(fd, DIOCGMEDIASIZE, &size) == 0) {
    _size = size;
  } else {
    struct stat st;
    if (fstat(fd, &st) == 0) {
      _size = st.st_size;
    } else {
      NSLog(@"BlockDeviceInfo: Cannot get device size for %@: %s", _devicePath, strerror(errno));
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
    NSLog(@"BlockDeviceInfo: lsblk failed: %@", e);
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
    NSLog(@"BlockDeviceInfo: Failed to parse lsblk JSON: %@", error);
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
  /* BSD: Would need to use gpart or fdisk to read partition table */
  NSLog(@"BlockDeviceInfo: Partition table reading not yet implemented for BSD\");
#endif
}

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
}

- (void)checkSystemDisk
{
  /* Check if this device contains / or /boot */
  _isSystemDisk = NO;
  
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
