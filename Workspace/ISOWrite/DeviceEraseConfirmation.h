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

@class NSWindow;
@class NSTextField;
@class NSTextView;
@class NSButton;
@class NSImageView;
@class BlockDeviceInfo;

@interface DeviceEraseConfirmation : NSObject
{
  NSString *_windowTitle;
  NSString *_actionTitle;
  NSString *_message;

  BOOL _confirmed;

  NSWindow *_window;
  NSImageView *_warningIcon;
  NSTextField *_titleLabel;
  NSTextView *_messageText;
  NSButton *_cancelButton;
  NSButton *_actionButton;
}

@property (nonatomic, assign, readonly) BOOL confirmed;

+ (instancetype)confirmationForISOWriteWithISOPath:(NSString *)isoPath
                                        deviceInfo:(BlockDeviceInfo *)deviceInfo
                                           isoSize:(unsigned long long)isoSize;

+ (instancetype)confirmationForDiskFormatWithMountPoint:(NSString *)mountPoint
                                             deviceInfo:(BlockDeviceInfo *)deviceInfo;

- (id)initWithWindowTitle:(NSString *)windowTitle
              actionTitle:(NSString *)actionTitle
                  message:(NSString *)message;

- (NSModalResponse)runModal;

- (IBAction)cancel:(id)sender;
- (IBAction)proceed:(id)sender;

@end

#endif /* DEVICEERASECONFIRMATION_H */
