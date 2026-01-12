/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#ifndef BLOCKDEVICEINFO_H
#define BLOCKDEVICEINFO_H

#import <Foundation/Foundation.h>

/**
 * Partition table type enumeration
 */
typedef NS_ENUM(NSInteger, PartitionTableType) {
  PartitionTableTypeUnknown = 0,
  PartitionTableTypeMBR,
  PartitionTableTypeGPT,
  PartitionTableTypeNone  /* Raw device with no partition table */
};

/**
 * Information about a single partition on a block device
 */
@interface PartitionInfo : NSObject
{
  NSString *_devicePath;      /* e.g., /dev/sdb1 */
  NSString *_label;           /* Partition label if any */
  NSString *_fsType;          /* Filesystem type (ext4, vfat, etc.) */
  NSString *_mountPoint;      /* Current mount point, or nil if not mounted */
  unsigned long long _size;   /* Size in bytes */
  NSUInteger _partitionNumber;
  BOOL _isMounted;
}

@property (nonatomic, copy) NSString *devicePath;
@property (nonatomic, copy) NSString *label;
@property (nonatomic, copy) NSString *fsType;
@property (nonatomic, copy) NSString *mountPoint;
@property (nonatomic, assign) unsigned long long size;
@property (nonatomic, assign) NSUInteger partitionNumber;
@property (nonatomic, assign) BOOL isMounted;

- (NSString *)sizeDescription;

@end


/**
 * BlockDeviceInfo provides metadata about a block device.
 * Used for validating ISO write targets and providing safety information.
 */
@interface BlockDeviceInfo : NSObject
{
  NSString *_devicePath;           /* e.g., /dev/sdb */
  NSString *_deviceName;           /* e.g., sdb */
  NSString *_model;                /* Device model name */
  NSString *_vendor;               /* Device vendor */
  NSString *_serial;               /* Serial number if available */
  unsigned long long _size;        /* Total size in bytes */
  PartitionTableType _partitionTableType;
  NSMutableArray *_partitions;     /* Array of PartitionInfo objects */
  BOOL _isRemovable;
  BOOL _isReadOnly;
  BOOL _isSystemDisk;              /* True if contains /boot or / */
  BOOL _isValid;
}

@property (nonatomic, copy, readonly) NSString *devicePath;
@property (nonatomic, copy, readonly) NSString *deviceName;
@property (nonatomic, copy, readonly) NSString *model;
@property (nonatomic, copy, readonly) NSString *vendor;
@property (nonatomic, copy, readonly) NSString *serial;
@property (nonatomic, assign, readonly) unsigned long long size;
@property (nonatomic, assign, readonly) PartitionTableType partitionTableType;
@property (nonatomic, copy, readonly) NSArray *partitions;
@property (nonatomic, assign, readonly) BOOL isRemovable;
@property (nonatomic, assign, readonly) BOOL isReadOnly;
@property (nonatomic, assign, readonly) BOOL isSystemDisk;
@property (nonatomic, assign, readonly) BOOL isValid;

/**
 * Create a BlockDeviceInfo from a device path (e.g., /dev/sdb)
 */
+ (instancetype)infoForDevicePath:(NSString *)devicePath;

/**
 * Create a BlockDeviceInfo from a mount point path.
 * Returns nil if the path is not a mount point for a physical device.
 */
+ (instancetype)infoForMountPoint:(NSString *)mountPoint;

/**
 * Get the raw device path for a mount point (e.g., /media/usb -> /dev/sdb1)
 * Returns nil if no device found for the mount point.
 */
+ (NSString *)devicePathForMountPoint:(NSString *)mountPoint;

/**
 * Get the parent block device path from a partition path.
 * e.g., /dev/sdb1 -> /dev/sdb, /dev/nvme0n1p1 -> /dev/nvme0n1
 */
+ (NSString *)parentDeviceForPartition:(NSString *)partitionPath;

/**
 * Check if a path represents a raw block device (not a partition)
 */
+ (BOOL)isRawBlockDevice:(NSString *)devicePath;

/**
 * Check if a path represents a partition
 */
+ (BOOL)isPartition:(NSString *)devicePath;

/**
 * Get all mounted partitions for this device
 */
- (NSArray *)mountedPartitions;

/**
 * Human-readable size description
 */
- (NSString *)sizeDescription;

/**
 * Description of partition table type
 */
- (NSString *)partitionTableDescription;

/**
 * Summary for confirmation dialog
 */
- (NSString *)deviceSummary;

/**
 * Check if any partition is currently in use (mounted, swap, etc.)
 */
- (BOOL)hasPartitionsInUse;

/**
 * Check if device can be safely written to
 * Returns nil if safe, or an error message if not
 */
- (NSString *)safetyCheckForWriting;

@end

#endif /* BLOCKDEVICEINFO_H */
