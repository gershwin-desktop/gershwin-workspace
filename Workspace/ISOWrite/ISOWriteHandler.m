/* ISOWriteHandler.m
 *
 * Copyright (C) 2026 Free Software Foundation, Inc.
 *
 * Handler for detecting and processing ISO file drops onto physical devices.
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

#import "ISOWriteHandler.h"
#import "ISOWriteOperation.h"
#import "BlockDeviceInfo.h"
#import "FSNode.h"

#import <AppKit/AppKit.h>
#import <GNUstepBase/GNUstep.h>

#import <sys/stat.h>

/* Singleton list of active operations */
static NSMutableArray *activeOperations = nil;

@implementation ISOWriteHandler

+ (void)initialize
{
  if (self == [ISOWriteHandler class]) {
    activeOperations = [[NSMutableArray alloc] init];
  }
}

+ (BOOL)isISOFile:(NSString *)path
{
  if (!path || [path length] == 0) {
    return NO;
  }
  
  NSString *ext = [[path pathExtension] lowercaseString];
  
  /* Common ISO/disk image extensions that can be written raw */
  NSSet *isoExtensions = [NSSet setWithObjects:
                          @"iso",
                          @"img",     /* Raw disk image */
                          nil];
  
  return [isoExtensions containsObject:ext];
}

+ (BOOL)isPhysicalDeviceNode:(FSNode *)node
{
  if (!node) {
    NSLog(@"ISOWriteHandler: isPhysicalDeviceNode - node is nil");
    return NO;
  }
  
  /* The node must be a mount point */
  if (![node isMountPoint]) {
    NSLog(@"ISOWriteHandler: isPhysicalDeviceNode - %@ is not a mount point", [node path]);
    return NO;
  }
  
  NSString *path = [node path];
  
  /* Get device path for this mount point (could be partition or raw device) */
  NSString *devicePath = [BlockDeviceInfo devicePathForMountPoint:path];
  if (!devicePath) {
    NSLog(@"ISOWriteHandler: isPhysicalDeviceNode - cannot find device for %@", path);
    return NO;
  }
  
  NSLog(@"ISOWriteHandler: isPhysicalDeviceNode - found device %@ for mountpoint %@", devicePath, path);
  
  /* Check it's a block device */
  struct stat st;
  if (stat([devicePath UTF8String], &st) != 0) {
    NSLog(@"ISOWriteHandler: isPhysicalDeviceNode - cannot stat %@: %s", devicePath, strerror(errno));
    return NO;
  }
  
  if (!S_ISBLK(st.st_mode)) {
    NSLog(@"ISOWriteHandler: isPhysicalDeviceNode - %@ is not a block device", devicePath);
    return NO;
  }
  
  /* If this is a partition, get the parent device */
  NSString *parentDevice = [BlockDeviceInfo parentDeviceForPartition:devicePath];
  if (parentDevice) {
    NSLog(@"ISOWriteHandler: isPhysicalDeviceNode - %@ is a partition, parent device is %@", devicePath, parentDevice);
    devicePath = parentDevice;
  }
  
  /* Get block device info for the parent/raw device */
  BlockDeviceInfo *info = [BlockDeviceInfo infoForDevicePath:devicePath];
  if (!info || !info.isValid) {
    NSLog(@"ISOWriteHandler: isPhysicalDeviceNode - cannot get info for %@", devicePath);
    return NO;
  }
  
  /* Don't allow writing to system disk */
  if (info.isSystemDisk) {
    NSLog(@"ISOWriteHandler: isPhysicalDeviceNode - %@ contains system partitions", devicePath);
    return NO;
  }
  
  /* Don't allow writing to read-only devices */
  if (info.isReadOnly) {
    NSLog(@"ISOWriteHandler: isPhysicalDeviceNode - %@ is read-only", devicePath);
    return NO;
  }
  
  NSLog(@"ISOWriteHandler: isPhysicalDeviceNode - %@ is suitable for ISO writing", devicePath);
  return YES;
}

+ (BOOL)canHandleISODrop:(NSString *)isoPath ontoNode:(FSNode *)targetNode
{
  NSLog(@"ISOWriteHandler: Validating drop of %@ onto %@", [isoPath lastPathComponent], [targetNode path]);

  NSString *reason = [self validationMessageForISODrop:isoPath ontoNode:targetNode];
  if (reason) {
    NSLog(@"ISOWriteHandler: Rejected - %@", reason);
    return NO;
  }

  NSLog(@"ISOWriteHandler: Validation passed - can handle this drop");
  return YES;
}

+ (NSString *)validationMessageForISODrop:(NSString *)isoPath ontoNode:(FSNode *)targetNode
{
  /* Check if it's an ISO file */
  if (![self isISOFile:isoPath]) {
    return NSLocalizedString(@"Not an ISO or supported disk image file.", "");
  }

  /* Check if target is a physical device mount point */
  if (![self isPhysicalDeviceNode:targetNode]) {
    return NSLocalizedString(@"Target is not a physical device mount point.", "");
  }

  /* Check if we can validate the operation */
  NSString *error = [ISOWriteOperation validateISOPath:isoPath
                                         forMountPoint:[targetNode path]];
  if (error) {
    return error; /* return the validation error produced by ISOWriteOperation */
  }

  return nil; /* Valid */
}

