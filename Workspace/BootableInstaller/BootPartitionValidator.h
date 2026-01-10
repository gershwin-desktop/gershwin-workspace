/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#ifndef BOOT_PARTITION_VALIDATOR_H
#define BOOT_PARTITION_VALIDATOR_H

#import <Foundation/Foundation.h>
#import "BootableInstallerTypes.h"

@class FSNode;

/**
 * Result of partition validation containing success/failure and reason
 */
@interface BootPartitionValidationResult : NSObject
{
  BOOL _valid;
  NSString *_failureReason;
  NSString *_failureCode;
  NSDictionary *_partitionInfo;
}

@property (nonatomic, assign) BOOL valid;
@property (nonatomic, copy) NSString *failureReason;
@property (nonatomic, copy) NSString *failureCode;
@property (nonatomic, copy) NSDictionary *partitionInfo;

+ (instancetype)validResultWithInfo:(NSDictionary *)info;
+ (instancetype)invalidResultWithReason:(NSString *)reason code:(NSString *)code;

@end


/**
 * BootPartitionValidator performs comprehensive validation of target partitions
 * for bootable OS installation. All checks are non-destructive and fast.
 *
 * This class implements all 30 validation checks from the requirements:
 * - Physical device checks (not loopback, not network, not root)
 * - Size and space validation
 * - Filesystem capability checks
 * - Boot environment compatibility
 * - Encryption and RAID status
 * - Policy and privilege checks
 */
@interface BootPartitionValidator : NSObject
{
  NSFileManager *_fm;
  SourceOSType _detectedOS;
  BootFirmwareType _detectedFirmware;
  NSString *_cpuArchitecture;
  BOOL _isRaspberryPi;
}

/**
 * Shared instance
 */
+ (instancetype)sharedValidator;

/**
 * Detect the running OS type (Linux/FreeBSD/etc.)
 */
- (SourceOSType)detectRunningOS;

/**
 * Detect the CPU architecture (x86_64, aarch64, armv7l, etc.)
 */
- (NSString *)detectCPUArchitecture;

/**
 * Detect if running on Raspberry Pi hardware
 */
- (BOOL)detectRaspberryPi;

/**
 * Detect the boot firmware type (BIOS/UEFI/RPi)
 */
- (BootFirmwareType)detectBootFirmware;

/**
 * Get the cached detected OS type
 */
- (SourceOSType)detectedOS;

/**
 * Get the cached boot firmware type
 */
- (BootFirmwareType)detectedFirmware;

/**
 * Get the cached CPU architecture
 */
- (NSString *)cpuArchitecture;

/**
 * Check if running on Raspberry Pi
 */
- (BOOL)isRaspberryPi;

#pragma mark - Main Validation

/**
 * Perform full validation of target node for bootable installation.
 * This runs all 30 checks and returns on first failure.
 * All checks are fast, non-destructive, and reversible.
 *
 * @param sourceNode The source root filesystem node (must be /)
 * @param targetNode The target partition node
 * @return Validation result with success/failure and reason
 */
- (BootPartitionValidationResult *)validateTargetNode:(FSNode *)targetNode
                                       forSourceNode:(FSNode *)sourceNode;

/**
 * Quick check if a drag should be accepted over a target.
 * This is used during draggingEntered/draggingUpdated.
 *
 * @param targetNode The potential target node
 * @param sourceNode The source root filesystem node
 * @return YES if the target might be valid, NO if definitely invalid
 */
- (BOOL)canAcceptDragForTarget:(FSNode *)targetNode
                        source:(FSNode *)sourceNode;

#pragma mark - Individual Validation Checks

/**
 * Check 1: Target is a real block device partition
 */
- (BOOL)isRealBlockDevice:(NSString *)path reason:(NSString **)reason;

/**
 * Check 2: Target is not the current root filesystem
 */
- (BOOL)isNotCurrentRoot:(NSString *)path reason:(NSString **)reason;

/**
 * Check 3: Target device is not read-only at block layer
 */
- (BOOL)isNotReadOnlyDevice:(NSString *)path reason:(NSString **)reason;

/**
 * Check 4: Target is not mounted or can be safely remounted
 */
- (BOOL)canMountReadWrite:(NSString *)path reason:(NSString **)reason;

/**
 * Check 5: Target has sufficient size for source rootfs
 */
- (BOOL)hasSufficientSize:(NSString *)targetPath
            forSourcePath:(NSString *)sourcePath
                   reason:(NSString **)reason;

/**
 * Check 6: Target filesystem type is supported
 */
- (BOOL)hasSuportedFilesystem:(NSString *)path reason:(NSString **)reason;

/**
 * Check 7: Filesystem supports POSIX permissions, symlinks, device nodes
 */
- (BOOL)supportsRequiredFeatures:(NSString *)path reason:(NSString **)reason;

/**
 * Check 8: Filesystem is not corrupted (quick check)
 */
- (BOOL)isFilesystemClean:(NSString *)path reason:(NSString **)reason;

