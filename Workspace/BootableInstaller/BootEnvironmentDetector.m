/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "BootEnvironmentDetector.h"
#import <sys/utsname.h>
#import <sys/stat.h>
#import <sys/statvfs.h>
#import <unistd.h>

#pragma mark - BootEnvironmentInfo Implementation

@implementation BootEnvironmentInfo

@synthesize osType = _osType;
@synthesize firmwareType = _firmwareType;
@synthesize rootPartitionScheme = _rootPartitionScheme;
@synthesize cpuArchitecture = _cpuArchitecture;
@synthesize isRaspberryPi = _isRaspberryPi;
@synthesize piModel = _piModel;
@synthesize kernelVersion = _kernelVersion;
@synthesize osRelease = _osRelease;
@synthesize rootDevice = _rootDevice;
@synthesize espDevice = _espDevice;
@synthesize espMountPoint = _espMountPoint;
@synthesize bootDevice = _bootDevice;
@synthesize bootMountPoint = _bootMountPoint;

- (void)dealloc
{
  [_cpuArchitecture release];
  [_kernelVersion release];
  [_osRelease release];
  [_rootDevice release];
  [_espDevice release];
  [_espMountPoint release];
  [_bootDevice release];
  [_bootMountPoint release];
  [super dealloc];
}

- (NSString *)osTypeString
{
  switch (_osType) {
    case SourceOSTypeLinux:      return @"Linux";
    case SourceOSTypeFreeBSD:    return @"FreeBSD";
    case SourceOSTypeNetBSD:     return @"NetBSD";
    case SourceOSTypeOpenBSD:    return @"OpenBSD";
    case SourceOSTypeDragonFly:  return @"DragonFly BSD";
    default:                     return @"Unknown";
  }
}

- (NSString *)firmwareTypeString
{
  switch (_firmwareType) {
    case BootFirmwareTypeBIOS:          return @"BIOS";
    case BootFirmwareTypeUEFI:          return @"UEFI";
    case BootFirmwareTypeRaspberryPi:   return @"Raspberry Pi Firmware";
    case BootFirmwareTypeFreeBSDLoader: return @"FreeBSD Loader";
    default:                            return @"Unknown";
  }
}

- (NSString *)description
{
  return [NSString stringWithFormat:
    @"<BootEnvironmentInfo: OS=%@, Firmware=%@, Arch=%@, RPi=%@, Kernel=%@>",
    [self osTypeString], [self firmwareTypeString], _cpuArchitecture,
    _isRaspberryPi ? @"YES" : @"NO", _kernelVersion];
}

@end


#pragma mark - BootEnvironmentDetector Implementation

@implementation BootEnvironmentDetector

static BootEnvironmentDetector *_sharedDetector = nil;

+ (instancetype)sharedDetector
{
  if (_sharedDetector == nil) {
    _sharedDetector = [[BootEnvironmentDetector alloc] init];
  }
  return _sharedDetector;
}

- (instancetype)init
{
  self = [super init];
  if (self) {
    _fm = [[NSFileManager defaultManager] retain];
    _cachedInfo = nil;
    _detectionDone = NO;
  }
  return self;
}

- (void)dealloc
{
  [_fm release];
  [_cachedInfo release];
  [super dealloc];
}

#pragma mark - Main Detection

- (BootEnvironmentInfo *)detectEnvironment
{
  if (_detectionDone && _cachedInfo) {
    return _cachedInfo;
  }
  return [self redetectEnvironment];
}

- (BootEnvironmentInfo *)redetectEnvironment
{
  [_cachedInfo release];
  _cachedInfo = [[BootEnvironmentInfo alloc] init];
  
  _cachedInfo.osType = [self detectRunningOS];
  _cachedInfo.cpuArchitecture = [self detectCPUArchitecture];
  _cachedInfo.kernelVersion = [self detectKernelVersion];
  _cachedInfo.osRelease = [self detectOSRelease];
  _cachedInfo.isRaspberryPi = [self detectRaspberryPi];
  if (_cachedInfo.isRaspberryPi) {
    _cachedInfo.piModel = [self detectRaspberryPiModel];
  }
  _cachedInfo.firmwareType = [self detectBootFirmware];
  _cachedInfo.rootDevice = [self detectRootDevice];
  
  if (_cachedInfo.rootDevice) {
    NSString *parentDisk = [self parentDiskForPartition:_cachedInfo.rootDevice];
    if (parentDisk) {
      _cachedInfo.rootPartitionScheme = [self partitionSchemeForDisk:parentDisk];
    }
  }
  
  NSString *espDev = nil, *espMount = nil;
  if ([self findESPDevice:&espDev mountPoint:&espMount]) {
    _cachedInfo.espDevice = espDev;
    _cachedInfo.espMountPoint = espMount;
  }
  
  NSString *bootDev = nil, *bootMount = nil;
  if ([self findBootPartition:&bootDev mountPoint:&bootMount]) {
    _cachedInfo.bootDevice = bootDev;
    _cachedInfo.bootMountPoint = bootMount;
  }
  
  _detectionDone = YES;
  return _cachedInfo;
}

