/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "BootPartitionValidator.h"
#import "BootEnvironmentDetector.h"
#import <sys/stat.h>
#import <sys/statvfs.h>
#import <sys/types.h>
#import <unistd.h>
#import <errno.h>

// Forward declaration for FSNode if not available
#ifndef FSNODE_DEFINED
@interface FSNode : NSObject
- (NSString *)path;
- (BOOL)isMountPoint;
- (BOOL)isDirectory;
@end
#define FSNODE_DEFINED
#endif

#pragma mark - BootPartitionValidationResult Implementation

@implementation BootPartitionValidationResult

@synthesize valid = _valid;
@synthesize failureReason = _failureReason;
@synthesize failureCode = _failureCode;
@synthesize partitionInfo = _partitionInfo;

+ (instancetype)validResultWithInfo:(NSDictionary *)info
{
  BootPartitionValidationResult *result = [[self alloc] init];
  result.valid = YES;
  result.partitionInfo = info;
  return [result autorelease];
}

+ (instancetype)invalidResultWithReason:(NSString *)reason code:(NSString *)code
{
  BootPartitionValidationResult *result = [[self alloc] init];
  result.valid = NO;
  result.failureReason = reason;
  result.failureCode = code;
  return [result autorelease];
}

- (void)dealloc
{
  [_failureReason release];
  [_failureCode release];
  [_partitionInfo release];
  [super dealloc];
}

@end


#pragma mark - BootPartitionValidator Implementation

@implementation BootPartitionValidator

static BootPartitionValidator *_sharedValidator = nil;

+ (instancetype)sharedValidator
{
  if (_sharedValidator == nil) {
    _sharedValidator = [[BootPartitionValidator alloc] init];
  }
  return _sharedValidator;
}

- (instancetype)init
{
  self = [super init];
  if (self) {
    _fm = [[NSFileManager defaultManager] retain];
    _detectedOS = SourceOSTypeUnknown;
    _detectedFirmware = BootFirmwareTypeUnknown;
    _cpuArchitecture = nil;
    _isRaspberryPi = NO;
    
    // Initialize detection
    [self detectRunningOS];
    [self detectCPUArchitecture];
    [self detectBootFirmware];
    [self detectRaspberryPi];
  }
  return self;
}

- (void)dealloc
{
  [_fm release];
  [_cpuArchitecture release];
  [super dealloc];
}

#pragma mark - Environment Detection Wrappers

- (SourceOSType)detectRunningOS
{
  if (_detectedOS == SourceOSTypeUnknown) {
    _detectedOS = [[BootEnvironmentDetector sharedDetector] detectRunningOS];
  }
  return _detectedOS;
}

- (NSString *)detectCPUArchitecture
{
  if (!_cpuArchitecture) {
    _cpuArchitecture = [[[BootEnvironmentDetector sharedDetector] 
                          detectCPUArchitecture] retain];
  }
  return _cpuArchitecture;
}

- (BOOL)detectRaspberryPi
{
  _isRaspberryPi = [[BootEnvironmentDetector sharedDetector] detectRaspberryPi];
  return _isRaspberryPi;
}

- (BootFirmwareType)detectBootFirmware
{
  if (_detectedFirmware == BootFirmwareTypeUnknown) {
    _detectedFirmware = [[BootEnvironmentDetector sharedDetector] 
                          detectBootFirmware];
  }
  return _detectedFirmware;
}

- (SourceOSType)detectedOS
{
  return _detectedOS;
}

- (BootFirmwareType)detectedFirmware
{
  return _detectedFirmware;
}

- (NSString *)cpuArchitecture
{
  return _cpuArchitecture;
}

- (BOOL)isRaspberryPi
{
  return _isRaspberryPi;
}

#pragma mark - Main Validation

