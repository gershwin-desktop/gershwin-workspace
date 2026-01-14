/* ISOWriteProgressWindow.m
 *
 * Copyright (C) 2026 Free Software Foundation, Inc.
 *
 * Progress window for ISO write operations.
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

#import "ISOWriteProgressWindow.h"

#import <AppKit/AppKit.h>
#import <GNUstepBase/GNUstep.h>

#define WINDOW_WIDTH 350
#define WINDOW_HEIGHT 200
#define MARGIN 12
#define LABEL_HEIGHT 17
#define FIELD_HEIGHT 17
#define BUTTON_WIDTH 80
#define BUTTON_HEIGHT 28
#define PROGRESS_HEIGHT 20

@implementation ISOWriteProgressWindow

@synthesize delegate = _delegate;
@synthesize window = _window;

- (id)init
{
  self = [super init];
  if (self) {
    [self createWindow];
  }
  return self;
}

- (void)dealloc
{
  RELEASE(_window);
  [super dealloc];
}

- (void)createWindow
{
  NSRect windowRect = NSMakeRect(0, 0, WINDOW_WIDTH, WINDOW_HEIGHT);
  
  _window = [[NSWindow alloc] initWithContentRect:windowRect
                                        styleMask:(NSTitledWindowMask | NSMiniaturizableWindowMask)
                                          backing:NSBackingStoreBuffered
                                            defer:NO];
  
  [_window setTitle:NSLocalizedString(@"Writing image", @"")];
  [_window setReleasedWhenClosed:NO];
  [_window setLevel:NSFloatingWindowLevel];
  
  NSView *content = [_window contentView];
  CGFloat y = WINDOW_HEIGHT - MARGIN;
  
  /* Status label */
  y -= LABEL_HEIGHT;
  _statusLabel = [self createLabelAt:NSMakeRect(MARGIN, y, WINDOW_WIDTH - 2*MARGIN, LABEL_HEIGHT)
                                text:NSLocalizedString(@"Preparing...", @"")
                                bold:YES];
  [content addSubview:_statusLabel];
  
  y -= LABEL_HEIGHT + 8;
  
  /* From label and field */
  _fromLabel = [self createLabelAt:NSMakeRect(MARGIN, y, 50, FIELD_HEIGHT)
                              text:NSLocalizedString(@"From:", @"")
                              bold:NO];
  [content addSubview:_fromLabel];
  
  _fromField = [self createLabelAt:NSMakeRect(MARGIN + 50, y, WINDOW_WIDTH - 2*MARGIN - 50, FIELD_HEIGHT)
                              text:@""
                              bold:NO];
  [[_fromField cell] setLineBreakMode:NSLineBreakByTruncatingMiddle];
  [content addSubview:_fromField];
  
  y -= FIELD_HEIGHT + 4;
  
  /* To label and field */
  _toLabel = [self createLabelAt:NSMakeRect(MARGIN, y, 50, FIELD_HEIGHT)
                            text:NSLocalizedString(@"To:", @"")
                            bold:NO];
  [content addSubview:_toLabel];
  
  _toField = [self createLabelAt:NSMakeRect(MARGIN + 50, y, WINDOW_WIDTH - 2*MARGIN - 50, FIELD_HEIGHT)
                            text:@""
                            bold:NO];
  [content addSubview:_toField];
  
  y -= PROGRESS_HEIGHT + 12;
  
  /* Progress indicator */
  _progressIndicator = [[NSProgressIndicator alloc] initWithFrame:
                        NSMakeRect(MARGIN, y, WINDOW_WIDTH - 2*MARGIN, PROGRESS_HEIGHT)];
  [_progressIndicator setStyle:NSProgressIndicatorBarStyle];
  [_progressIndicator setIndeterminate:YES];
  [_progressIndicator setMinValue:0.0];
  [_progressIndicator setMaxValue:100.0];
  [content addSubview:_progressIndicator];
  RELEASE(_progressIndicator);
  
  y -= FIELD_HEIGHT + 4;
  
  /* Progress text (percentage and bytes) */
  _progressLabel = [self createLabelAt:NSMakeRect(MARGIN, y, WINDOW_WIDTH/2 - MARGIN, FIELD_HEIGHT)
                                  text:@""
                                  bold:NO];
  [content addSubview:_progressLabel];
  
  /* Speed label */
  _speedLabel = [self createLabelAt:NSMakeRect(WINDOW_WIDTH/2, y, WINDOW_WIDTH/2 - MARGIN, FIELD_HEIGHT)
                               text:@""
                               bold:NO];
  [_speedLabel setAlignment:NSRightTextAlignment];
  [content addSubview:_speedLabel];
  
  y -= FIELD_HEIGHT + 2;
  
  /* ETA label */
  _etaLabel = [self createLabelAt:NSMakeRect(MARGIN, y, WINDOW_WIDTH - 2*MARGIN, FIELD_HEIGHT)
                             text:@""
                             bold:NO];
  [_etaLabel setAlignment:NSCenterTextAlignment];
  [content addSubview:_etaLabel];
  
  /* Cancel button */
  _cancelButton = [[NSButton alloc] initWithFrame:
                   NSMakeRect(WINDOW_WIDTH - BUTTON_WIDTH - MARGIN, MARGIN, BUTTON_WIDTH, BUTTON_HEIGHT)];
  [_cancelButton setTitle:NSLocalizedString(@"Cancel", @"")];
  [_cancelButton setBezelStyle:NSRoundedBezelStyle];
  [_cancelButton setTarget:self];
  [_cancelButton setAction:@selector(cancelAction:)];
  [content addSubview:_cancelButton];
  RELEASE(_cancelButton);
}