#pragma mark - OS Detection

- (SourceOSType)detectRunningOS
{
  struct utsname unameData;
  if (uname(&unameData) == 0) {
    NSString *sysname = [NSString stringWithUTF8String:unameData.sysname];
    
    if ([sysname isEqualToString:@"Linux"]) {
      return SourceOSTypeLinux;
    } else if ([sysname isEqualToString:@"FreeBSD"]) {
      return SourceOSTypeFreeBSD;
    } else if ([sysname isEqualToString:@"NetBSD"]) {
      return SourceOSTypeNetBSD;
    } else if ([sysname isEqualToString:@"OpenBSD"]) {
      return SourceOSTypeOpenBSD;
    } else if ([sysname isEqualToString:@"DragonFly"]) {
      return SourceOSTypeDragonFly;
    }
  }
  return SourceOSTypeUnknown;
}

- (NSString *)detectOSRelease
{
  // Try /etc/os-release first (standard location)
  NSString *osReleasePath = @"/etc/os-release";
  NSString *content = [self readFileContents:osReleasePath];
  
  if (content) {
    NSArray *lines = [content componentsSeparatedByString:@"\n"];
    for (NSString *line in lines) {
      if ([line hasPrefix:@"PRETTY_NAME="]) {
        NSString *value = [line substringFromIndex:12];
        // Remove quotes if present
        value = [value stringByTrimmingCharactersInSet:
          [NSCharacterSet characterSetWithCharactersInString:@"\""]];
        return value;
      }
    }
  }
  
  // Try FreeBSD style
  content = [self readFileContents:@"/etc/release"];
  if (content) {
    return [content stringByTrimmingCharactersInSet:
      [NSCharacterSet whitespaceAndNewlineCharacterSet]];
  }
  
  // Fallback to uname
  return [self runCommand:@"/bin/uname" arguments:@[@"-sr"]];
}

- (NSString *)detectCPUArchitecture
{
  struct utsname unameData;
  if (uname(&unameData) == 0) {
    return [NSString stringWithUTF8String:unameData.machine];
  }
  return @"unknown";
}

- (NSString *)detectKernelVersion
{
  struct utsname unameData;
  if (uname(&unameData) == 0) {
    return [NSString stringWithUTF8String:unameData.release];
  }
  return @"unknown";
}

#pragma mark - Firmware Detection

- (BootFirmwareType)detectBootFirmware
{
  // Check for Raspberry Pi first
  if ([self detectRaspberryPi]) {
    return BootFirmwareTypeRaspberryPi;
  }
  
  SourceOSType osType = [self detectRunningOS];
  
  if (osType == SourceOSTypeLinux) {
    // Linux: check /sys/firmware/efi
    if ([_fm fileExistsAtPath:@"/sys/firmware/efi"]) {
      return BootFirmwareTypeUEFI;
    }
    return BootFirmwareTypeBIOS;
  }
  
  if (osType == SourceOSTypeFreeBSD) {
    // FreeBSD: check via kenv or efivar
    NSString *output = [self runCommand:@"/sbin/kenv" 
                              arguments:@[@"bootmethod"]];
    if ([output containsString:@"UEFI"]) {
      return BootFirmwareTypeUEFI;
    }
    
    // Check for /dev/efi
    if ([_fm fileExistsAtPath:@"/dev/efi"]) {
      return BootFirmwareTypeUEFI;
    }
    
    return BootFirmwareTypeFreeBSDLoader;
  }
  
  // BSD variants
  if (osType == SourceOSTypeNetBSD || osType == SourceOSTypeOpenBSD ||
      osType == SourceOSTypeDragonFly) {
    // Check for UEFI presence
    if ([_fm fileExistsAtPath:@"/dev/efi"]) {
      return BootFirmwareTypeUEFI;
    }
    return BootFirmwareTypeBIOS;
  }
  
  return BootFirmwareTypeUnknown;
}

