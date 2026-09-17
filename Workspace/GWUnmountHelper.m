/*
 * GWUnmountHelper.m
 *
 * Copyright (c) 2026 Simon Peter
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "GWUnmountHelper.h"
#import <AppKit/AppKit.h>

static NSString *GWTrimmedString(NSString *s)
{
  if (!s) {
    return nil;
  }
  return [s stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

@implementation GWUnmountHelper

+ (NSString *)findSudoPath
{
  /* Resolve via PATH; do not hardcode absolute paths to binaries. */
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
  return [self unmountPath:mountPoint devicePath:devicePath eject:shouldEject error:NULL];
}

+ (BOOL)unmountPath:(NSString *)mountPoint
          devicePath:(NSString *)devicePath
               eject:(BOOL)shouldEject
               error:(NSString **)errorString
{
  if (!mountPoint || [mountPoint length] == 0) {
    if (errorString) {
      *errorString = NSLocalizedString(@"Invalid mount point.", @"");
    }
    return NO;
  }
  
  if (devicePath) {
  } else {
  }

  /* Tell interested views (Desktop) that this unmount is expected. */
  NSDictionary *unmountInfo = [NSDictionary dictionaryWithObject:mountPoint forKey:@"NSDevicePath"];
  [[NSNotificationCenter defaultCenter]
    postNotificationName:NSWorkspaceWillUnmountNotification
                  object:[NSWorkspace sharedWorkspace]
                userInfo:unmountInfo];
  
  BOOL unmounted = NO;
  
  /* For eject, try NSWorkspace unmountAndEjectDeviceAtPath first */
  /* For unmount-only (ISO writing, CDROM burning prep), skip to umount command */
  if (shouldEject) {
    NSWorkspace *ws = [NSWorkspace sharedWorkspace];
    unmounted = [ws unmountAndEjectDeviceAtPath:mountPoint];
    
    if (unmounted) {
      return YES;
    }
  } else {
  }

  /* First try unmount without sudo (works for user-mounted volumes). */
  NSString *lastOutput = nil;
  unmounted = [self runCommand:@"umount" arguments:@[mountPoint] output:&lastOutput];
  if (unmounted) {
    return YES;
  }
  if (GWTrimmedString(lastOutput)) {
  }

  /* Try with sudo umount command (askpass if configured via env). */
  NSString *sudoPath = [self findSudoPath];
  unmounted = [self runCommand:sudoPath arguments:@[@"-A", @"-E", @"umount", mountPoint] output:&lastOutput];
  
  if (unmounted) {
    return YES;
  }
  
  /* Try force unmount */
  unmounted = [self runCommand:sudoPath arguments:@[@"-A", @"-E", @"umount", @"-f", mountPoint] output:&lastOutput];
  
  if (unmounted) {
    return YES;
  }
  

#if defined(__linux__)
  /* Last resort: lazy unmount (Linux only) */
  unmounted = [self runCommand:sudoPath arguments:@[@"-A", @"-E", @"umount", @"-l", mountPoint] output:&lastOutput];

  if (unmounted) {
    return YES;
  }
#endif
  
  if (GWTrimmedString(lastOutput)) {
  } else {
  }
  if (errorString) {
    if (GWTrimmedString(lastOutput)) {
      *errorString = lastOutput;
    } else {
      *errorString = NSLocalizedString(@"Unmount failed.", @"");
    }
  }
  return NO;
}

+ (BOOL)runCommand:(NSString *)launchPath arguments:(NSArray *)arguments output:(NSString **)output
{
  if (output) {
    *output = nil;
  }
  if (!launchPath || [launchPath length] == 0 || !arguments) {
    return NO;
  }
  
  NSTask *task = [[NSTask alloc] init];
  [task setLaunchPath:launchPath];
  [task setArguments:arguments];

  /* Capture combined stdout/stderr for diagnostics and UI error strings. */
  NSPipe *pipe = [NSPipe pipe];
  [task setStandardOutput:pipe];
  [task setStandardError:pipe];

  /* Ensure askpass works if configured by the session environment. */
  NSDictionary *env = [[NSProcessInfo processInfo] environment];
  if (env) {
    [task setEnvironment:env];
  }
  
  BOOL success = NO;
  NSData *data = nil;
  
  @try {
    [task launch];
    [task waitUntilExit];
    data = [[pipe fileHandleForReading] readDataToEndOfFile];
    success = ([task terminationStatus] == 0);
  } @catch (NSException *e) {
    success = NO;
  } @finally {
    /* Ensure task is always released to prevent segfault */
    DESTROY(task);
  }

  if (output && data && [data length] > 0) {
    NSString *s = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (!s) {
      s = [[NSString alloc] initWithData:data encoding:NSISOLatin1StringEncoding];
    }
    if (s) {
      *output = GWTrimmedString(s);
    }
    DESTROY(s);
  }
  
  return success;
}

@end
