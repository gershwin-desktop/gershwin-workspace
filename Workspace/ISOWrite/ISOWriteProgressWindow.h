/* ISOWriteProgressWindow.h
 *
 * Copyright (C) 2026 Free Software Foundation, Inc.
 *
 * Progress window for ISO write operations.
 * Matches the style of existing FileOperationWin.
 *
 * This file is part of the GNUstep Workspace application
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 31 Milk Street #960789 Boston, MA 02196 USA.
 */

#ifndef ISOWRITEPROGRESSWINDOW_H
#define ISOWRITEPROGRESSWINDOW_H

#import <Foundation/Foundation.h>

@class NSWindow;
@class NSTextField;
@class NSProgressIndicator;
@class NSButton;

@protocol ISOWriteProgressDelegate <NSObject>
- (void)progressWindowDidRequestCancel:(id)sender;
@end

/**
 * ISOWriteProgressWindow provides a progress display for ISO write operations.
 * The UI matches the existing file operation progress window style.
 */
@interface ISOWriteProgressWindow : NSObject
{
  NSWindow *_window;
  NSTextField *_statusLabel;
  NSTextField *_fromLabel;
  NSTextField *_fromField;
  NSTextField *_toLabel;
  NSTextField *_toField;
  NSTextField *_progressLabel;
  NSTextField *_speedLabel;
  NSTextField *_etaLabel;
  NSProgressIndicator *_progressIndicator;
  NSButton *_cancelButton;
  
  id<ISOWriteProgressDelegate> _delegate;
}

@property (nonatomic, assign) id<ISOWriteProgressDelegate> delegate;
@property (nonatomic, readonly) NSWindow *window;

/**
 * Initialize the progress window
 */
- (id)init;

/**
 * Show the window
 */
- (void)show;

/**
 * Close the window
 */
- (void)close;

/**
 * Update status text
 */
- (void)setStatus:(NSString *)status;

/**
 * Set source file path
 */
- (void)setSourcePath:(NSString *)path;

/**
 * Set destination device path
 */
- (void)setDestinationPath:(NSString *)path;

/**
 * Set indeterminate mode (spinner)
 */
- (void)setIndeterminate:(BOOL)indeterminate;

/**
 * Update progress (0.0 - 100.0)
 */
- (void)setProgress:(double)progress;

/**
 * Update progress with detailed info
 */
- (void)setProgress:(double)progress
       bytesWritten:(unsigned long long)written
         totalBytes:(unsigned long long)total
       transferRate:(double)bytesPerSecond
                eta:(NSTimeInterval)eta;

/**
 * Cancel button action
 */
- (IBAction)cancelAction:(id)sender;

@end

#endif /* ISOWRITEPROGRESSWINDOW_H */
