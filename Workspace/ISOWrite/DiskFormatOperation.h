/*
 * DiskFormatOperation.h
 *
 * Copyright (c) 2026 Simon Peter
 * SPDX-License-Identifier: BSD-2-Clause
 */

#ifndef DISKFORMATOPERATION_H
#define DISKFORMATOPERATION_H

#import <Foundation/Foundation.h>

@class BlockDeviceInfo;

@interface DiskFormatOperation : NSObject

+ (BlockDeviceInfo *)deviceInfoForMountPoint:(NSString *)mountPoint
									   error:(NSString **)errorMessage;

+ (BOOL)formatMountPoint:(NSString *)mountPoint error:(NSString **)errorMessage;

@end

#endif /* DISKFORMATOPERATION_H */