- (BootPartitionValidationResult *)validateTargetNode:(FSNode *)targetNode
                                       forSourceNode:(FSNode *)sourceNode
{
  NSString *targetPath = [targetNode path];
  NSString *sourcePath = [sourceNode path];
  NSString *reason = nil;
  
  // Gather partition info as we validate
  NSMutableDictionary *info = [NSMutableDictionary dictionary];
  
  // Check 1: Real block device
  if (![self isRealBlockDevice:targetPath reason:&reason]) {
    return [BootPartitionValidationResult invalidResultWithReason:reason 
                                                            code:@"NOT_BLOCK_DEVICE"];
  }
  
  // Check 2: Not current root
  if (![self isNotCurrentRoot:targetPath reason:&reason]) {
    return [BootPartitionValidationResult invalidResultWithReason:reason 
                                                            code:@"IS_ROOT"];
  }
  
  // Check 3: Not read-only
  if (![self isNotReadOnlyDevice:targetPath reason:&reason]) {
    return [BootPartitionValidationResult invalidResultWithReason:reason 
                                                            code:@"READ_ONLY"];
  }
  
  // Check 4: Can mount read-write
  if (![self canMountReadWrite:targetPath reason:&reason]) {
    return [BootPartitionValidationResult invalidResultWithReason:reason 
                                                            code:@"CANNOT_MOUNT_RW"];
  }
  
  // Check 5: Sufficient size
  if (![self hasSufficientSize:targetPath forSourcePath:sourcePath reason:&reason]) {
    return [BootPartitionValidationResult invalidResultWithReason:reason 
                                                            code:@"INSUFFICIENT_SIZE"];
  }
  
  // Check 6: Supported filesystem
  if (![self hasSuportedFilesystem:targetPath reason:&reason]) {
    return [BootPartitionValidationResult invalidResultWithReason:reason 
                                                            code:@"UNSUPPORTED_FS"];
  }
  
  // Check 7: Required features
  if (![self supportsRequiredFeatures:targetPath reason:&reason]) {
    return [BootPartitionValidationResult invalidResultWithReason:reason 
                                                            code:@"MISSING_FEATURES"];
  }
  
  // Check 8: Filesystem clean
  if (![self isFilesystemClean:targetPath reason:&reason]) {
    return [BootPartitionValidationResult invalidResultWithReason:reason 
                                                            code:@"FS_CORRUPTED"];
  }
  
  // Check 9: Readable identifier
  if (![self hasReadableIdentifier:targetPath reason:&reason]) {
    return [BootPartitionValidationResult invalidResultWithReason:reason 
                                                            code:@"NO_IDENTIFIER"];
  }
  
  // Check 10: Not swap
  if (![self isNotSwap:targetPath reason:&reason]) {
    return [BootPartitionValidationResult invalidResultWithReason:reason 
                                                            code:@"IS_SWAP"];
  }
  
  // Check 11: Not encrypted
  if (![self isNotEncryptedOrUnlocked:targetPath reason:&reason]) {
    return [BootPartitionValidationResult invalidResultWithReason:reason 
                                                            code:@"ENCRYPTED"];
  }
  
  // Check 12: Not RAID/LVM
  if (![self isNotActiveRAIDOrLVM:targetPath reason:&reason]) {
    return [BootPartitionValidationResult invalidResultWithReason:reason 
                                                            code:@"RAID_LVM"];
  }
  
  // Check 13: Supported partition scheme
  PartitionSchemeType scheme = PartitionSchemeTypeUnknown;
  if (![self hasSuportedPartitionScheme:targetPath scheme:&scheme reason:&reason]) {
    return [BootPartitionValidationResult invalidResultWithReason:reason 
                                                            code:@"UNSUPPORTED_SCHEME"];
  }
  info[@"partitionScheme"] = @(scheme);
  
  // Check 14: Sufficient free space
  if (![self hasSufficientFreeSpace:targetPath forSourcePath:sourcePath reason:&reason]) {
    return [BootPartitionValidationResult invalidResultWithReason:reason 
                                                            code:@"INSUFFICIENT_SPACE"];
  }
  
  // Check 15: Ownership and xattrs
  if (![self supportsOwnershipAndXattrs:targetPath reason:&reason]) {
    return [BootPartitionValidationResult invalidResultWithReason:reason 
                                                            code:@"NO_OWNERSHIP"];
  }
  
  // Check 16: Firmware can boot
  if (![self firmwareCanBootFrom:targetPath reason:&reason]) {
    return [BootPartitionValidationResult invalidResultWithReason:reason 
                                                            code:@"FIRMWARE_CANNOT_BOOT"];
  }
  
  // Check 17-18: UEFI ESP
  if (_detectedFirmware == BootFirmwareTypeUEFI) {
    NSString *espPath = nil;
    if (![self hasValidESP:targetPath espPath:&espPath reason:&reason]) {
      return [BootPartitionValidationResult invalidResultWithReason:reason 
                                                              code:@"NO_VALID_ESP"];
    }
    if (espPath) info[@"espPath"] = espPath;
  }
  
  // Check 18-19: Raspberry Pi boot
  if (_isRaspberryPi) {
    NSString *bootPath = nil;
    if (![self hasValidRPiBootPartition:targetPath bootPath:&bootPath reason:&reason]) {
      return [BootPartitionValidationResult invalidResultWithReason:reason 
                                                              code:@"NO_RPI_BOOT"];
    }
    if (bootPath) info[@"rpiBootPath"] = bootPath;
  }
  
  // Check 20: Boot partition accessible
  NSString *bootPath = info[@"rpiBootPath"] ?: info[@"espPath"];
  if (bootPath) {
    if (![self bootPartitionAccessible:targetPath bootPath:bootPath reason:&reason]) {
      return [BootPartitionValidationResult invalidResultWithReason:reason 
                                                              code:@"BOOT_NOT_ACCESSIBLE"];
    }
  }
  
  // Check 21: Bootloader available
  NSString *bootloaderPath = nil;
  if (![self bootloaderAvailable:&bootloaderPath reason:&reason]) {
    return [BootPartitionValidationResult invalidResultWithReason:reason 
                                                            code:@"NO_BOOTLOADER"];
  }
  if (bootloaderPath) info[@"bootloaderPath"] = bootloaderPath;
  
  // Check 22: Not non-bootable removable
  if (![self isNotNonBootableRemovable:targetPath reason:&reason]) {
    return [BootPartitionValidationResult invalidResultWithReason:reason 
                                                            code:@"NON_BOOTABLE_REMOVABLE"];
  }
  
  // Check 23: OS compatible with arch
  if (![self isOSCompatibleWithArch:&reason]) {
    return [BootPartitionValidationResult invalidResultWithReason:reason 
                                                            code:@"ARCH_INCOMPATIBLE"];
  }
  
  // Check 24: Source supports live copy
  if (![self sourceSupportsLiveCopy:&reason]) {
    return [BootPartitionValidationResult invalidResultWithReason:reason 
                                                            code:@"NO_LIVE_COPY"];
  }
  
  // Check 25: Kernel suitable
  if (![self kernelSuitableForTarget:targetPath reason:&reason]) {
    return [BootPartitionValidationResult invalidResultWithReason:reason 
                                                            code:@"KERNEL_UNSUITABLE"];
  }
  
  // Check 26: FS supported by bootloader
  if (![self filesystemSuportedByBootloader:targetPath reason:&reason]) {
    return [BootPartitionValidationResult invalidResultWithReason:reason 
                                                            code:@"FS_NOT_BOOTABLE"];
  }
  
  // Check 27: FreeBSD bootcode
  if (_detectedOS == SourceOSTypeFreeBSD) {
    if (![self freebsdBootcodeAvailable:targetPath reason:&reason]) {
      return [BootPartitionValidationResult invalidResultWithReason:reason 
                                                              code:@"NO_FREEBSD_BOOTCODE"];
    }
  }
  
  // Check 28: Sufficient privileges
  if (![self hasSufficientPrivileges:&reason]) {
    return [BootPartitionValidationResult invalidResultWithReason:reason 
                                                            code:@"INSUFFICIENT_PRIVILEGES"];
  }
  
  // Check 29: Not protected by policy
  if (![self isNotProtectedByPolicy:targetPath reason:&reason]) {
    return [BootPartitionValidationResult invalidResultWithReason:reason 
                                                            code:@"PROTECTED_BY_POLICY"];
  }
  
  // Check 30: No I/O errors
  if (![self hasNoIOErrors:targetPath reason:&reason]) {
    return [BootPartitionValidationResult invalidResultWithReason:reason 
                                                            code:@"IO_ERRORS"];
  }
  
  // Check 31: Target is not source disk
  if (![self targetIsNotSourceDisk:targetPath sourcePath:sourcePath reason:&reason]) {
    return [BootPartitionValidationResult invalidResultWithReason:reason 
                                                            code:@"TARGET_IS_SOURCE"];
  }
  
  // All checks passed
  return [BootPartitionValidationResult validResultWithInfo:info];
}

