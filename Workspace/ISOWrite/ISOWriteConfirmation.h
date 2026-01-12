/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#ifndef ISOWRITECONFIRMATION_H
#define ISOWRITECONFIRMATION_H

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>

@class NSWindow;
@class NSTextField;
@class NSTextView;
@class NSButton;
@class NSImageView;
@class BlockDeviceInfo;

/**
 * ISOWriteConfirmation provides a single-step confirmation dialog
 * for the destructive ISO write operation.
 *
 * Safety features:
 * - Explicit warning about data destruction
 * - Shows device identification info
 * - Cancel button is the default
 * - All information displayed in one dialog
 */
@interface ISOWriteConfirmation : NSObject
{
  NSString *_isoPath;
  BlockDeviceInfo *_deviceInfo;
  unsigned long long _isoSize;
  
  BOOL _confirmed;
  
  /* Window and controls */
  NSWindow *_window;
  NSImageView *_warningIcon;
  NSTextField *_titleLabel;
  NSTextView *_messageText;
  NSButton *_cancelButton;
  NSButton *_nextButton;           /* "Write" button */
}

@property (nonatomic, assign, readonly) BOOL confirmed;

/**
 * Initialize with ISO path and target device info
 */
- (id)initWithISOPath:(NSString *)isoPath
           deviceInfo:(BlockDeviceInfo *)deviceInfo
              isoSize:(unsigned long long)isoSize;

/**
 * Run the modal confirmation dialog.
 * Returns NSModalResponseOK if user confirmed, NSModalResponseCancel otherwise.
 */
- (NSModalResponse)runModal;

/**
 * Action methods for buttons
 */
- (IBAction)cancel:(id)sender;
- (IBAction)write:(id)sender;

@end

#endif /* ISOWRITECONFIRMATION_H */
