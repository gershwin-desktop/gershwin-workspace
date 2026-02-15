/*
 * DiskFormatOperation.m
 *
 * Copyright (c) 2026 Simon Peter
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "DiskFormatOperation.h"
#import "BlockDeviceInfo.h"
#import "../GWUnmountHelper.h"

#import <Foundation/Foundation.h>

@implementation DiskFormatOperation

+ (BlockDeviceInfo *)deviceInfoForMountPoint:(NSString *)mountPoint
                                       error:(NSString **)errorMessage
{
  if (errorMessage) {
    *errorMessage = nil;
  }

  if (!mountPoint || [mountPoint length] == 0) {
    if (errorMessage) {
      *errorMessage = NSLocalizedString(@"Invalid mount point.", @"");
    }
    return nil;
  }

  NSString *partitionPath = [BlockDeviceInfo devicePathForMountPoint:mountPoint];
  if (!partitionPath || [partitionPath length] == 0) {
    if (errorMessage) {
      *errorMessage = NSLocalizedString(@"Cannot determine device for the selected mount point.", @"");
    }
    return nil;
  }

  NSString *devicePath = [BlockDeviceInfo parentDeviceForPartition:partitionPath];
  if (!devicePath) {
    devicePath = partitionPath;
  }

  BlockDeviceInfo *deviceInfo = [BlockDeviceInfo infoForDevicePath:devicePath];
  if (!deviceInfo || !deviceInfo.isValid) {
    if (errorMessage) {
      *errorMessage = NSLocalizedString(@"Cannot read information for the selected device.", @"");
    }
    return nil;
  }

  return deviceInfo;
}

+ (NSString *)trimmedString:(NSString *)value
{
  if (!value) {
    return nil;
  }

  NSString *trimmed = [value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  return [trimmed length] > 0 ? trimmed : nil;
}

+ (NSString *)findExecutableInPATH:(NSString *)name
{
  if (!name || [name length] == 0) {
    return nil;
  }

  NSFileManager *fm = [NSFileManager defaultManager];
  NSDictionary *env = [[NSProcessInfo processInfo] environment];
  NSString *pathValue = [env objectForKey:@"PATH"];
  if (!pathValue || [pathValue length] == 0) {
    return nil;
  }

  NSArray *parts = [pathValue componentsSeparatedByString:@":"];
  for (NSString *dirPath in parts) {
    if ([dirPath length] == 0) {
      continue;
    }
    NSString *candidate = [dirPath stringByAppendingPathComponent:name];
    if ([fm isExecutableFileAtPath:candidate]) {
      return candidate;
    }
  }

  return nil;
}

+ (NSString *)helperPath
{
  NSString *bundleHelper = [[NSBundle mainBundle] pathForResource:@"formatdisk-helper"
                                                           ofType:nil
                                                      inDirectory:@"../Tools"];
  if (bundleHelper && [[NSFileManager defaultManager] isExecutableFileAtPath:bundleHelper]) {
    return bundleHelper;
  }

  return [self findExecutableInPATH:@"formatdisk-helper"];
}

+ (BOOL)runTaskWithLaunchPath:(NSString *)launchPath
                    arguments:(NSArray *)arguments
                       output:(NSString **)outputMessage
{
  NSTask *task = [[NSTask alloc] init];
  NSPipe *outPipe = [NSPipe pipe];
  NSPipe *errPipe = [NSPipe pipe];

  [task setLaunchPath:launchPath];
  [task setArguments:arguments];
  [task setStandardOutput:outPipe];
  [task setStandardError:errPipe];

  BOOL ok = NO;
  NSString *combined = nil;

  @try {
    [task launch];
    [task waitUntilExit];

    NSData *outData = [[outPipe fileHandleForReading] readDataToEndOfFile];
    NSData *errData = [[errPipe fileHandleForReading] readDataToEndOfFile];

    NSString *outString = [[[NSString alloc] initWithData:outData encoding:NSUTF8StringEncoding] autorelease];
    NSString *errString = [[[NSString alloc] initWithData:errData encoding:NSUTF8StringEncoding] autorelease];

    NSMutableString *buffer = [NSMutableString string];
    NSString *trimmedOut = [self trimmedString:outString];
    NSString *trimmedErr = [self trimmedString:errString];

    if (trimmedOut) {
      [buffer appendString:trimmedOut];
    }
    if (trimmedErr) {
      if ([buffer length] > 0) {
        [buffer appendString:@"\n"];
      }
      [buffer appendString:trimmedErr];
    }

    combined = [buffer length] > 0 ? [buffer copy] : nil;
    ok = ([task terminationStatus] == 0);
  }
  @catch (NSException *e) {
    ok = NO;
    combined = [[NSString stringWithFormat:@"%@", [e reason]] copy];
  }
  @finally {
    RELEASE(task);
  }

  if (outputMessage) {
    *outputMessage = [combined autorelease];
  } else {
    [combined autorelease];
  }

  return ok;
}

+ (BOOL)unmountAllPartitionsForDevice:(BlockDeviceInfo *)deviceInfo
                                error:(NSString **)errorMessage
{
  NSArray *mountedPartitions = [deviceInfo mountedPartitions];
  for (PartitionInfo *part in mountedPartitions) {
    if (!part.mountPoint || [part.mountPoint length] == 0) {
      continue;
    }

    /* Skip if it is already unmounted (common when we unmount the selected
       mount point first). */
    NSString *stillMountedDevice = [BlockDeviceInfo devicePathForMountPoint:part.mountPoint];
    if (!stillMountedDevice || [stillMountedDevice length] == 0) {
      continue;
    }

    NSString *unmountError = nil;
    BOOL unmounted = [GWUnmountHelper unmountPath:part.mountPoint
                                       devicePath:part.devicePath
                                            eject:NO
                                            error:&unmountError];
    if (!unmounted) {
      /* If the command reported failure but the mount point is already gone,
         treat it as success (race / already-unmounted cases). */
      NSString *afterDevice = [BlockDeviceInfo devicePathForMountPoint:part.mountPoint];
      if (!afterDevice || [afterDevice length] == 0) {
        continue;
      }

      if (errorMessage) {
        if (unmountError && [unmountError length] > 0) {
          *errorMessage = [NSString stringWithFormat:NSLocalizedString(@"Failed to unmount %@: %@", @""), part.mountPoint, unmountError];
        } else {
          *errorMessage = [NSString stringWithFormat:NSLocalizedString(@"Failed to unmount %@.", @""), part.mountPoint];
        }
      }
      return NO;
    }
  }

  return YES;
}