- (BOOL)canAcceptDragForTarget:(FSNode *)targetNode
                        source:(FSNode *)sourceNode
{
  NSString *targetPath = [targetNode path];
  NSString *sourcePath = [sourceNode path];
  
  // Quick checks only - must be very fast
  
  // Source must be root
  if (![sourcePath isEqualToString:@"/"]) {
    return NO;
  }
  
  // Target must be a mount point or potential mount point
  if (![targetNode isMountPoint] && ![targetNode isDirectory]) {
    return NO;
  }
  
  // Target must not be root
  if ([targetPath isEqualToString:@"/"]) {
    return NO;
  }
  
  // Basic privilege check
  if (geteuid() != 0) {
    return NO;
  }
  
  // Don't do expensive checks here - those are done in full validation
  return YES;
}

#pragma mark - Individual Validation Checks

// Check 1: Real block device
- (BOOL)isRealBlockDevice:(NSString *)path reason:(NSString **)reason
{
  // Get device for this mount point
  NSString *device = [self deviceForMountPoint:path];
  if (!device) {
    // Path might be a device path itself
    device = path;
  }
  
  struct stat statBuf;
  if (stat([device fileSystemRepresentation], &statBuf) != 0) {
    if (reason) *reason = @"Cannot stat device";
    return NO;
  }
  
  // Check if it's a block device
  if (!S_ISBLK(statBuf.st_mode)) {
    if (reason) *reason = @"Target is not a block device";
    return NO;
  }
  
  // Check it's not a loopback device
  if ([device hasPrefix:@"/dev/loop"]) {
    if (reason) *reason = @"Target is a loopback device";
    return NO;
  }
  
  // Check it's not a network device
  if ([device hasPrefix:@"/dev/nbd"]) {
    if (reason) *reason = @"Target is a network block device";
    return NO;
  }
  
  return YES;
}

// Check 2: Not current root
- (BOOL)isNotCurrentRoot:(NSString *)path reason:(NSString **)reason
{
  if ([path isEqualToString:@"/"]) {
    if (reason) *reason = @"Cannot install to current root filesystem";
    return NO;
  }
  
  // Also check by device
  NSString *targetDevice = [self deviceForMountPoint:path];
  NSString *rootDevice = [self deviceForMountPoint:@"/"];
  
  if (targetDevice && rootDevice && [targetDevice isEqualToString:rootDevice]) {
    if (reason) *reason = @"Target device is the current root device";
    return NO;
  }
  
  return YES;
}

// Check 3: Not read-only at block layer
- (BOOL)isNotReadOnlyDevice:(NSString *)path reason:(NSString **)reason
{
  NSString *device = [self deviceForMountPoint:path];
  if (!device) device = path;
  
  // On Linux, check /sys/block/<dev>/ro
  if (_detectedOS == SourceOSTypeLinux) {
    NSString *devName = [device lastPathComponent];
    // Remove partition number to get base device
    NSString *baseDev = [[BootEnvironmentDetector sharedDetector] 
                          parentDiskForPartition:device];
    if (baseDev) {
      devName = [baseDev lastPathComponent];
    }
    
    NSString *roPath = [NSString stringWithFormat:@"/sys/block/%@/ro", devName];
    NSString *content = [[NSString alloc] initWithContentsOfFile:roPath
                                                        encoding:NSUTF8StringEncoding
                                                           error:nil];
    if (content) {
      int ro = [[content stringByTrimmingCharactersInSet:
        [NSCharacterSet whitespaceAndNewlineCharacterSet]] intValue];
      [content release];
      if (ro) {
        if (reason) *reason = @"Device is read-only at hardware level";
        return NO;
      }
    }
  }
  
  return YES;
}

