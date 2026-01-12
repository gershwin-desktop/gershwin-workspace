/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#ifndef ISOWRITEOPERATION_H
#define ISOWRITEOPERATION_H

#import <Foundation/Foundation.h>
#import "ISOWriteProgressWindow.h"

@class NSWindow;
@class NSTextField;
@class NSButton;
@class NSProgressIndicator;
@class BlockDeviceInfo;
@class ISOWriteProgressWindow;

/**
 * Operation states for the ISO write process
 */
typedef NS_ENUM(NSInteger, ISOWriteState) {
  ISOWriteStateIdle = 0,
  ISOWriteStateValidating,
  ISOWriteStateConfirming,
  ISOWriteStateUnmounting,
  ISOWriteStateWriting,
  ISOWriteStateVerifying,
  ISOWriteStateCompleted,
  ISOWriteStateFailed,
  ISOWriteStateCancelled
};

/**
 * Protocol for receiving ISO write progress updates
 */
@protocol ISOWriteOperationDelegate <NSObject>
@optional
- (void)isoWriteOperationDidStart:(id)operation;
- (void)isoWriteOperation:(id)operation didUpdateProgress:(double)progress
             bytesWritten:(unsigned long long)bytes
               totalBytes:(unsigned long long)total
               transferRate:(double)bytesPerSecond;
- (void)isoWriteOperationDidComplete:(id)operation;
- (void)isoWriteOperation:(id)operation didFailWithError:(NSString *)error;
- (void)isoWriteOperationWasCancelled:(id)operation;
@end


/**
 * ISOWriteOperation handles writing an ISO image directly to a block device.
 * This is a destructive operation that erases all data on the target device.
 *
 * Safety features:
 * - Validates target is a raw block device (not partition)
 * - Checks ISO size fits on device
 * - Detects and prevents writing to system disks
 * - Requires multi-step user confirmation
 * - Unmounts all partitions before writing
 * - Provides cancellation support
 * - Performs optional verification after write
 */
@interface ISOWriteOperation : NSObject <ISOWriteProgressDelegate>
{
  NSString *_isoPath;
  NSString *_devicePath;
  BlockDeviceInfo *_deviceInfo;
  
  unsigned long long _isoSize;
  unsigned long long _bytesWritten;
  
  ISOWriteState _state;
  BOOL _cancelled;
  BOOL _verifyAfterWrite;
  
  NSDate *_startTime;
  NSTimer *_progressTimer;
  
  id<ISOWriteOperationDelegate> _delegate;
  
  /* Progress window */
  ISOWriteProgressWindow *_progressWindow;
}

@property (nonatomic, copy, readonly) NSString *isoPath;
@property (nonatomic, copy, readonly) NSString *devicePath;
@property (nonatomic, retain, readonly) BlockDeviceInfo *deviceInfo;
@property (nonatomic, assign, readonly) ISOWriteState state;
@property (nonatomic, assign, readonly) unsigned long long bytesWritten;
@property (nonatomic, assign, readonly) unsigned long long isoSize;
@property (nonatomic, assign) BOOL verifyAfterWrite;
@property (nonatomic, assign) id<ISOWriteOperationDelegate> delegate;

/**
 * Check if an ISO file can be written to a device (mount point).
 * Returns nil if valid, or an error message explaining why not.
 */
+ (NSString *)validateISOPath:(NSString *)isoPath
              forMountPoint:(NSString *)mountPoint;

/**
 * Check if a mount point represents a physical block device suitable for ISO writing.
 */
+ (BOOL)isPhysicalDeviceMountPoint:(NSString *)mountPoint;

/**
 * Get the raw block device path for a mount point.
 * Returns nil if not a suitable physical device.
 */
+ (NSString *)devicePathForMountPoint:(NSString *)mountPoint;

/**
 * Initialize an ISO write operation
 */
- (id)initWithISOPath:(NSString *)isoPath
         targetDevice:(NSString *)devicePath;

/**
 * Start the operation with full user confirmation flow.
 * This shows the confirmation dialog and, if confirmed, begins writing.
 */
- (void)startWithConfirmation;

/**
 * Cancel the operation if in progress.
 * The device may be left in an inconsistent state.
 */
- (IBAction)cancel:(id)sender;

/**
 * Show the progress window
 */
- (void)showProgressWindow;

/**
 * Human-readable state description
 */
- (NSString *)stateDescription;

@end

#endif /* ISOWRITEOPERATION_H */
