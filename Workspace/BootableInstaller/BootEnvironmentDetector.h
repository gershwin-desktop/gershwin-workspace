/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#ifndef BOOT_ENVIRONMENT_DETECTOR_H
#define BOOT_ENVIRONMENT_DETECTOR_H

#import <Foundation/Foundation.h>
#import "BootableInstallerTypes.h"

/**
 * Raspberry Pi model variants
 */
typedef NS_ENUM(NSInteger, RaspberryPiModel) {
  RaspberryPiModelNone = 0,
  RaspberryPiModel1,
  RaspberryPiModel2,
  RaspberryPiModel3,
  RaspberryPiModel4,
  RaspberryPiModel5,
  RaspberryPiModelZero,
  RaspberryPiModelZero2,
  RaspberryPiModelUnknown
};

/**
 * Boot environment information container
 */
@interface BootEnvironmentInfo : NSObject
{
  SourceOSType _osType;
  BootFirmwareType _firmwareType;
  PartitionSchemeType _rootPartitionScheme;
  NSString *_cpuArchitecture;
  BOOL _isRaspberryPi;
  RaspberryPiModel _piModel;
  NSString *_kernelVersion;
  NSString *_osRelease;
  NSString *_rootDevice;
  NSString *_espDevice;
  NSString *_espMountPoint;
  NSString *_bootDevice;
  NSString *_bootMountPoint;
}

@property (nonatomic, assign) SourceOSType osType;
@property (nonatomic, assign) BootFirmwareType firmwareType;
@property (nonatomic, assign) PartitionSchemeType rootPartitionScheme;
@property (nonatomic, copy) NSString *cpuArchitecture;
@property (nonatomic, assign) BOOL isRaspberryPi;
@property (nonatomic, assign) RaspberryPiModel piModel;
@property (nonatomic, copy) NSString *kernelVersion;
@property (nonatomic, copy) NSString *osRelease;
@property (nonatomic, copy) NSString *rootDevice;
@property (nonatomic, copy) NSString *espDevice;
@property (nonatomic, copy) NSString *espMountPoint;
@property (nonatomic, copy) NSString *bootDevice;
@property (nonatomic, copy) NSString *bootMountPoint;

- (NSString *)osTypeString;
- (NSString *)firmwareTypeString;
- (NSString *)description;

@end


/**
 * BootEnvironmentDetector detects the running system's boot environment.
 * 
 * This includes OS type, CPU architecture, firmware type (BIOS/UEFI/RPi),
 * partition schemes, and hardware-specific details like Raspberry Pi detection.
 */
@interface BootEnvironmentDetector : NSObject
{
  NSFileManager *_fm;
  BootEnvironmentInfo *_cachedInfo;
  BOOL _detectionDone;
}

/**
 * Shared singleton instance
 */
+ (instancetype)sharedDetector;

/**
 * Perform full environment detection and return cached info
 */
- (BootEnvironmentInfo *)detectEnvironment;

/**
 * Force re-detection (clears cache)
 */
- (BootEnvironmentInfo *)redetectEnvironment;

#pragma mark - Individual Detection Methods

/**
 * Detect the running OS type (Linux/FreeBSD/etc.)
 * Uses uname system call and /etc/os-release
 */
- (SourceOSType)detectRunningOS;

/**
 * Get detailed OS release information
 */
- (NSString *)detectOSRelease;

/**
 * Detect the CPU architecture (x86_64, aarch64, armv7l, etc.)
 * Uses uname system call
 */
- (NSString *)detectCPUArchitecture;

/**
 * Detect the boot firmware type (BIOS/UEFI/RPi)
 * Linux: checks /sys/firmware/efi
 * FreeBSD: checks efibootmgr or kenv
 */
- (BootFirmwareType)detectBootFirmware;

/**
 * Detect if running on Raspberry Pi hardware
 * Linux: /proc/device-tree/model, /proc/cpuinfo
 * FreeBSD: sysctl hw.model, FDT
 */
- (BOOL)detectRaspberryPi;

/**
 * Get specific Raspberry Pi model if detected
 */
- (RaspberryPiModel)detectRaspberryPiModel;

/**
 * Detect kernel version
 */
- (NSString *)detectKernelVersion;

#pragma mark - Disk/Partition Detection

/**
 * Get the device path for the root filesystem
 */
- (NSString *)detectRootDevice;

/**
 * Get the parent disk device for a partition
 * e.g., /dev/sda1 -> /dev/sda
 */
- (NSString *)parentDiskForPartition:(NSString *)partitionDevice;

/**
 * Detect partition scheme for a disk (GPT/MBR/BSD)
 * Linux: uses blkid or fdisk
 * FreeBSD: uses gpart or disklabel
 */
- (PartitionSchemeType)partitionSchemeForDisk:(NSString *)diskDevice;

/**
 * Find EFI System Partition device and mount point
 */
- (BOOL)findESPDevice:(NSString **)device mountPoint:(NSString **)mountPoint;

/**
 * Find separate /boot partition if exists
 */
- (BOOL)findBootPartition:(NSString **)device mountPoint:(NSString **)mountPoint;

/**
 * Enumerate all available block devices and partitions
 */
- (NSArray *)enumerateBlockDevices;

/**
 * Get filesystem type for a device or mount point
 */
- (NSString *)filesystemTypeForPath:(NSString *)path;

/**
 * Get filesystem type for a device
 */
- (NSString *)filesystemTypeForDevice:(NSString *)device;

/**
 * Get mount point for a device (nil if not mounted)
 */
- (NSString *)mountPointForDevice:(NSString *)device;

/**
 * Get device for a mount point (nil if not a mount point)
 */
- (NSString *)deviceForMountPoint:(NSString *)mountPoint;

#pragma mark - Tool Detection

/**
 * Check if a required tool/binary exists
 */
- (BOOL)toolExists:(NSString *)toolName;

/**
 * Get full path to a tool
 */
- (NSString *)pathForTool:(NSString *)toolName;

/**
 * Check if GRUB is available (grub-install or grub2-install)
 */
- (BOOL)grubAvailable;

/**
 * Check if systemd-boot is available (bootctl)
 */
- (BOOL)systemdBootAvailable;

/**
 * Check if FreeBSD bootcode tools are available
 */
- (BOOL)freebsdBootcodeAvailable;

#pragma mark - Utility Methods

/**
 * Run a command and return stdout
 */
- (NSString *)runCommand:(NSString *)command arguments:(NSArray *)args;

/**
 * Run a command and return exit status
 */
- (int)runCommandStatus:(NSString *)command arguments:(NSArray *)args;

/**
 * Read file contents as string
 */
- (NSString *)readFileContents:(NSString *)path;

/**
 * Parse /proc/mounts or equivalent
 */
- (NSArray *)parseMountTable;

@end

#endif /* BOOT_ENVIRONMENT_DETECTOR_H */
