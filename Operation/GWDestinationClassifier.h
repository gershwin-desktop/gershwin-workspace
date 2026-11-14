/* GWDestinationClassifier.h
 *
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

#ifndef GW_DESTINATION_CLASSIFIER_H
#define GW_DESTINATION_CLASSIFIER_H

#import <Foundation/Foundation.h>

/* Where a copy goes decides how carefully it has to be written: data for a
 * USB stick or a network share must really be there before the operation
 * says it is done, while a local fixed disk keeps the plain fast path. */
typedef enum
{
  GWDestinationLocal = 0,
  GWDestinationRemovable,
  GWDestinationNetwork
} GWDestinationKind;

typedef enum
{
  GWFilesystemDeviceBacked = 0,  /* look at the device to decide */
  GWFilesystemNetwork,
  GWFilesystemVirtual            /* tmpfs, proc, ...: local, no device */
} GWFilesystemClass;

/* Forces a kind for tests ("removable", "network", "local"). */
extern NSString * const GWCopyDestinationEnvironmentKey;

@interface GWDestination : NSObject
{
  GWDestinationKind _kind;
  NSString *_filesystemType;
  NSString *_mountPoint;
}

+ (instancetype)destinationWithKind:(GWDestinationKind)kind
                     filesystemType:(NSString *)type
                         mountPoint:(NSString *)mountPoint;

@property (nonatomic, readonly) GWDestinationKind kind;
@property (nonatomic, readonly) NSString *filesystemType;
@property (nonatomic, readonly) NSString *mountPoint;

/* Removable and network targets get the windowed writeback. */
- (BOOL)usesWriteWindows;
- (unsigned long long)windowCap;
/* Only removable devices get the final flush and the moves that keep
 * their sources until it succeeded. */
- (BOOL)needsFinalFlush;

/* Makes everything written below `items' durable on the device: one
 * syncfs() of the filesystem on Linux; elsewhere an fsync() of every file
 * and folder of the items and of the folder holding them. */
- (BOOL)flushItemsAtPaths:(NSArray *)items
              inDirectory:(NSString *)directory
                    error:(NSError **)error;

@end

@interface GWDestinationClassifier : NSObject
{
  NSString *_sysfsRoot;
  NSString *_mountInfoPath;
  NSMutableDictionary *_removableByDevice;
  NSMutableDictionary *_destinationByMount;
  NSLock *_lock;
}

+ (GWDestinationClassifier *)sharedClassifier;

/* Linux: the sysfs tree and the mountinfo file to read, replaceable by
 * recorded fixture trees in tests. */
- (instancetype)initWithSysfsRoot:(NSString *)sysfsRoot
                    mountInfoPath:(NSString *)mountInfoPath;

- (GWDestination *)destinationForDirectory:(NSString *)directory;

/* Linux sysfs: the device or what it is built on (device-mapper, md) is a
 * disk the kernel calls removable, sits behind a removable USB port or PCIe
 * slot, or is an SD card.  Cached per device. */
- (BOOL)isRemovableDeviceMajor:(unsigned)major minor:(unsigned)minor;

+ (GWFilesystemClass)classOfFilesystemType:(NSString *)type
                                    source:(NSString *)source;

/* One /proc/self/mountinfo line as a dictionary (mountID, major, minor,
 * mountPoint, type, source), or nil when it does not parse. */
+ (NSDictionary *)parseMountInfoLine:(NSString *)line;

/* The mount a path lies on, from (mountPoint) dictionaries: the longest
 * mount point that is the path or one of its parents. */
+ (NSDictionary *)mountForPath:(NSString *)path inMounts:(NSArray *)mounts;

/* FreeBSD: the device a mount comes from ("da0" of "/dev/da0p1"), and
 * whether a disk of that name is removable given the da(4) flags text. */
+ (NSString *)diskNameOfMountSource:(NSString *)source;
+ (BOOL)isRemovableBSDDisk:(NSString *)disk daFlags:(NSString *)flags;

@end

#endif