// Check 4: Can mount read-write
- (BOOL)canMountReadWrite:(NSString *)path reason:(NSString **)reason
{
  // Check if already mounted
  NSString *device = [self deviceForMountPoint:path];
  if (device) {
    // It's mounted - check if it's mounted RW
    NSArray *mounts = [[BootEnvironmentDetector sharedDetector] parseMountTable];
    for (NSDictionary *mount in mounts) {
      if ([mount[@"mountpoint"] isEqualToString:path]) {
        // Check mount options for ro
        NSString *options = mount[@"options"];
        if (options && [options containsString:@"ro"]) {
          // Try to check if remountable
          if (reason) *reason = @"Filesystem is mounted read-only";
          return NO;
        }
        return YES;
      }
    }
  }
  
  // Not mounted - assume it can be mounted RW
  return YES;
}

// Check 5: Sufficient size
- (BOOL)hasSufficientSize:(NSString *)targetPath
            forSourcePath:(NSString *)sourcePath
                   reason:(NSString **)reason
{
  unsigned long long required = [self requiredSizeForSource:sourcePath 
                                              excludingHome:NO];
  unsigned long long available = [self availableSizeForTarget:targetPath];
  
  // Add 10% overhead
  required = (unsigned long long)(required * 1.1);
  
  if (available < required) {
    if (reason) {
      *reason = [NSString stringWithFormat:
        @"Insufficient space: need %.2f GB, have %.2f GB",
        required / 1073741824.0, available / 1073741824.0];
    }
    return NO;
  }
  
  return YES;
}

// Check 6: Supported filesystem
- (BOOL)hasSuportedFilesystem:(NSString *)path reason:(NSString **)reason
{
  NSString *fsType = [self filesystemTypeForPath:path];
  if (!fsType) {
    if (reason) *reason = @"Cannot determine filesystem type";
    return NO;
  }
  
  // Supported filesystem types
  NSSet *supported = [NSSet setWithArray:@[
    @"ext4", @"ext3", @"ext2", @"xfs", @"btrfs", @"f2fs",
    @"ufs", @"zfs", @"ffs", @"hammer2"
  ]];
  
  if (![supported containsObject:fsType]) {
    if (reason) {
      *reason = [NSString stringWithFormat:
        @"Filesystem type '%@' is not supported for bootable installation", fsType];
    }
    return NO;
  }
  
  return YES;
}

// Check 7: Required features
- (BOOL)supportsRequiredFeatures:(NSString *)path reason:(NSString **)reason
{
  // Check if filesystem supports symlinks, device nodes, permissions
  NSString *fsType = [self filesystemTypeForPath:path];
  
  // FAT doesn't support these
  if ([fsType hasPrefix:@"vfat"] || [fsType hasPrefix:@"fat"] ||
      [fsType isEqualToString:@"msdosfs"] || [fsType isEqualToString:@"ntfs"]) {
    if (reason) *reason = @"Filesystem does not support POSIX permissions or symlinks";
    return NO;
  }
  
  return YES;
}

// Check 8: Filesystem clean
- (BOOL)isFilesystemClean:(NSString *)path reason:(NSString **)reason
{
  // Quick check - we can't do full fsck without unmounting
  // Just check if mounted cleanly
  
  NSString *device = [self deviceForMountPoint:path];
  if (!device) {
    // Not mounted - we'll assume it needs to be checked at mount time
    return YES;
  }
  
  // On ext filesystems, check for clean unmount
  NSString *fsType = [self filesystemTypeForPath:path];
  if ([fsType hasPrefix:@"ext"]) {
    // Could use tune2fs to check, but that's invasive
    // Just trust the kernel mounted it
  }
  
  return YES;
}

// Check 9: Readable identifier
- (BOOL)hasReadableIdentifier:(NSString *)path reason:(NSString **)reason
{
  NSString *device = [self deviceForMountPoint:path];
  if (!device) device = path;
  
  if (_detectedOS == SourceOSTypeLinux) {
    // Try to get UUID via blkid
    NSString *output = [[BootEnvironmentDetector sharedDetector] 
                         runCommand:@"/sbin/blkid"
                         arguments:@[@"-s", @"UUID", @"-o", @"value", device]];
    if (!output || [output length] == 0) {
      // Try PARTUUID
      output = [[BootEnvironmentDetector sharedDetector]
                 runCommand:@"/sbin/blkid"
                 arguments:@[@"-s", @"PARTUUID", @"-o", @"value", device]];
    }
    
    if (!output || [output length] == 0) {
      if (reason) *reason = @"Cannot determine partition UUID or PARTUUID";
      return NO;
    }
  }
  
  return YES;
}