#pragma mark - Raspberry Pi Detection

- (BOOL)detectRaspberryPi
{
  SourceOSType osType = [self detectRunningOS];
  
  if (osType == SourceOSTypeLinux) {
    // Check /proc/device-tree/model
    NSString *model = [self readFileContents:@"/proc/device-tree/model"];
    if (model && [model containsString:@"Raspberry Pi"]) {
      return YES;
    }
    
    // Check /proc/cpuinfo for Raspberry Pi
    NSString *cpuinfo = [self readFileContents:@"/proc/cpuinfo"];
    if (cpuinfo) {
      if ([cpuinfo containsString:@"Raspberry Pi"] ||
          [cpuinfo containsString:@"BCM2835"] ||
          [cpuinfo containsString:@"BCM2836"] ||
          [cpuinfo containsString:@"BCM2837"] ||
          [cpuinfo containsString:@"BCM2711"] ||
          [cpuinfo containsString:@"BCM2712"]) {
        return YES;
      }
    }
  }
  
  if (osType == SourceOSTypeFreeBSD) {
    // Check sysctl hw.model
    NSString *model = [self runCommand:@"/sbin/sysctl" 
                             arguments:@[@"-n", @"hw.model"]];
    if (model && [model containsString:@"Raspberry Pi"]) {
      return YES;
    }
    
    // Check FDT
    NSString *fdt = [self runCommand:@"/sbin/sysctl"
                           arguments:@[@"-n", @"hw.fdt.model"]];
    if (fdt && [fdt containsString:@"Raspberry Pi"]) {
      return YES;
    }
  }
  
  return NO;
}

- (RaspberryPiModel)detectRaspberryPiModel
{
  NSString *model = nil;
  SourceOSType osType = [self detectRunningOS];
  
  if (osType == SourceOSTypeLinux) {
    model = [self readFileContents:@"/proc/device-tree/model"];
  } else if (osType == SourceOSTypeFreeBSD) {
    model = [self runCommand:@"/sbin/sysctl" 
                   arguments:@[@"-n", @"hw.fdt.model"]];
  }
  
  if (!model) {
    return RaspberryPiModelUnknown;
  }
  
  if ([model containsString:@"Pi 5"]) return RaspberryPiModel5;
  if ([model containsString:@"Pi 4"]) return RaspberryPiModel4;
  if ([model containsString:@"Pi 3"]) return RaspberryPiModel3;
  if ([model containsString:@"Pi 2"]) return RaspberryPiModel2;
  if ([model containsString:@"Pi Zero 2"]) return RaspberryPiModelZero2;
  if ([model containsString:@"Pi Zero"]) return RaspberryPiModelZero;
  if ([model containsString:@"Pi 1"] || 
      [model containsString:@"Model A"] ||
      [model containsString:@"Model B"]) return RaspberryPiModel1;
  
  return RaspberryPiModelUnknown;
}

#pragma mark - Disk/Partition Detection

- (NSString *)detectRootDevice
{
  return [self deviceForMountPoint:@"/"];
}

