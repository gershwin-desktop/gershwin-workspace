/*
 * GWUnmountHelper.m
 *
 * Copyright (c) 2026 Simon Peter
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "GWUnmountHelper.h"
#import <AppKit/AppKit.h>

@implementation GWUnmountHelper

+ (NSString *)findSudoPath
{
  /* Try common sudo locations (varies by OS) */
  NSArray *sudoPaths = @[
    @"/usr/bin/sudo",           // Linux, most BSD
    @"/usr/local/bin/sudo",     // FreeBSD, pkgsrc
    @"/opt/local/bin/sudo"      // MacPorts
  ];
  
  NSFileManager *fm = [NSFileManager defaultManager];
  for (NSString *path in sudoPaths) {
    if ([fm isExecutableFileAtPath:path]) {
      return path;
    }
  }
  
  /* Fallback: assume in PATH */
  return @"sudo";
}

+ (BOOL)unmountAndEjectPath:(NSString *)mountPoint
{
  return [self unmountPath:mountPoint devicePath:nil eject:YES];
}

+ (BOOL)unmountPath:(NSString *)mountPoint
{
  return [self unmountPath:mountPoint devicePath:nil eject:NO];
}

+ (BOOL)unmountPath:(NSString *)mountPoint eject:(BOOL)shouldEject
{
  return [self unmountPath:mountPoint devicePath:nil eject:shouldEject];
}

+ (BOOL)unmountPath:(NSString *)mountPoint devicePath:(NSString *)devicePath eject:(BOOL)shouldEject
{
  if (!mountPoint || [mountPoint length] == 0) {
    NSLog(@"GWUnmountHelper: Invalid mount point");
    return NO;
  }
  
  if (devicePath) {
    NSLog(@"GWUnmountHelper: Unmounting %@ from %@ (eject=%d)", devicePath, mountPoint, shouldEject);
  } else {
    NSLog(@"GWUnmountHelper: Unmounting %@ (eject=%d)", mountPoint, shouldEject);
  }
  
  BOOL unmounted = NO;
  
  /* For eject, try NSWorkspace unmountAndEjectDeviceAtPath first */
  /* For unmount-only (ISO writing, CDROM burning prep), skip to umount command */
  if (shouldEject) {
    NSWorkspace *ws = [NSWorkspace sharedWorkspace];
    unmounted = [ws unmountAndEjectDeviceAtPath:mountPoint];
    
    if (unmounted) {
      NSLog(@"GWUnmountHelper: Graceful unmount+eject succeeded");
      return YES;
    }
    NSLog(@"GWUnmountHelper: Graceful unmount+eject failed, trying umount command");
  } else {
    NSLog(@"GWUnmountHelper: Unmount-only mode (no eject), using umount command");
  }
  
  /* Try with sudo umount command */
  NSString *sudoPath = [self findSudoPath];
  unmounted = [self runUnmountCommand:sudoPath arguments:@[@"-A", @"-E", @"/bin/umount", mountPoint]];
  
  if (unmounted) {
    NSLog(@"GWUnmountHelper: sudo umount succeeded");
    return YES;
  }
  
  /* Try force unmount */
  NSLog(@"GWUnmountHelper: Normal unmount failed, trying force unmount (sudo umount -f)");
  unmounted = [self runUnmountCommand:sudoPath arguments:@[@"-A", @"-E", @"/bin/umount", @"-f", mountPoint]];
  
  if (unmounted) {
    NSLog(@"GWUnmountHelper: Force unmount succeeded");
    return YES;
  }
  
  /* Last resort: lazy unmount */
  NSLog(@"GWUnmountHelper: Force unmount failed, trying lazy unmount (sudo umount -l)");
  unmounted = [self runUnmountCommand:sudoPath arguments:@[@"-A", @"-E", @"/bin/umount", @"-l", mountPoint]];
  
  if (unmounted) {
    NSLog(@"GWUnmountHelper: Lazy unmount succeeded");
    return YES;
  }
  
  NSLog(@"GWUnmountHelper: ERROR - All unmount attempts failed for %@", mountPoint);
  return NO;
}

+ (BOOL)runUnmountCommand:(NSString *)sudoPath arguments:(NSArray *)arguments
{
  if (!sudoPath || !arguments) {
    NSLog(@"GWUnmountHelper: ERROR - Invalid parameters to runUnmountCommand");
    return NO;
  }
  
  NSTask *task = [[NSTask alloc] init];
  [task setLaunchPath:sudoPath];
  [task setArguments:arguments];
  
  /* Suppress output */
  [task setStandardOutput:[NSFileHandle fileHandleWithNullDevice]];
  [task setStandardError:[NSFileHandle fileHandleWithNullDevice]];
  
  BOOL success = NO;
  
  @try {
    [task launch];
    [task waitUntilExit];
    success = ([task terminationStatus] == 0);
  } @catch (NSException *e) {
    NSLog(@"GWUnmountHelper: Exception running sudo umount: %@", e);
    success = NO;
  } @finally {
    /* Ensure task is always released to prevent segfault */
    DESTROY(task);
  }
  
  return success;
}

@end