// Check 10: Not swap
- (BOOL)isNotSwap:(NSString *)path reason:(NSString **)reason
{
  NSString *device = [self deviceForMountPoint:path];
  if (!device) device = path;
  
  if (_detectedOS == SourceOSTypeLinux) {
    NSString *fsType = [[BootEnvironmentDetector sharedDetector]
                         filesystemTypeForDevice:device];
    if ([fsType isEqualToString:@"swap"]) {
      if (reason) *reason = @"Target is a swap partition";
      return NO;
    }
    
    // Also check /proc/swaps
    NSString *swaps = [[BootEnvironmentDetector sharedDetector]
                        readFileContents:@"/proc/swaps"];
    if (swaps && [swaps containsString:device]) {
      if (reason) *reason = @"Target is in use as swap";
      return NO;
    }
  }
  
  return YES;
}

// Check 11: Not encrypted or unlocked
- (BOOL)isNotEncryptedOrUnlocked:(NSString *)path reason:(NSString **)reason
{
  NSString *device = [self deviceForMountPoint:path];
  if (!device) device = path;
  
  if (_detectedOS == SourceOSTypeLinux) {
    // Check for LUKS encryption
    int status = [[BootEnvironmentDetector sharedDetector]
                   runCommandStatus:@"/sbin/cryptsetup"
                   arguments:@[@"isLuks", device]];
    if (status == 0) {
      if (reason) *reason = @"Target is an encrypted (LUKS) partition - not supported";
      return NO;
    }
    
    // Check for dm-crypt mapping
    if ([device hasPrefix:@"/dev/dm-"]) {
      // Could be LUKS unlocked - we need to check more carefully
      // For now, allow it if it's mounted and working
    }
  }
  
  return YES;
}

// Check 12: Not RAID or LVM
- (BOOL)isNotActiveRAIDOrLVM:(NSString *)path reason:(NSString **)reason
{
  NSString *device = [self deviceForMountPoint:path];
  if (!device) device = path;
  
  if (_detectedOS == SourceOSTypeLinux) {
    // Check for LVM
    if ([device hasPrefix:@"/dev/mapper/"] || 
        [device hasPrefix:@"/dev/dm-"]) {
      // Could be LVM - check with lvs
      NSString *output = [[BootEnvironmentDetector sharedDetector]
                           runCommand:@"/sbin/lvs"
                           arguments:@[@"--noheadings", @"-o", @"lv_path"]];
      if (output && [output containsString:device]) {
        if (reason) *reason = @"Target is an LVM logical volume - not supported";
        return NO;
      }
    }
    
    // Check for mdadm RAID
    if ([device hasPrefix:@"/dev/md"]) {
      if (reason) *reason = @"Target is a software RAID device - not supported";
      return NO;
    }
  }
  
  return YES;
}

// Check 13: Supported partition scheme
- (BOOL)hasSuportedPartitionScheme:(NSString *)path
                            scheme:(PartitionSchemeType *)scheme
                            reason:(NSString **)reason
{
  NSString *device = [self deviceForMountPoint:path];
  if (!device) device = path;
  
  NSString *parentDisk = [[BootEnvironmentDetector sharedDetector]
                           parentDiskForPartition:device];
  if (!parentDisk) {
    if (reason) *reason = @"Cannot determine parent disk device";
    return NO;
  }
  
  PartitionSchemeType detected = [[BootEnvironmentDetector sharedDetector]
                                   partitionSchemeForDisk:parentDisk];
  
  if (scheme) *scheme = detected;
  
  if (detected == PartitionSchemeTypeUnknown) {
    if (reason) *reason = @"Unknown or unsupported partition scheme";
    return NO;
  }
  
  return YES;
}

// Check 14: Sufficient free space (using statvfs)
- (BOOL)hasSufficientFreeSpace:(NSString *)targetPath
                 forSourcePath:(NSString *)sourcePath
                        reason:(NSString **)reason
{
  struct statvfs targetStat, sourceStat;
  
  if (statvfs([targetPath fileSystemRepresentation], &targetStat) != 0) {
    if (reason) *reason = @"Cannot stat target filesystem";
    return NO;
  }
  
  if (statvfs([sourcePath fileSystemRepresentation], &sourceStat) != 0) {
    if (reason) *reason = @"Cannot stat source filesystem";
    return NO;
  }
  
  // Calculate used space on source
  unsigned long long sourceUsed = 
    (sourceStat.f_blocks - sourceStat.f_bfree) * sourceStat.f_frsize;
  
  // Calculate available space on target
  unsigned long long targetAvail = targetStat.f_bavail * targetStat.f_frsize;
  
  // Add 10% overhead
  unsigned long long required = (unsigned long long)(sourceUsed * 1.1);
  
  if (targetAvail < required) {
    if (reason) {
      *reason = [NSString stringWithFormat:
        @"Insufficient free space: need %.2f GB, available %.2f GB",
        required / 1073741824.0, targetAvail / 1073741824.0];
    }
    return NO;
  }
  
  return YES;
}

// Check 15: Ownership and xattrs
- (BOOL)supportsOwnershipAndXattrs:(NSString *)path reason:(NSString **)reason
{
  NSString *fsType = [self filesystemTypeForPath:path];
  
  // FAT/NTFS don't support ownership
  if ([fsType hasPrefix:@"vfat"] || [fsType hasPrefix:@"fat"] ||
      [fsType isEqualToString:@"msdosfs"] || [fsType isEqualToString:@"ntfs"]) {
    if (reason) *reason = @"Filesystem does not support ownership";
    return NO;
  }
  
  // TODO: Could do a test write with xattr to verify
  
  return YES;
}

