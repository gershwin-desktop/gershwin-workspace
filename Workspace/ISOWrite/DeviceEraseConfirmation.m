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

@implementation DeviceEraseConfirmation

@synthesize confirmed = _confirmed;

+ (NSString *)sizeDescription:(unsigned long long)size
{
  if (size >= 1000000000000ULL)
    return [NSString stringWithFormat:@"%.1f TB", (double)size / 1000000000000.0];
  if (size >= 1000000000ULL)
    return [NSString stringWithFormat:@"%.1f GB", (double)size / 1000000000.0];
  if (size >= 1000000ULL)
    return [NSString stringWithFormat:@"%.1f MB", (double)size / 1000000.0];
  if (size >= 1000ULL)
    return [NSString stringWithFormat:@"%.1f KB", (double)size / 1000.0];
  return [NSString stringWithFormat:@"%llu bytes", size];
}

+ (instancetype)confirmationForISOWriteWithISOPath:(NSString *)isoPath
                                        deviceInfo:(BlockDeviceInfo *)deviceInfo
                                           isoSize:(unsigned long long)isoSize
{
  DeviceEraseConfirmation *c = [[self alloc] init];
  if (c) {
    c->_deviceInfo = [deviceInfo retain];
    c->_isoPath = [isoPath copy];
    c->_isoSize = isoSize;
    c->_isISOWrite = YES;
  }
  return [c autorelease];
}

+ (instancetype)confirmationForDiskFormatWithMountPoint:(NSString *)mountPoint
                                              deviceInfo:(BlockDeviceInfo *)deviceInfo
{
  DeviceEraseConfirmation *c = [[self alloc] init];
  if (c) {
    c->_deviceInfo = [deviceInfo retain];
    c->_mountPoint = [mountPoint copy];
    c->_isISOWrite = NO;
  }
  return [c autorelease];
}

- (void)dealloc
{
  RELEASE(_deviceInfo);
  RELEASE(_isoPath);
  RELEASE(_mountPoint);
  [super dealloc];
}

- (NSString *)_deviceDisplayName
{
  if (_deviceInfo.model && [_deviceInfo.model length] > 0)
    return _deviceInfo.model;
  if (_deviceInfo.vendor && [_deviceInfo.vendor length] > 0)
    return _deviceInfo.vendor;
  return [_deviceInfo.devicePath lastPathComponent];
}

- (NSModalResponse)runModal
{
  NSAlert *alert = [[NSAlert alloc] init];

  if (_isISOWrite) {
    NSString *fileName = [_isoPath lastPathComponent] ?: @"";
    NSString *sizeStr = [[self class] sizeDescription:_isoSize];
    [alert setMessageText:[NSString stringWithFormat:
      NSLocalizedString(@"Write ISO to “%@”?", @""), [self _deviceDisplayName]]];
    [alert setInformativeText:[NSString stringWithFormat:
      NSLocalizedString(@"Erases all data on %@ and writes “%@” (%@).\n"
                         "\n"
                         @"Device: %@%@%@\n"
                         "\n"
                         @"Partitions:\n%@"
                         "\n"
                         @"This cannot be undone.",
                         @""),
      _deviceInfo.devicePath, fileName, sizeStr,
      _deviceInfo.devicePath,
      (_deviceInfo.isRemovable ? @" (Removable)" : @""),
      (_deviceInfo.partitionTableDescription ? [NSString stringWithFormat:@", %@", _deviceInfo.partitionTableDescription] : @""),
      [self _partitionsBulletList]]];
  } else {
    [alert setMessageText:[NSString stringWithFormat:
      NSLocalizedString(@"Format “%@”?", @""), [self _deviceDisplayName]]];
    [alert setInformativeText:[NSString stringWithFormat:
      NSLocalizedString(@"Erases all data on %@ and reformats as FAT32.\n"
                         "\n"
                         @"Device: %@%@%@\n"
                         "\n"
                         @"Partitions:\n%@"
                         "\n"
                         @"This cannot be undone.",
                         @""),
      _deviceInfo.devicePath,
      _deviceInfo.devicePath,
      (_deviceInfo.isRemovable ? @" (Removable)" : @""),
      (_deviceInfo.partitionTableDescription ? [NSString stringWithFormat:@", %@", _deviceInfo.partitionTableDescription] : @""),
      [self _partitionsBulletList]]];
  }

  [alert addButtonWithTitle:NSLocalizedString(@"Cancel", @"")];
  [alert addButtonWithTitle:(_isISOWrite
    ? NSLocalizedString(@"Write", @"")
    : NSLocalizedString(@"Format", @""))];

  NSInteger result = [alert runModal];
  DESTROY(alert);

  _confirmed = (result == NSAlertAlternateReturn);
  return _confirmed ? NSModalResponseOK : NSModalResponseCancel;
}

- (NSString *)_partitionsBulletList
{
  if ([_deviceInfo.partitions count] == 0)
    return @"  (none)\n";

  NSMutableString *result = [NSMutableString string];
  for (PartitionInfo *part in _deviceInfo.partitions) {
    NSString *label = part.label ?: NSLocalizedString(@"(unlabeled)", @"");
    NSString *fstype = part.fsType ?: NSLocalizedString(@"unknown", @"");
    [result appendFormat:@"  • %@ — %@ [%@]\n",
      [part.devicePath lastPathComponent], label, fstype];
    if (part.isMounted && part.mountPoint && [part.mountPoint length] > 0)
      [result appendFormat:@"    Mounted at: %@\n", part.mountPoint];
  }
  return result;
}

@end