- (NSString *)parentDiskForPartition:(NSString *)partitionDevice
{
  if (!partitionDevice) return nil;
  
  // Handle /dev/sdXN -> /dev/sdX
  // Handle /dev/nvme0n1pN -> /dev/nvme0n1
  // Handle /dev/mmcblkNpM -> /dev/mmcblkN
  
  NSString *dev = [partitionDevice lastPathComponent];
  
  // NVMe style: nvme0n1p1 -> nvme0n1
  NSRange pRange = [dev rangeOfString:@"p" options:NSBackwardsSearch];
  if (pRange.location != NSNotFound && 
      [dev hasPrefix:@"nvme"]) {
    // Check if there are digits after the 'p'
    NSString *suffix = [dev substringFromIndex:pRange.location + 1];
    if ([suffix length] > 0) {
      unichar c = [suffix characterAtIndex:0];
      if (c >= '0' && c <= '9') {
        NSString *disk = [dev substringToIndex:pRange.location];
        return [NSString stringWithFormat:@"/dev/%@", disk];
      }
    }
  }
  
  // mmcblk style: mmcblk0p1 -> mmcblk0
  if ([dev hasPrefix:@"mmcblk"]) {
    pRange = [dev rangeOfString:@"p" options:NSBackwardsSearch];
    if (pRange.location != NSNotFound) {
      NSString *disk = [dev substringToIndex:pRange.location];
      return [NSString stringWithFormat:@"/dev/%@", disk];
    }
  }
  
  // Standard sd/hd style: sda1 -> sda
  NSMutableString *result = [NSMutableString stringWithString:dev];
  while ([result length] > 0) {
    unichar last = [result characterAtIndex:[result length] - 1];
    if (last >= '0' && last <= '9') {
      [result deleteCharactersInRange:NSMakeRange([result length] - 1, 1)];
    } else {
      break;
    }
  }
  
  if ([result length] > 0 && ![result isEqualToString:dev]) {
    return [NSString stringWithFormat:@"/dev/%@", result];
  }
  
  return nil;
}

- (PartitionSchemeType)partitionSchemeForDisk:(NSString *)diskDevice
{
  if (!diskDevice) return PartitionSchemeTypeUnknown;
  
  SourceOSType osType = [self detectRunningOS];
  
  if (osType == SourceOSTypeLinux) {
    // Use blkid to detect
    NSString *output = [self runCommand:@"/sbin/blkid" 
                              arguments:@[@"-p", @"-o", @"value", 
                                          @"-s", @"PTTYPE", diskDevice]];
    if ([output containsString:@"gpt"]) {
      return PartitionSchemeTypeGPT;
    }
    if ([output containsString:@"dos"] || [output containsString:@"mbr"]) {
      return PartitionSchemeTypeMBR;
    }
    
    // Fallback: check /sys/block
    NSString *devName = [diskDevice lastPathComponent];
    NSString *sysPath = [NSString stringWithFormat:
      @"/sys/block/%@/device/type", devName];
    if ([_fm fileExistsAtPath:sysPath]) {
      // Check for GPT in partition table
      NSString *ptPath = [NSString stringWithFormat:
        @"/sys/block/%@/device/gpt_verified", devName];
      if ([_fm fileExistsAtPath:ptPath]) {
        return PartitionSchemeTypeGPT;
      }
    }
  }
  
  if (osType == SourceOSTypeFreeBSD) {
    // Use gpart to detect
    NSString *output = [self runCommand:@"/sbin/gpart" 
                              arguments:@[@"show", diskDevice]];
    if ([output containsString:@"GPT"]) {
      return PartitionSchemeTypeGPT;
    }
    if ([output containsString:@"MBR"] || [output containsString:@"MSDOS"]) {
      return PartitionSchemeTypeMBR;
    }
    if ([output containsString:@"BSD"]) {
      return PartitionSchemeTypeBSD;
    }
  }
  
  return PartitionSchemeTypeUnknown;
}

- (BOOL)findESPDevice:(NSString **)device mountPoint:(NSString **)mountPoint
{
  NSArray *mounts = [self parseMountTable];
  
  // Common ESP mount points
  NSArray *espMounts = @[@"/boot/efi", @"/efi", @"/boot/EFI"];
  
  for (NSDictionary *mount in mounts) {
    NSString *mp = mount[@"mountpoint"];
    NSString *dev = mount[@"device"];
    NSString *fstype = mount[@"fstype"];
    
    // Check if it's an ESP mount point
    for (NSString *espPath in espMounts) {
      if ([mp isEqualToString:espPath]) {
        // Verify it's FAT
        if ([fstype hasPrefix:@"vfat"] || [fstype hasPrefix:@"fat"] ||
            [fstype isEqualToString:@"msdosfs"]) {
          if (device) *device = dev;
          if (mountPoint) *mountPoint = mp;
          return YES;
        }
      }
    }
  }
  
  return NO;
}

- (BOOL)findBootPartition:(NSString **)device mountPoint:(NSString **)mountPoint
{
  NSArray *mounts = [self parseMountTable];
  
  for (NSDictionary *mount in mounts) {
    NSString *mp = mount[@"mountpoint"];
    NSString *dev = mount[@"device"];
    
    if ([mp isEqualToString:@"/boot"]) {
      if (device) *device = dev;
      if (mountPoint) *mountPoint = mp;
      return YES;
    }
  }
  
  return NO;
}