+ (BOOL)handleISODrop:(NSString *)isoPath ontoNode:(FSNode *)targetNode
{
  /* Validate first */
  if (![self canHandleISODrop:isoPath ontoNode:targetNode]) {
    return NO;
  }
  
  /* Get device path for this mount point (might be partition) */
  NSString *mountedDevicePath = [BlockDeviceInfo devicePathForMountPoint:[targetNode path]];
  if (!mountedDevicePath) {
    NSLog(@"ISOWriteHandler: handleISODrop - cannot resolve device path");
    return NO;
  }
  
  /* If it's a partition, get the parent device - we'll write to the whole disk */
  NSString *devicePath = [BlockDeviceInfo parentDeviceForPartition:mountedDevicePath];
  if (!devicePath) {
    /* Not a partition, use as-is */
    devicePath = mountedDevicePath;
  }
  
  NSLog(@"ISOWriteHandler: handleISODrop - resolved to physical device %@", devicePath);
  
  /* Check if we already have an operation for this device */
  for (ISOWriteOperation *op in activeOperations) {
    if ([[op devicePath] isEqualToString:devicePath]) {
      NSRunAlertPanel(
        NSLocalizedString(@"Operation In Progress", @""),
        NSLocalizedString(@"An ISO write operation is already in progress for this device.", @""),
        NSLocalizedString(@"OK", @""),
        nil, nil);
      return NO;
    }
  }
  
  /* Check if target filesystem is writable */
  BOOL targetIsWritable = [targetNode isWritable];
  NSLog(@"ISOWriteHandler: Target node %@ writable: %@", [targetNode path], targetIsWritable ? @"YES" : @"NO");
  
  /* Prompt user: "Write ISO to device or copy to folder?" */
  NSString *deviceName = [devicePath lastPathComponent];
  NSString *message;
  
  if ([devicePath isEqualToString:mountedDevicePath]) {
    /* Dropped directly on device */
    if (targetIsWritable) {
      message = [NSString stringWithFormat:
        @"You dropped an ISO file onto a device mount point.\n\n"
        @"Would you like to:\n"
        @"  - Write the ISO image directly to %@ (ALL PARTITIONS on this device will be ERASED and unmounted)\n"
        @"  - Copy the ISO file to the mounted filesystem",
        deviceName];
    } else {
      message = [NSString stringWithFormat:
        @"You dropped an ISO file onto a device mount point.\n\n"
        @"The mounted filesystem is read-only (cannot copy files to it).\n\n"
        @"Do you want to write the ISO image directly to %@?\n"
        @"WARNING: ALL PARTITIONS on this device will be ERASED and unmounted.",
        deviceName];
    }
  } else {
    /* Dropped on a partition - make it clear we'll erase the whole disk */
    if (targetIsWritable) {
      message = [NSString stringWithFormat:
        @"You dropped an ISO file onto a partition mount point.\n\n"
        @"IMPORTANT: Writing will affect the ENTIRE PHYSICAL DEVICE %@\n\n"
        @"Would you like to:\n"
        @"  - Write the ISO image to the entire device %@ (ALL PARTITIONS including this one will be ERASED and unmounted)\n"
        @"  - Copy the ISO file to this partition's filesystem",
        deviceName, deviceName];
    } else {
      message = [NSString stringWithFormat:
        @"You dropped an ISO file onto a partition mount point.\n\n"
        @"The mounted filesystem is read-only (cannot copy files to it).\n\n"
        @"IMPORTANT: Writing will affect the ENTIRE PHYSICAL DEVICE %@\n\n"
        @"Do you want to write the ISO image to device %@?\n"
        @"WARNING: ALL PARTITIONS including this one will be ERASED and unmounted.",
        deviceName, deviceName];
    }
  }
  
  NSInteger choice;
  
  if (targetIsWritable) {
    /* Offer both options, but make Cancel the default (third button) */
    choice = NSRunAlertPanel(
      NSLocalizedString(@"ISO File Dropped", @""),
      message,
      NSLocalizedString(@"Cancel", @""),           /* Default button */
      NSLocalizedString(@"Copy File", @""),        /* Alternate */
      NSLocalizedString(@"Write to Device", @"")); /* Other */
    
    if (choice == NSAlertDefaultReturn) {
      /* User cancelled */
      return YES; /* But we did handle it (by cancelling) */
    }
    
    if (choice == NSAlertAlternateReturn) {
      /* User chose to copy file instead - return NO so normal copy proceeds */
      return NO;
    }
    
    /* If we get here, user chose "Write to Device" (Other button) */
  } else {
    /* Only offer Write or Cancel since filesystem is not writable */
    choice = NSRunAlertPanel(
      NSLocalizedString(@"ISO File Dropped", @""),
      message,
      NSLocalizedString(@"Cancel", @""),           /* Default button */
      NSLocalizedString(@"Write to Device", @""),  /* Alternate */
      nil);                                         /* No third button */
    
    if (choice == NSAlertDefaultReturn) {
      /* User cancelled */
      return YES; /* But we did handle it (by cancelling) */
    }
    
    /* If we get here, user chose "Write to Device" (Alternate button) */
  }
  
  /* User chose to write to device */
  ISOWriteOperation *operation = [[ISOWriteOperation alloc]
                                  initWithISOPath:isoPath
                                  targetDevice:devicePath];
  
  /* Add to active operations */
  @synchronized(activeOperations) {
    [activeOperations addObject:operation];
  }
  
  /* Set up completion handler to remove from active list */
  /* We'll observe completion via a notification or delegate */
  
  /* Start the operation (shows confirmation dialog, then writes) */
  [operation startWithConfirmation];
  
  /* Clean up reference - operation retains itself during execution */
  @synchronized(activeOperations) {
    [activeOperations removeObject:operation];
  }
  RELEASE(operation);
  
  return YES;
}

+ (BOOL)isOperationInProgress
{
  @synchronized(activeOperations) {
    return [activeOperations count] > 0;
  }
}

+ (NSArray *)activeOperations
{
  @synchronized(activeOperations) {
    return [[activeOperations copy] autorelease];
  }
}

@end
