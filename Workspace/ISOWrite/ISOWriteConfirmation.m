/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "ISOWriteConfirmation.h"
#import "BlockDeviceInfo.h"

#import <AppKit/AppKit.h>
#import <GNUstepBase/GNUstep.h>

#define WINDOW_WIDTH 480
#define WINDOW_HEIGHT 400
#define MARGIN 20
#define BUTTON_WIDTH 100
#define BUTTON_HEIGHT 28

@implementation ISOWriteConfirmation

@synthesize confirmed = _confirmed;

- (id)initWithISOPath:(NSString *)isoPath
           deviceInfo:(BlockDeviceInfo *)deviceInfo
              isoSize:(unsigned long long)isoSize
{
  self = [super init];
  if (self) {
    _isoPath = [isoPath copy];
    _deviceInfo = [deviceInfo retain];
    _isoSize = isoSize;
    _confirmed = NO;
    
    [self createWindow];
  }
  return self;
}

- (void)dealloc
{
  RELEASE(_isoPath);
  RELEASE(_deviceInfo);
  RELEASE(_window);
  [super dealloc];
}

- (void)createWindow
{
  NSRect windowRect = NSMakeRect(0, 0, WINDOW_WIDTH, WINDOW_HEIGHT);
  
  _window = [[NSWindow alloc] initWithContentRect:windowRect
                                        styleMask:(NSTitledWindowMask | NSClosableWindowMask)
                                          backing:NSBackingStoreBuffered
                                            defer:NO];
  
  [_window setTitle:NSLocalizedString(@"Confirm ISO Write", @"")];
  [_window setReleasedWhenClosed:NO];
  
  NSView *contentView = [_window contentView];
  
  /* Warning icon */
  _warningIcon = [[NSImageView alloc] initWithFrame:NSMakeRect(MARGIN, WINDOW_HEIGHT - 80, 64, 64)];
  [_warningIcon setImage:[NSImage imageNamed:@"NSCaution"]];
  [_warningIcon setImageScaling:NSImageScaleProportionallyUpOrDown];
  [contentView addSubview:_warningIcon];
  RELEASE(_warningIcon);
  
  /* Title label */
  _titleLabel = [[NSTextField alloc] initWithFrame:
                 NSMakeRect(MARGIN + 74, WINDOW_HEIGHT - 60, WINDOW_WIDTH - 2*MARGIN - 74, 40)];
  [_titleLabel setBezeled:NO];
  [_titleLabel setDrawsBackground:NO];
  [_titleLabel setEditable:NO];
  [_titleLabel setSelectable:NO];
  [_titleLabel setFont:[NSFont boldSystemFontOfSize:16]];
  [_titleLabel setAlignment:NSLeftTextAlignment];
  [contentView addSubview:_titleLabel];
  RELEASE(_titleLabel);
  
  /* Message text view in scroll view */
  NSScrollView *scrollView = [[NSScrollView alloc] initWithFrame:
                              NSMakeRect(MARGIN, 100, WINDOW_WIDTH - 2*MARGIN, WINDOW_HEIGHT - 200)];
  [scrollView setHasVerticalScroller:YES];
  [scrollView setHasHorizontalScroller:NO];
  [scrollView setBorderType:NSBezelBorder];
  [scrollView setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
  
  NSSize contentSize = [scrollView contentSize];
  _messageText = [[NSTextView alloc] initWithFrame:
                  NSMakeRect(0, 0, contentSize.width, contentSize.height)];
  [_messageText setEditable:NO];
  [_messageText setSelectable:YES];
  [_messageText setFont:[NSFont systemFontOfSize:13]];
  [_messageText setMinSize:NSMakeSize(0.0, contentSize.height)];
  [_messageText setMaxSize:NSMakeSize(FLT_MAX, FLT_MAX)];
  [_messageText setVerticallyResizable:YES];
  [_messageText setHorizontallyResizable:NO];
  [_messageText setAutoresizingMask:NSViewWidthSizable];
  [[_messageText textContainer] setContainerSize:NSMakeSize(contentSize.width, FLT_MAX)];
  [[_messageText textContainer] setWidthTracksTextView:YES];
  
  [scrollView setDocumentView:_messageText];
  RELEASE(_messageText);
  [contentView addSubview:scrollView];
  RELEASE(scrollView);
  
  /* Buttons - Only Cancel and Write, no Back */
  /* Cancel button (default - responds to Return/Escape) */
  _cancelButton = [[NSButton alloc] initWithFrame:
                   NSMakeRect(MARGIN, MARGIN, BUTTON_WIDTH, BUTTON_HEIGHT)];
  [_cancelButton setTitle:NSLocalizedString(@"Cancel", @"")];
  [_cancelButton setBezelStyle:NSRoundedBezelStyle];
  [_cancelButton setTarget:self];
  [_cancelButton setAction:@selector(cancel:)];
  [_cancelButton setKeyEquivalent:@"\r"]; /* Return key - make Cancel the default */
  [contentView addSubview:_cancelButton];
  RELEASE(_cancelButton);
  
  /* Write button (NOT default) */
  _nextButton = [[NSButton alloc] initWithFrame:
                 NSMakeRect(WINDOW_WIDTH - BUTTON_WIDTH - MARGIN, MARGIN, BUTTON_WIDTH, BUTTON_HEIGHT)];
  [_nextButton setTitle:NSLocalizedString(@"Write", @"")];
  [_nextButton setBezelStyle:NSRoundedBezelStyle];
  [_nextButton setTarget:self];
  [_nextButton setAction:@selector(write:)];
  [_nextButton setKeyEquivalent:@""]; /* No keyboard shortcut - user must click */
  [contentView addSubview:_nextButton];
  RELEASE(_nextButton);
  
  [self updateUIForCurrentStep];
}

- (void)updateUIForCurrentStep
{
  /* Single-step confirmation - show all info at once */
  [_titleLabel setStringValue:NSLocalizedString(@"WARNING: Data Destruction", @"")];
  
  NSMutableString *message = [NSMutableString string];
  
  /* ISO info */
  [message appendFormat:NSLocalizedString(@"ISO File: %@\n", @""), [_isoPath lastPathComponent]];
  [message appendFormat:NSLocalizedString(@"ISO Size: %@\n\n", @""), [self sizeDescription:_isoSize]];
  
  /* Warning */
  [message appendString:NSLocalizedString(@"You are about to write this ISO image directly to a physical device.\n\n", @"")];
  [message appendString:NSLocalizedString(@"THIS OPERATION WILL:\n", @"")];
  [message appendString:NSLocalizedString(@"  - UNMOUNT ALL partitions on the target device\n", @"")];
  [message appendString:NSLocalizedString(@"  - Completely ERASE all data on the target device\n", @"")];
  [message appendString:NSLocalizedString(@"  - Destroy ALL partitions on the device\n", @"")];
  [message appendString:NSLocalizedString(@"  - Overwrite the partition table\n", @"")];
  [message appendString:NSLocalizedString(@"  - Make any existing data UNRECOVERABLE\n\n", @"")];
  
  /* Device info */
  [message appendString:NSLocalizedString(@"TARGET DEVICE:\n", @"")];
  [message appendString:@"---------------------------------------\n"];
  [message appendFormat:@"Device: %@\n", _deviceInfo.devicePath];
  
  if (_deviceInfo.vendor && [_deviceInfo.vendor length] > 0) {
    [message appendFormat:@"Vendor: %@\n", _deviceInfo.vendor];
  }
  if (_deviceInfo.model && [_deviceInfo.model length] > 0) {
    [message appendFormat:@"Model: %@\n", _deviceInfo.model];
  }
  
  [message appendFormat:@"Size: %@\n", [_deviceInfo sizeDescription]];
  [message appendFormat:@"Partition Table: %@\n", [_deviceInfo partitionTableDescription]];
  [message appendFormat:@"Partitions: %lu\n", (unsigned long)[_deviceInfo.partitions count]];
  
  if (_deviceInfo.isRemovable) {
    [message appendString:@"Type: Removable device\n"];
  }
  
  [message appendString:@"---------------------------------------\n\n"];
  
  /* List partitions that will be destroyed */
  if ([_deviceInfo.partitions count] > 0) {
    [message appendString:NSLocalizedString(@"ALL PARTITIONS WILL BE DESTROYED:\n", @"")];
    for (PartitionInfo *part in _deviceInfo.partitions) {
      NSString *label = part.label ? part.label : @"(unlabeled)";
      NSString *fstype = part.fsType ? part.fsType : @"unknown";
      [message appendFormat:@"  - %@ - %@ [%@]\n", 
       [part.devicePath lastPathComponent], label, fstype];
      if (part.isMounted) {
        [message appendFormat:@"    Currently mounted at: %@\n", part.mountPoint];
      }
    }
    [message appendString:@"\n"];
  } else {
    [message appendString:NSLocalizedString(@"(No existing partitions detected)\n\n", @"")];
  }
  
  [message appendString:NSLocalizedString(@"This action CANNOT be undone.\n\n", @"")];
  [message appendString:NSLocalizedString(@"Click \"Write\" to proceed or \"Cancel\" to abort.\n", @"")];
  
  [_messageText setString:message];
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

#pragma mark - Modal Interface

- (NSModalResponse)runModal
{
  [_window center];
  
  NSModalResponse response = [NSApp runModalForWindow:_window];
  
  /* Cancel any pending delayed performs on the window and its content view hierarchy */
  /* This prevents theme code timers from firing after the window is deallocated */
  [NSObject cancelPreviousPerformRequestsWithTarget:_window];
  [NSObject cancelPreviousPerformRequestsWithTarget:[_window contentView]];
  
  /* Also cancel for all subviews including buttons */
  NSArray *subviews = [[_window contentView] subviews];
  for (NSView *view in subviews) {
    [NSObject cancelPreviousPerformRequestsWithTarget:view];
    if ([view respondsToSelector:@selector(cell)]) {
      id cell = [view performSelector:@selector(cell)];
      if (cell) {
        [NSObject cancelPreviousPerformRequestsWithTarget:cell];
      }
    }
  }
  
  [_window orderOut:nil];
  
  return response;
}

#pragma mark - Button Actions

- (IBAction)cancel:(id)sender
{
  _confirmed = NO;
  [NSApp stopModalWithCode:NSModalResponseCancel];
}

- (IBAction)write:(id)sender
{
  /* User confirmed - proceed with write */
  _confirmed = YES;
  [NSApp stopModalWithCode:NSModalResponseOK];
}

@end
