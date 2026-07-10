/*
 * DeviceEraseConfirmation.h
 *
 * Shared single-step confirmation dialog for destructive operations on a
 * physical device (e.g., ISO write, disk format).
 *
 * Copyright (c) 2026 Simon Peter
 * SPDX-License-Identifier: BSD-2-Clause
 */

#ifndef DEVICEERASECONFIRMATION_H
#define DEVICEERASECONFIRMATION_H

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>

@class BlockDeviceInfo;

@interface DeviceEraseConfirmation : NSObject
{
  BlockDeviceInfo *_deviceInfo;
  NSString *_isoPath;
  NSString *_mountPoint;
  unsigned long long _isoSize;
  BOOL _isISOWrite;

  BOOL _confirmed;
}

@property (nonatomic, assign, readonly) BOOL confirmed;

+ (instancetype)confirmationForISOWriteWithISOPath:(NSString *)isoPath
                                        deviceInfo:(BlockDeviceInfo *)deviceInfo
                                           isoSize:(unsigned long long)isoSize;

+ (instancetype)confirmationForDiskFormatWithMountPoint:(NSString *)mountPoint
                                              deviceInfo:(BlockDeviceInfo *)deviceInfo;

- (NSModalResponse)runModal;

@end

#endif /* DEVICEERASECONFIRMATION_H */