- (NSArray *)enumerateBlockDevices
{
  NSMutableArray *devices = [NSMutableArray array];
  
  SourceOSType osType = [self detectRunningOS];
  
  if (osType == SourceOSTypeLinux) {
    // Read /sys/block
    NSString *sysBlock = @"/sys/block";
    NSArray *contents = [_fm contentsOfDirectoryAtPath:sysBlock error:nil];
    
    for (NSString *dev in contents) {
      // Skip loop devices, ram devices
      if ([dev hasPrefix:@"loop"] || [dev hasPrefix:@"ram"] ||
          [dev hasPrefix:@"dm-"]) {
        continue;
      }
      
      NSString *devPath = [NSString stringWithFormat:@"/dev/%@", dev];
      if ([_fm fileExistsAtPath:devPath]) {
        [devices addObject:devPath];
      }
    }
  }
  
  if (osType == SourceOSTypeFreeBSD) {
    // Use geom to list devices
    NSString *output = [self runCommand:@"/sbin/geom" 
                              arguments:@[@"disk", @"list"]];
    if (output) {
      NSArray *lines = [output componentsSeparatedByString:@"\n"];
      for (NSString *line in lines) {
        if ([line hasPrefix:@"Geom name:"]) {
          NSString *name = [[line componentsSeparatedByString:@":"] 
                             lastObject];
          name = [name stringByTrimmingCharactersInSet:
            [NSCharacterSet whitespaceCharacterSet]];
          if ([name length] > 0) {
            [devices addObject:[NSString stringWithFormat:@"/dev/%@", name]];
          }
        }
      }
    }
  }
  
  return devices;
}

- (NSString *)filesystemTypeForPath:(NSString *)path
{
  if (!path) return nil;
  
  NSArray *mounts = [self parseMountTable];
  
  // Find the mount that contains this path
  NSUInteger bestLen = 0;
  NSString *bestType = nil;
  
  for (NSDictionary *mount in mounts) {
    NSString *mp = mount[@"mountpoint"];
    if ([path hasPrefix:mp] && [mp length] > bestLen) {
      bestLen = [mp length];
      bestType = mount[@"fstype"];
    }
  }
  
  return bestType;
}