- (NSTextField *)createLabelAt:(NSRect)frame text:(NSString *)text bold:(BOOL)bold
{
  NSTextField *label = [[NSTextField alloc] initWithFrame:frame];
  [label setBezeled:NO];
  [label setDrawsBackground:NO];
  [label setEditable:NO];
  [label setSelectable:NO];
  [label setStringValue:text];
  
  if (bold) {
    [label setFont:[NSFont boldSystemFontOfSize:[NSFont systemFontSize]]];
  } else {
    [label setFont:[NSFont systemFontOfSize:[NSFont smallSystemFontSize]]];
  }
  
  return [label autorelease];
}

#pragma mark - Public Methods

- (void)show
{
  [_window center];
  [_window makeKeyAndOrderFront:nil];
}

- (void)close
{
  if ([_progressIndicator isIndeterminate]) {
    [_progressIndicator stopAnimation:self];
  }
  [_window close];
}

- (void)setStatus:(NSString *)status
{
  [_statusLabel setStringValue:status];
}

- (void)setSourcePath:(NSString *)path
{
  [_fromField setStringValue:[path lastPathComponent]];
  [_fromField setToolTip:path];
}

- (void)setDestinationPath:(NSString *)path
{
  [_toField setStringValue:path];
  [_toField setToolTip:path];
}

- (void)setIndeterminate:(BOOL)indeterminate
{
  [_progressIndicator setIndeterminate:indeterminate];
  if (indeterminate) {
    [_progressIndicator startAnimation:self];
  } else {
    [_progressIndicator stopAnimation:self];
  }
}

- (void)setProgress:(double)progress
{
  [_progressIndicator setIndeterminate:NO];
  [_progressIndicator setDoubleValue:progress];
  [_progressLabel setStringValue:[NSString stringWithFormat:@"%.1f%%", progress]];
}

- (void)setProgress:(double)progress
       bytesWritten:(unsigned long long)written
         totalBytes:(unsigned long long)total
       transferRate:(double)bytesPerSecond
                eta:(NSTimeInterval)eta
{
  [_progressIndicator setIndeterminate:NO];
  [_progressIndicator setDoubleValue:progress];
  
  [_progressLabel setStringValue:[NSString stringWithFormat:@"%.1f%% (%@ / %@)",
                                  progress,
                                  [self sizeDescription:written],
                                  [self sizeDescription:total]]];
  
  [_speedLabel setStringValue:[NSString stringWithFormat:@"%@/s",
                               [self sizeDescription:(unsigned long long)bytesPerSecond]]];
  
  if (eta > 0) {
    int hours = (int)(eta / 3600);
    int minutes = (int)((eta - hours * 3600) / 60);
    int seconds = (int)eta % 60;
    
    if (hours > 0) {
      [_etaLabel setStringValue:[NSString stringWithFormat:
                                 NSLocalizedString(@"%d:%02d:%02d remaining", @""),
                                 hours, minutes, seconds]];
    } else {
      [_etaLabel setStringValue:[NSString stringWithFormat:
                                 NSLocalizedString(@"%d:%02d remaining", @""),
                                 minutes, seconds]];
    }
  } else {
    [_etaLabel setStringValue:@""];
  }
}

- (NSString *)sizeDescription:(unsigned long long)size
{
  if (size >= 1000000000000ULL) {
    return [NSString stringWithFormat:@"%.1f TB", (double)size / 1000000000000.0];
  } else if (size >= 1000000000ULL) {
    return [NSString stringWithFormat:@"%.1f GB", (double)size / 1000000000.0];
  } else if (size >= 1000000ULL) {
    return [NSString stringWithFormat:@"%.1f MB", (double)size / 1000000.0];
  } else if (size >= 1000ULL) {
    return [NSString stringWithFormat:@"%.1f KB", (double)size / 1000.0];
  }
  return [NSString stringWithFormat:@"%llu bytes", size];
}

#pragma mark - Actions

- (IBAction)cancelAction:(id)sender
{
  /* Confirm cancellation */
  NSInteger result = NSRunAlertPanel(
    NSLocalizedString(@"Cancel Write?", @""),
    NSLocalizedString(@"Are you sure you want to cancel?\n\nThe target device may be left in an inconsistent state and will need to be reformatted.", @""),
    NSLocalizedString(@"Continue Writing", @""),
    NSLocalizedString(@"Cancel Write", @""),
    nil);
  
  if (result == NSAlertAlternateReturn) {
    if ([_delegate respondsToSelector:@selector(progressWindowDidRequestCancel:)]) {
      [_delegate progressWindowDidRequestCancel:self];
    }
  }
}

@end