/**
 * Check 9: Partition label/UUID is readable
 */
- (BOOL)hasReadableIdentifier:(NSString *)path reason:(NSString **)reason;

/**
 * Check 10: Not marked as swap
 */
- (BOOL)isNotSwap:(NSString *)path reason:(NSString **)reason;

/**
 * Check 11: Not encrypted or encryption is unlocked
 */
- (BOOL)isNotEncryptedOrUnlocked:(NSString *)path reason:(NSString **)reason;

/**
 * Check 12: Not part of active RAID/LVM
 */
- (BOOL)isNotActiveRAIDOrLVM:(NSString *)path reason:(NSString **)reason;

/**
 * Check 13: Uses supported partition scheme
 */
- (BOOL)hasSuportedPartitionScheme:(NSString *)path
                            scheme:(PartitionSchemeType *)scheme
                            reason:(NSString **)reason;

/**
 * Check 14: Sufficient free space with overhead
 */
- (BOOL)hasSufficientFreeSpace:(NSString *)targetPath
                 forSourcePath:(NSString *)sourcePath
                        reason:(NSString **)reason;

/**
 * Check 15: Allows setting ownership and xattrs
 */
- (BOOL)supportsOwnershipAndXattrs:(NSString *)path reason:(NSString **)reason;

/**
 * Check 16: Firmware can boot from target disk
 */
- (BOOL)firmwareCanBootFrom:(NSString *)path reason:(NSString **)reason;

/**
 * Check 17-18: UEFI-specific: ESP exists and is FAT formatted
 */
- (BOOL)hasValidESP:(NSString *)path
            espPath:(NSString **)espPath
             reason:(NSString **)reason;

/**
 * Check 18-19: Raspberry Pi: Boot partition exists and is FAT
 */
- (BOOL)hasValidRPiBootPartition:(NSString *)path
                        bootPath:(NSString **)bootPath
                          reason:(NSString **)reason;

/**
 * Check 20: Boot partition is accessible from target root
 */
- (BOOL)bootPartitionAccessible:(NSString *)rootPath
                       bootPath:(NSString *)bootPath
                         reason:(NSString **)reason;

/**
 * Check 21: Bootloader is available in running system
 */
- (BOOL)bootloaderAvailable:(NSString **)bootloaderPath reason:(NSString **)reason;

/**
 * Check 22: Target disk is not non-bootable removable media
 */
- (BOOL)isNotNonBootableRemovable:(NSString *)path reason:(NSString **)reason;

/**
 * Check 23: Source OS is compatible with target architecture
 */
- (BOOL)isOSCompatibleWithArch:(NSString **)reason;

/**
 * Check 24: Source OS supports live copy
 */
- (BOOL)sourceSupportsLiveCopy:(NSString **)reason;

/**
 * Check 25: Kernel/initramfs are suitable for target
 */
- (BOOL)kernelSuitableForTarget:(NSString *)targetPath reason:(NSString **)reason;

/**
 * Check 26: Filesystem supported by bootloader
 */
- (BOOL)filesystemSuportedByBootloader:(NSString *)path reason:(NSString **)reason;

/**
 * Check 27: FreeBSD-specific bootcode checks
 */
- (BOOL)freebsdBootcodeAvailable:(NSString *)path reason:(NSString **)reason;

/**
 * Check 28: User has sufficient privileges
 */
- (BOOL)hasSufficientPrivileges:(NSString **)reason;

/**
 * Check 29: Target not protected by policy
 */
- (BOOL)isNotProtectedByPolicy:(NSString *)path reason:(NSString **)reason;

/**
 * Check 30: Target not experiencing I/O errors
 */
- (BOOL)hasNoIOErrors:(NSString *)path reason:(NSString **)reason;

/**
 * Check 31: Target disk is not source disk
 */
- (BOOL)targetIsNotSourceDisk:(NSString *)targetPath
                   sourcePath:(NSString *)sourcePath
                       reason:(NSString **)reason;

#pragma mark - Utility Methods

/**
 * Get device path for a mount point
 */
- (NSString *)deviceForMountPoint:(NSString *)mountPoint;

/**
 * Get mount point for a device
 */
- (NSString *)mountPointForDevice:(NSString *)device;

/**
 * Get filesystem type for a path
 */
- (NSString *)filesystemTypeForPath:(NSString *)path;

/**
 * Get parent disk device for a partition device
 */
- (NSString *)parentDiskForPartition:(NSString *)partitionDevice;

/**
 * Get partition scheme for a disk
 */
- (PartitionSchemeType)partitionSchemeForDisk:(NSString *)diskDevice;

/**
 * Calculate required size for source rootfs copy
 */
- (unsigned long long)requiredSizeForSource:(NSString *)sourcePath
                              excludingHome:(BOOL)excludeHome;

/**
 * Get available size on target using statvfs
 */
- (unsigned long long)availableSizeForTarget:(NSString *)targetPath;

@end

#endif /* BOOT_PARTITION_VALIDATOR_H */