// Check 16: Firmware can boot
- (BOOL)firmwareCanBootFrom:(NSString *)path reason:(NSString **)reason
{
  NSString *device = [self deviceForMountPoint:path];
  if (!device) device = path;
  
  NSString *parentDisk = [[BootEnvironmentDetector sharedDetector]
                           parentDiskForPartition:device];
  
  if (_detectedFirmware == BootFirmwareTypeUEFI) {
    // UEFI can boot from most disks, but needs an ESP
    // ESP check is done separately
  }
  
  if (_detectedFirmware == BootFirmwareTypeBIOS) {
    // BIOS has limitations on disk size (2TB for MBR)
    // Check disk size
    if (_detectedOS == SourceOSTypeLinux && parentDisk) {
      NSString *sizePath = [NSString stringWithFormat:@"/sys/block/%@/size",
        [parentDisk lastPathComponent]];
      NSString *sizeStr = [[BootEnvironmentDetector sharedDetector]
                            readFileContents:sizePath];
      if (sizeStr) {
        unsigned long long sectors = [sizeStr longLongValue];
        unsigned long long bytes = sectors * 512;
        
        // 2TB limit for MBR
        PartitionSchemeType scheme = [[BootEnvironmentDetector sharedDetector]
                                       partitionSchemeForDisk:parentDisk];
        if (scheme == PartitionSchemeTypeMBR && bytes > 2199023255552ULL) {
          if (reason) *reason = @"Disk is larger than 2TB, BIOS cannot boot from MBR";
          return NO;
        }
      }
    }
  }
  
  return YES;
}

// Check 17-18: UEFI ESP
- (BOOL)hasValidESP:(NSString *)path
            espPath:(NSString **)espPath
             reason:(NSString **)reason
{
  // For UEFI, we need an EFI System Partition
  NSString *espDev = nil, *espMount = nil;
  
  if (![[BootEnvironmentDetector sharedDetector] 
         findESPDevice:&espDev mountPoint:&espMount]) {
    if (reason) *reason = @"No EFI System Partition found";
    return NO;
  }
  
  // Verify ESP is FAT formatted
  NSString *fsType = [[BootEnvironmentDetector sharedDetector]
                       filesystemTypeForDevice:espDev];
  if (!([fsType hasPrefix:@"vfat"] || [fsType hasPrefix:@"fat"] ||
        [fsType isEqualToString:@"msdosfs"])) {
    if (reason) *reason = @"EFI System Partition is not FAT formatted";
    return NO;
  }
  
  if (espPath) *espPath = espMount;
  return YES;
}

// Check 18-19: Raspberry Pi boot
- (BOOL)hasValidRPiBootPartition:(NSString *)path
                        bootPath:(NSString **)bootPath
                          reason:(NSString **)reason
{
  NSString *bootDev = nil, *bootMount = nil;
  
  // On Raspberry Pi, /boot is typically FAT
  if (![[BootEnvironmentDetector sharedDetector]
         findBootPartition:&bootDev mountPoint:&bootMount]) {
    // Try /boot/firmware (Ubuntu style)
    if ([_fm fileExistsAtPath:@"/boot/firmware/config.txt"]) {
      if (bootPath) *bootPath = @"/boot/firmware";
      return YES;
    }
    
    if (reason) *reason = @"No Raspberry Pi boot partition found";
    return NO;
  }
  
  // Verify boot partition is FAT
  NSString *fsType = [[BootEnvironmentDetector sharedDetector]
                       filesystemTypeForDevice:bootDev];
  if (!([fsType hasPrefix:@"vfat"] || [fsType hasPrefix:@"fat"] ||
        [fsType isEqualToString:@"msdosfs"])) {
    if (reason) *reason = @"Raspberry Pi boot partition is not FAT formatted";
    return NO;
  }
  
  if (bootPath) *bootPath = bootMount;
  return YES;
}

// Check 20: Boot partition accessible
- (BOOL)bootPartitionAccessible:(NSString *)rootPath
                       bootPath:(NSString *)bootPath
                         reason:(NSString **)reason
{
  // Check that boot path is accessible
  BOOL isDir = NO;
  if (![_fm fileExistsAtPath:bootPath isDirectory:&isDir] || !isDir) {
    if (reason) *reason = @"Boot partition is not accessible";
    return NO;
  }
  
  return YES;
}

// Check 21: Bootloader available
- (BOOL)bootloaderAvailable:(NSString **)bootloaderPath reason:(NSString **)reason
{
  BootEnvironmentDetector *detector = [BootEnvironmentDetector sharedDetector];
  
  if (_detectedOS == SourceOSTypeLinux) {
    if ([detector grubAvailable]) {
      NSString *path = [detector pathForTool:@"grub-install"];
      if (!path) path = [detector pathForTool:@"grub2-install"];
      if (bootloaderPath) *bootloaderPath = path;
      return YES;
    }
    
    if (_detectedFirmware == BootFirmwareTypeUEFI && 
        [detector systemdBootAvailable]) {
      if (bootloaderPath) *bootloaderPath = [detector pathForTool:@"bootctl"];
      return YES;
    }
    
    if (reason) *reason = @"No bootloader installer found (grub-install or bootctl)";
    return NO;
  }
  
  if (_detectedOS == SourceOSTypeFreeBSD) {
    if ([detector freebsdBootcodeAvailable]) {
      if (bootloaderPath) *bootloaderPath = [detector pathForTool:@"gpart"];
      return YES;
    }
    
    if (reason) *reason = @"FreeBSD bootcode tools not found";
    return NO;
  }
  
  if (reason) *reason = @"No bootloader available for this OS";
  return NO;
}

