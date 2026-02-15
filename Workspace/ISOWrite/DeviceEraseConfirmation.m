/*
 * DeviceEraseConfirmation.m
 *
 * Copyright (c) 2026 Simon Peter
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "DeviceEraseConfirmation.h"
#import "BlockDeviceInfo.h"

#import <AppKit/AppKit.h>
#import <GNUstepBase/GNUstep.h>

#define WINDOW_WIDTH 480
#define WINDOW_HEIGHT 400
#define MARGIN 20
#define BUTTON_WIDTH 100
#define BUTTON_HEIGHT 28

@implementation DeviceEraseConfirmation

@synthesize confirmed = _confirmed;

+ (NSString *)sizeDescription:(unsigned long long)size
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

+ (NSString *)deviceDetailsSectionForDeviceInfo:(BlockDeviceInfo *)deviceInfo
{
  if (!deviceInfo) {
    return @"";
  }

  NSMutableString *message = [NSMutableString string];

  [message appendString:NSLocalizedString(@"TARGET DEVICE:\n", @"")];
  [message appendString:@"---------------------------------------\n"];
  [message appendFormat:NSLocalizedString(@"Device: %@\n", @""), deviceInfo.devicePath];

  if (deviceInfo.vendor && [deviceInfo.vendor length] > 0) {
    [message appendFormat:NSLocalizedString(@"Vendor: %@\n", @""), deviceInfo.vendor];
  }
  if (deviceInfo.model && [deviceInfo.model length] > 0) {
    [message appendFormat:NSLocalizedString(@"Model: %@\n", @""), deviceInfo.model];
  }
  if (deviceInfo.serial && [deviceInfo.serial length] > 0) {
    [message appendFormat:NSLocalizedString(@"Serial: %@\n", @""), deviceInfo.serial];
  }

  [message appendFormat:NSLocalizedString(@"Size: %@\n", @""), [deviceInfo sizeDescription]];
  [message appendFormat:NSLocalizedString(@"Partition Table: %@\n", @""), [deviceInfo partitionTableDescription]];
  [message appendFormat:NSLocalizedString(@"Partitions: %lu\n", @""), (unsigned long)[deviceInfo.partitions count]];

  if (deviceInfo.isRemovable) {
    [message appendString:NSLocalizedString(@"Type: Removable device\n", @"")];
  }

  [message appendString:@"---------------------------------------\n\n"];

  return message;
}

+ (NSString *)partitionsSectionForDeviceInfo:(BlockDeviceInfo *)deviceInfo
{
  if (!deviceInfo) {
    return @"";
  }

  NSMutableString *message = [NSMutableString string];

  if ([deviceInfo.partitions count] > 0) {
    [message appendString:NSLocalizedString(@"ALL PARTITIONS WILL BE DESTROYED:\n", @"")];
    for (PartitionInfo *part in deviceInfo.partitions) {
      NSString *label = part.label ? part.label : NSLocalizedString(@"(unlabeled)", @"");
      NSString *fstype = part.fsType ? part.fsType : NSLocalizedString(@"unknown", @"");
      [message appendFormat:@"  - %@ - %@ [%@]\n",
       [part.devicePath lastPathComponent], label, fstype];
      if (part.isMounted && part.mountPoint && [part.mountPoint length] > 0) {
        [message appendFormat:NSLocalizedString(@"    Currently mounted at: %@\n", @""), part.mountPoint];
      }
    }
    [message appendString:@"\n"];
  } else {
    [message appendString:NSLocalizedString(@"(No existing partitions detected)\n\n", @"")];
  }

  return message;
}

+ (instancetype)confirmationForISOWriteWithISOPath:(NSString *)isoPath
                                        deviceInfo:(BlockDeviceInfo *)deviceInfo
                                           isoSize:(unsigned long long)isoSize
{
  NSString *fileName = [isoPath lastPathComponent];
  if (!fileName) {
    fileName = @"";
  }

  NSMutableString *message = [NSMutableString string];

  [message appendFormat:NSLocalizedString(@"ISO File: %@\n", @""), fileName];
  [message appendFormat:NSLocalizedString(@"ISO Size: %@\n\n", @""), [self sizeDescription:isoSize]];

  [message appendString:NSLocalizedString(@"You are about to write this ISO image directly to a physical device.\n\n", @"")];
  [message appendString:NSLocalizedString(@"THIS OPERATION WILL:\n", @"")];
  [message appendString:NSLocalizedString(@"  - UNMOUNT ALL partitions on the target device\n", @"")];
  [message appendString:NSLocalizedString(@"  - Completely ERASE all data on the target device\n", @"")];
  [message appendString:NSLocalizedString(@"  - Destroy ALL partitions on the device\n", @"")];
  [message appendString:NSLocalizedString(@"  - Overwrite the partition table\n", @"")];
  [message appendString:NSLocalizedString(@"  - Make any existing data UNRECOVERABLE\n\n", @"")];

  [message appendString:[self deviceDetailsSectionForDeviceInfo:deviceInfo]];
  [message appendString:[self partitionsSectionForDeviceInfo:deviceInfo]];

  [message appendString:NSLocalizedString(@"This action CANNOT be undone.\n\n", @"")];
  [message appendString:NSLocalizedString(@"Click \"Write\" to proceed or \"Cancel\" to abort.\n", @"")];

  return [[[self alloc] initWithWindowTitle:NSLocalizedString(@"Confirm ISO Write", @"")
                               actionTitle:NSLocalizedString(@"Write", @"")
                                   message:message] autorelease];
}

+ (instancetype)confirmationForDiskFormatWithMountPoint:(NSString *)mountPoint
                                             deviceInfo:(BlockDeviceInfo *)deviceInfo
{
  NSString *mp = mountPoint ? mountPoint : @"";

  NSMutableString *message = [NSMutableString string];

  [message appendFormat:NSLocalizedString(@"Mount Point: %@\n\n", @""), mp];

  [message appendString:NSLocalizedString(@"You are about to format a physical device as FAT32.\n\n", @"")];
  [message appendString:NSLocalizedString(@"THIS OPERATION WILL:\n", @"")];
  [message appendString:NSLocalizedString(@"  - UNMOUNT ALL partitions on the target device\n", @"")];
  [message appendString:NSLocalizedString(@"  - Completely ERASE all data on the target device\n", @"")];
  [message appendString:NSLocalizedString(@"  - Destroy ALL partitions on the device\n", @"")];
  [message appendString:NSLocalizedString(@"  - Create a new MBR partition table\n", @"")];
  [message appendString:NSLocalizedString(@"  - Create a new FAT32 partition and filesystem\n", @"")];
  [message appendString:NSLocalizedString(@"  - Make any existing data UNRECOVERABLE\n\n", @"")];

  [message appendString:[self deviceDetailsSectionForDeviceInfo:deviceInfo]];
  [message appendString:[self partitionsSectionForDeviceInfo:deviceInfo]];

  [message appendString:NSLocalizedString(@"This action CANNOT be undone.\n\n", @"")];
  [message appendString:NSLocalizedString(@"Click \"Format\" to proceed or \"Cancel\" to abort.\n", @"")];

  return [[[self alloc] initWithWindowTitle:NSLocalizedString(@"Format Disk", @"")
                               actionTitle:NSLocalizedString(@"Format", @"")
                                   message:message] autorelease];
}

- (id)initWithWindowTitle:(NSString *)windowTitle
              actionTitle:(NSString *)actionTitle
                  message:(NSString *)message
{
  self = [super init];
  if (self) {
    _windowTitle = [windowTitle copy];
    _actionTitle = [actionTitle copy];
    _message = [message copy];
    _confirmed = NO;

    [self createWindow];
  }
  return self;
}

- (void)dealloc
{
  RELEASE(_windowTitle);
  RELEASE(_actionTitle);
  RELEASE(_message);
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

  [_window setTitle:_windowTitle ? _windowTitle : @"" ];
  [_window setReleasedWhenClosed:NO];

  NSView *contentView = [_window contentView];

  _warningIcon = [[NSImageView alloc] initWithFrame:NSMakeRect(MARGIN, WINDOW_HEIGHT - 80, 64, 64)];
  [_warningIcon setImage:[NSImage imageNamed:@"NSCaution"]];
  [_warningIcon setImageScaling:NSImageScaleProportionallyUpOrDown];
  [contentView addSubview:_warningIcon];
  RELEASE(_warningIcon);

  _titleLabel = [[NSTextField alloc] initWithFrame:
                 NSMakeRect(MARGIN + 74, WINDOW_HEIGHT - 60, WINDOW_WIDTH - 2*MARGIN - 74, 40)];
  [_titleLabel setBezeled:NO];
  [_titleLabel setDrawsBackground:NO];
  [_titleLabel setEditable:NO];
  [_titleLabel setSelectable:NO];
  [_titleLabel setFont:[NSFont boldSystemFontOfSize:16]];
  [_titleLabel setAlignment:NSLeftTextAlignment];
  [_titleLabel setStringValue:NSLocalizedString(@"WARNING: Data Destruction", @"")];
  [contentView addSubview:_titleLabel];
  RELEASE(_titleLabel);

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

  _cancelButton = [[NSButton alloc] initWithFrame:
                   NSMakeRect(MARGIN, MARGIN, BUTTON_WIDTH, BUTTON_HEIGHT)];
  [_cancelButton setTitle:NSLocalizedString(@"Cancel", @"")];
  [_cancelButton setBezelStyle:NSRoundedBezelStyle];
  [_cancelButton setTarget:self];
  [_cancelButton setAction:@selector(cancel:)];
  [_cancelButton setKeyEquivalent:@"\r"]; /* Return key - default */
  [contentView addSubview:_cancelButton];
  RELEASE(_cancelButton);

  _actionButton = [[NSButton alloc] initWithFrame:
                 NSMakeRect(WINDOW_WIDTH - BUTTON_WIDTH - MARGIN, MARGIN, BUTTON_WIDTH, BUTTON_HEIGHT)];
  [_actionButton setTitle:(_actionTitle ? _actionTitle : @"")];
  [_actionButton setBezelStyle:NSRoundedBezelStyle];
  [_actionButton setTarget:self];
  [_actionButton setAction:@selector(proceed:)];
  [_actionButton setKeyEquivalent:@""];
  [contentView addSubview:_actionButton];
  RELEASE(_actionButton);

  [_messageText setString:(_message ? _message : @"")];
}

- (NSModalResponse)runModal
{
  [_window center];

  NSModalResponse response = [NSApp runModalForWindow:_window];

  [NSObject cancelPreviousPerformRequestsWithTarget:_window];
  [NSObject cancelPreviousPerformRequestsWithTarget:[_window contentView]];

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

- (IBAction)cancel:(id)sender
{
  _confirmed = NO;
  [NSApp stopModalWithCode:NSModalResponseCancel];
}

- (IBAction)proceed:(id)sender
{
  _confirmed = YES;
  [NSApp stopModalWithCode:NSModalResponseOK];
}

@end