+ (BOOL)formatMountPoint:(NSString *)mountPoint error:(NSString **)errorMessage
{
  if (errorMessage) {
    *errorMessage = nil;
  }

  if (!mountPoint || [mountPoint length] == 0) {
    if (errorMessage) {
      *errorMessage = NSLocalizedString(@"Invalid mount point.", @"");
    }
    return NO;
  }

  BlockDeviceInfo *deviceInfo = [self deviceInfoForMountPoint:mountPoint error:errorMessage];
  if (!deviceInfo) {
    return NO;
  }

  NSString *devicePath = deviceInfo.devicePath;

  NSString *safetyError = [deviceInfo safetyCheckForWriting];
  if (safetyError) {
    if (errorMessage) {
      *errorMessage = safetyError;
    }
    return NO;
  }

  /* Always try to unmount the selected mount point first, even if partition
     enumeration fails or is incomplete on some platforms. */
  /* Ensure our own process CWD is not inside the target mount. */
  [[NSFileManager defaultManager] changeCurrentDirectoryPath:@"/"];

  NSString *selectedPartition = [BlockDeviceInfo devicePathForMountPoint:mountPoint];
  if (selectedPartition && [selectedPartition length] > 0) {
    NSString *unmountError = nil;
    BOOL unmounted = [GWUnmountHelper unmountPath:mountPoint
                                       devicePath:selectedPartition
                                            eject:NO
                                            error:&unmountError];
    if (!unmounted) {
      if (errorMessage) {
        if (unmountError && [unmountError length] > 0) {
          *errorMessage = [NSString stringWithFormat:NSLocalizedString(@"Failed to unmount %@: %@", @""), mountPoint, unmountError];
        } else {
          *errorMessage = [NSString stringWithFormat:NSLocalizedString(@"Failed to unmount %@.", @""), mountPoint];
        }
      }
      return NO;
    }
  }

  if (![self unmountAllPartitionsForDevice:deviceInfo error:errorMessage]) {
    return NO;
  }

  NSString *helperPath = [self helperPath];
  if (!helperPath) {
    if (errorMessage) {
      *errorMessage = NSLocalizedString(@"Could not find formatdisk-helper. Please reinstall Workspace tools.", @"");
    }
    return NO;
  }

  /* Use sudo -A -E and explicitly set LD_LIBRARY_PATH via a shell wrapper so the
     helper can find libgnustep and other runtime libraries even when sudo
     sanitizes the environment. This mirrors ISOWriteOperation's approach. */
  NSString *sudoPath = [GWUnmountHelper findSudoPath];
  NSString *label = [mountPoint lastPathComponent];
  if (!label || [label length] == 0) {
    label = @"UNTITLED";
  }

  NSString *ldPath = [[[NSProcessInfo processInfo] environment] objectForKey:@"LD_LIBRARY_PATH"];
  if (!ldPath || [ldPath length] == 0) {
    ldPath = @"/System/Library/Libraries";
  }

  /* Build a safe shell command: LD_LIBRARY_PATH=<path> '<helper>' '<device>' '<label>' */
  NSString *helperCommand = [NSString stringWithFormat:@"LD_LIBRARY_PATH=%@ '%@' '%@' '%@'",
                             ldPath, helperPath, devicePath, label];

  NSArray *arguments = [NSArray arrayWithObjects:@"-A", @"-E", @"sh", @"-c", helperCommand, nil];
  NSString *taskOutput = nil;
  BOOL formatted = [self runTaskWithLaunchPath:sudoPath arguments:arguments output:&taskOutput];

  if (!formatted) {
    if (errorMessage) {
      if (taskOutput && [taskOutput length] > 0) {
        *errorMessage = taskOutput;
      } else {
        *errorMessage = NSLocalizedString(@"Formatting failed.", @"");
      }
    }
    return NO;
  }

  NSLog(@"DiskFormatOperation: Successfully formatted %@", devicePath);
  return YES;
}

@end