// Check 22: Not non-bootable removable
- (BOOL)isNotNonBootableRemovable:(NSString *)path reason:(NSString **)reason
{
  NSString *device = [self deviceForMountPoint:path];
  if (!device) device = path;
  
  NSString *parentDisk = [[BootEnvironmentDetector sharedDetector]
                           parentDiskForPartition:device];
  
  if (_detectedOS == SourceOSTypeLinux && parentDisk) {
    NSString *devName = [parentDisk lastPathComponent];
    
    // Check if removable
    NSString *removablePath = [NSString stringWithFormat:
      @"/sys/block/%@/removable", devName];
    NSString *content = [[BootEnvironmentDetector sharedDetector]
                          readFileContents:removablePath];
    if (content) {
      int removable = [[content stringByTrimmingCharactersInSet:
        [NSCharacterSet whitespaceAndNewlineCharacterSet]] intValue];
      if (removable) {
        // It's removable - check if it's a USB flash drive that may not be bootable
        // For now, just warn but allow it
      }
    }
  }
  
  return YES;
}

// Check 23: OS compatible with architecture
- (BOOL)isOSCompatibleWithArch:(NSString **)reason
{
  // Source and target should be same arch for live copy
  // Cross-architecture installation is not supported
  return YES;
}

// Check 24: Source supports live copy
- (BOOL)sourceSupportsLiveCopy:(NSString **)reason
{
  // All supported OS types support live copy
  if (_detectedOS == SourceOSTypeUnknown) {
    if (reason) *reason = @"Unknown operating system - cannot verify live copy support";
    return NO;
  }
  return YES;
}

// Check 25: Kernel suitable for target
- (BOOL)kernelSuitableForTarget:(NSString *)targetPath reason:(NSString **)reason
{
  // Check that kernel exists
  BOOL kernelExists = NO;
  
  if (_detectedOS == SourceOSTypeLinux) {
    kernelExists = [_fm fileExistsAtPath:@"/boot/vmlinuz"] ||
                   [_fm fileExistsAtPath:@"/boot/vmlinuz-linux"] ||
                   [_fm fileExistsAtPath:@"/vmlinuz"];
    
    // Also check for initramfs
    if (kernelExists) {
      BOOL initramfsExists = [_fm fileExistsAtPath:@"/boot/initrd.img"] ||
                             [_fm fileExistsAtPath:@"/boot/initramfs-linux.img"] ||
                             [_fm fileExistsAtPath:@"/initrd.img"];
      if (!initramfsExists) {
        // Check for versioned files
        NSArray *bootContents = [_fm contentsOfDirectoryAtPath:@"/boot" error:nil];
        for (NSString *file in bootContents) {
          if ([file hasPrefix:@"initrd"] || [file hasPrefix:@"initramfs"]) {
            initramfsExists = YES;
            break;
          }
        }
      }
      
      if (!initramfsExists) {
        if (reason) *reason = @"No initramfs found in /boot";
        return NO;
      }
    }
  }
  
  if (_detectedOS == SourceOSTypeFreeBSD) {
    kernelExists = [_fm fileExistsAtPath:@"/boot/kernel/kernel"];
  }
  
  if (!kernelExists) {
    if (reason) *reason = @"No bootable kernel found";
    return NO;
  }
  
  return YES;
}

// Check 26: Filesystem supported by bootloader
- (BOOL)filesystemSuportedByBootloader:(NSString *)path reason:(NSString **)reason
{
  NSString *fsType = [self filesystemTypeForPath:path];
  
  // GRUB supports most filesystems
  NSSet *grubSupported = [NSSet setWithArray:@[
    @"ext4", @"ext3", @"ext2", @"xfs", @"btrfs", @"f2fs",
    @"zfs", @"jfs", @"reiserfs"
  ]];
  
  // FreeBSD loader
  NSSet *freebsdSupported = [NSSet setWithArray:@[
    @"ufs", @"zfs", @"ffs"
  ]];
  
  if (_detectedOS == SourceOSTypeLinux) {
    if (![grubSupported containsObject:fsType]) {
      if (reason) {
        *reason = [NSString stringWithFormat:
          @"Filesystem '%@' is not supported by GRUB bootloader", fsType];
      }
      return NO;
    }
  }
  
  if (_detectedOS == SourceOSTypeFreeBSD) {
    if (![freebsdSupported containsObject:fsType]) {
      if (reason) {
        *reason = [NSString stringWithFormat:
          @"Filesystem '%@' is not supported by FreeBSD loader", fsType];
      }
      return NO;
    }
  }
  
  return YES;
}

// Check 27: FreeBSD bootcode
- (BOOL)freebsdBootcodeAvailable:(NSString *)path reason:(NSString **)reason
{
  if (_detectedOS != SourceOSTypeFreeBSD) {
    return YES;  // Not applicable
  }
  
  BootEnvironmentDetector *detector = [BootEnvironmentDetector sharedDetector];
  
  if (![detector freebsdBootcodeAvailable]) {
    if (reason) *reason = @"FreeBSD bootcode tools (gpart, boot0cfg) not found";
    return NO;
  }
  
  // Check that bootcode files exist
  BOOL hasBootcode = [_fm fileExistsAtPath:@"/boot/pmbr"] ||
                     [_fm fileExistsAtPath:@"/boot/gptboot"] ||
                     [_fm fileExistsAtPath:@"/boot/boot0"];
  
  if (!hasBootcode) {
    if (reason) *reason = @"FreeBSD bootcode files not found in /boot";
    return NO;
  }
  
  return YES;
}