- (NSString *)filesystemTypeForDevice:(NSString *)device
{
  if (!device) return nil;
  
  SourceOSType osType = [self detectRunningOS];
  
  if (osType == SourceOSTypeLinux) {
    NSString *output = [self runCommand:@"/sbin/blkid" 
                              arguments:@[@"-o", @"value", @"-s", 
                                          @"TYPE", device]];
    if (output) {
      return [output stringByTrimmingCharactersInSet:
        [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    }
  }
  
  if (osType == SourceOSTypeFreeBSD) {
    // Check mount table first
    NSArray *mounts = [self parseMountTable];
    for (NSDictionary *mount in mounts) {
      if ([mount[@"device"] isEqualToString:device]) {
        return mount[@"fstype"];
      }
    }
    
    // Use file -s
    NSString *output = [self runCommand:@"/usr/bin/file" 
                              arguments:@[@"-s", device]];
    if (output) {
      if ([output containsString:@"ext4"]) return @"ext4";
      if ([output containsString:@"ext3"]) return @"ext3";
      if ([output containsString:@"ext2"]) return @"ext2";
      if ([output containsString:@"XFS"]) return @"xfs";
      if ([output containsString:@"UFS"]) return @"ufs";
      if ([output containsString:@"ZFS"]) return @"zfs";
      if ([output containsString:@"FAT"]) return @"msdosfs";
    }
  }
  
  return nil;
}

- (NSString *)mountPointForDevice:(NSString *)device
{
  if (!device) return nil;
  
  NSArray *mounts = [self parseMountTable];
  for (NSDictionary *mount in mounts) {
    if ([mount[@"device"] isEqualToString:device]) {
      return mount[@"mountpoint"];
    }
  }
  
  return nil;
}

- (NSString *)deviceForMountPoint:(NSString *)mountPoint
{
  if (!mountPoint) return nil;
  
  NSArray *mounts = [self parseMountTable];
  for (NSDictionary *mount in mounts) {
    if ([mount[@"mountpoint"] isEqualToString:mountPoint]) {
      return mount[@"device"];
    }
  }
  
  return nil;
}

#pragma mark - Tool Detection

- (BOOL)toolExists:(NSString *)toolName
{
  return [self pathForTool:toolName] != nil;
}

- (NSString *)pathForTool:(NSString *)toolName
{
  if (!toolName) return nil;
  
  // Check common paths
  NSArray *searchPaths = @[
    @"/usr/sbin", @"/sbin", @"/usr/bin", @"/bin",
    @"/usr/local/sbin", @"/usr/local/bin"
  ];
  
  for (NSString *dir in searchPaths) {
    NSString *path = [dir stringByAppendingPathComponent:toolName];
    if ([_fm isExecutableFileAtPath:path]) {
      return path;
    }
  }
  
  return nil;
}

- (BOOL)grubAvailable
{
  return [self toolExists:@"grub-install"] || 
         [self toolExists:@"grub2-install"];
}

- (BOOL)systemdBootAvailable
{
  return [self toolExists:@"bootctl"];
}

- (BOOL)freebsdBootcodeAvailable
{
  return [self toolExists:@"gpart"] && [self toolExists:@"boot0cfg"];
}

#pragma mark - Utility Methods

- (NSString *)runCommand:(NSString *)command arguments:(NSArray *)args
{
  if (!command) return nil;
  
  NSTask *task = [[NSTask alloc] init];
  NSPipe *pipe = [NSPipe pipe];
  
  @try {
    [task setLaunchPath:command];
    if (args) {
      [task setArguments:args];
    }
    [task setStandardOutput:pipe];
    [task setStandardError:[NSPipe pipe]];
    [task launch];
    [task waitUntilExit];
    
    NSData *data = [[pipe fileHandleForReading] readDataToEndOfFile];
    NSString *output = [[NSString alloc] initWithData:data 
                                             encoding:NSUTF8StringEncoding];
    [task release];
    return [output autorelease];
  } @catch (NSException *e) {
    [task release];
    return nil;
  }
}

- (int)runCommandStatus:(NSString *)command arguments:(NSArray *)args
{
  if (!command) return -1;
  
  NSTask *task = [[NSTask alloc] init];
  
  @try {
    [task setLaunchPath:command];
    if (args) {
      [task setArguments:args];
    }
    [task setStandardOutput:[NSPipe pipe]];
    [task setStandardError:[NSPipe pipe]];
    [task launch];
    [task waitUntilExit];
    
    int status = [task terminationStatus];
    [task release];
    return status;
  } @catch (NSException *e) {
    [task release];
    return -1;
  }
}

- (NSString *)readFileContents:(NSString *)path
{
  if (!path) return nil;
  
  NSError *error = nil;
  NSString *contents = [NSString stringWithContentsOfFile:path 
                                                 encoding:NSUTF8StringEncoding 
                                                    error:&error];
  return contents;
}

- (NSArray *)parseMountTable
{
  NSMutableArray *mounts = [NSMutableArray array];
  SourceOSType osType = [self detectRunningOS];
  
  NSString *mountFile = nil;
  if (osType == SourceOSTypeLinux) {
    mountFile = @"/proc/mounts";
  } else {
    mountFile = @"/etc/mtab";
  }
  
  // Try /proc/mounts first, then mount command
  NSString *content = [self readFileContents:mountFile];
  if (!content) {
    content = [self runCommand:@"/bin/mount" arguments:nil];
  }
  
  if (!content) return mounts;
  
  NSArray *lines = [content componentsSeparatedByString:@"\n"];
  for (NSString *line in lines) {
    if ([line length] == 0) continue;
    
    NSArray *parts = [line componentsSeparatedByCharactersInSet:
      [NSCharacterSet whitespaceCharacterSet]];
    
    // Filter empty parts
    NSMutableArray *filtered = [NSMutableArray array];
    for (NSString *part in parts) {
      if ([part length] > 0) {
        [filtered addObject:part];
      }
    }
    
    if ([filtered count] >= 3) {
      NSDictionary *mount = @{
        @"device": filtered[0],
        @"mountpoint": filtered[1],
        @"fstype": filtered[2]
      };
      [mounts addObject:mount];
    }
  }
  
  return mounts;
}

@end