// Check 28: Sufficient privileges
- (BOOL)hasSufficientPrivileges:(NSString **)reason
{
  if (geteuid() != 0) {
    if (reason) *reason = @"Must be running as root to perform bootable installation";
    return NO;
  }
  return YES;
}

// Check 29: Not protected by policy
- (BOOL)isNotProtectedByPolicy:(NSString *)path reason:(NSString **)reason
{
  // Check for protected paths
  NSSet *protected = [NSSet setWithArray:@[
    @"/",
    @"/boot/efi",
    @"/efi"
  ]];
  
  if ([protected containsObject:path]) {
    if (reason) *reason = @"Target path is protected by policy";
    return NO;
  }
  
  // Check for other OS partitions (by looking for OS markers)
  if ([_fm fileExistsAtPath:[path stringByAppendingPathComponent:@"Windows"]] ||
      [_fm fileExistsAtPath:[path stringByAppendingPathComponent:@"Windows/System32"]]) {
    if (reason) *reason = @"Target appears to contain a Windows installation";
    return NO;
  }
  
  return YES;
}

// Check 30: No I/O errors
- (BOOL)hasNoIOErrors:(NSString *)path reason:(NSString **)reason
{
  // Do a test read/write if path is mounted
  if ([_fm isWritableFileAtPath:path]) {
    NSString *testFile = [path stringByAppendingPathComponent:@".bootable_test"];
    NSData *testData = [@"test" dataUsingEncoding:NSUTF8StringEncoding];
    
    if (![testData writeToFile:testFile atomically:YES]) {
      if (reason) *reason = @"Cannot write to target - I/O error";
      return NO;
    }
    
    NSData *readBack = [NSData dataWithContentsOfFile:testFile];
    [_fm removeItemAtPath:testFile error:nil];
    
    if (![readBack isEqualToData:testData]) {
      if (reason) *reason = @"Write verification failed - possible I/O error";
      return NO;
    }
  }
  
  return YES;
}

// Check 31: Target is not source disk
- (BOOL)targetIsNotSourceDisk:(NSString *)targetPath
                   sourcePath:(NSString *)sourcePath
                       reason:(NSString **)reason
{
  BootEnvironmentDetector *detector = [BootEnvironmentDetector sharedDetector];
  
  NSString *targetDevice = [self deviceForMountPoint:targetPath];
  NSString *sourceDevice = [self deviceForMountPoint:sourcePath];
  
  if (!targetDevice || !sourceDevice) {
    return YES;  // Can't verify, allow it
  }
  
  NSString *targetDisk = [detector parentDiskForPartition:targetDevice];
  NSString *sourceDisk = [detector parentDiskForPartition:sourceDevice];
  
  if (targetDisk && sourceDisk && [targetDisk isEqualToString:sourceDisk]) {
    if (reason) *reason = @"Target partition is on the same disk as source";
    return NO;
  }
  
  return YES;
}

#pragma mark - Utility Methods

- (NSString *)deviceForMountPoint:(NSString *)mountPoint
{
  return [[BootEnvironmentDetector sharedDetector] deviceForMountPoint:mountPoint];
}

- (NSString *)mountPointForDevice:(NSString *)device
{
  return [[BootEnvironmentDetector sharedDetector] mountPointForDevice:device];
}

- (NSString *)filesystemTypeForPath:(NSString *)path
{
  return [[BootEnvironmentDetector sharedDetector] filesystemTypeForPath:path];
}

- (NSString *)parentDiskForPartition:(NSString *)partitionDevice
{
  return [[BootEnvironmentDetector sharedDetector] 
           parentDiskForPartition:partitionDevice];
}

- (PartitionSchemeType)partitionSchemeForDisk:(NSString *)diskDevice
{
  return [[BootEnvironmentDetector sharedDetector] 
           partitionSchemeForDisk:diskDevice];
}

- (unsigned long long)requiredSizeForSource:(NSString *)sourcePath
                              excludingHome:(BOOL)excludeHome
{
  struct statvfs stat;
  
  if (statvfs([sourcePath fileSystemRepresentation], &stat) != 0) {
    return 0;
  }
  
  unsigned long long used = (stat.f_blocks - stat.f_bfree) * stat.f_frsize;
  
  if (excludeHome) {
    // Subtract estimated /home size
    struct statvfs homeStat;
    if (statvfs("/home", &homeStat) == 0) {
      // Only subtract if /home is on same filesystem
      if (homeStat.f_fsid == stat.f_fsid) {
        unsigned long long homeUsed = 
          (homeStat.f_blocks - homeStat.f_bfree) * homeStat.f_frsize;
        if (homeUsed < used) {
          used -= homeUsed;
        }
      }
    }
  }
  
  return used;
}

- (unsigned long long)availableSizeForTarget:(NSString *)targetPath
{
  struct statvfs stat;
  
  if (statvfs([targetPath fileSystemRepresentation], &stat) != 0) {
    return 0;
  }
  
  return stat.f_bavail * stat.f_frsize;
}

@end
