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

static NSMutableSet *inflightUnmounts = nil;
static NSString *umountPath = nil;
static NSString *sudoPath = nil;

static NSString *resolveInPath(NSString *name)
{
  NSString *pathEnv = [[[NSProcessInfo processInfo] environment] objectForKey:@"PATH"];
  if (!pathEnv)
    return name;

  NSArray *dirs = [pathEnv componentsSeparatedByString:@":"];
  for (NSString *dir in dirs)
    {
      NSString *full = [dir stringByAppendingPathComponent:name];
      if ([[NSFileManager defaultManager] isExecutableFileAtPath:full])
        return full;
    }
  return name;
}

@implementation GWUnmountHelper

+ (void)initialize
{
  if (inflightUnmounts == nil)
    {
      inflightUnmounts = [NSMutableSet new];
      umountPath = [resolveInPath(@"umount") copy];
      sudoPath = [resolveInPath(@"sudo") copy];
    }
}

+ (NSString *)findSudoPath
{
  return sudoPath ?: @"sudo";
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
    NSDebugLLog(@"gwspace", @"GWUnmountHelper: Invalid mount point");
    if (errorString) {
      *errorString = NSLocalizedString(@"Invalid mount point.", @"");
    }
    return NO;
  }
  
  if (devicePath) {
    NSDebugLLog(@"gwspace", @"GWUnmountHelper: Unmounting %@ from %@ (eject=%d)", devicePath, mountPoint, shouldEject);
  } else {
    NSDebugLLog(@"gwspace", @"GWUnmountHelper: Unmounting %@ (eject=%d)", mountPoint, shouldEject);
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
      NSDebugLLog(@"gwspace", @"GWUnmountHelper: Graceful unmount+eject succeeded");
      return YES;
    }
    NSDebugLLog(@"gwspace", @"GWUnmountHelper: Graceful unmount+eject failed, trying umount command");
  } else {
    NSDebugLLog(@"gwspace", @"GWUnmountHelper: Unmount-only mode (no eject), using umount command");
  }

  /* First try unmount without sudo (works for user-mounted volumes). */
  NSString *lastOutput = nil;
  unmounted = [self runCommand:umountPath arguments:@[mountPoint] output:&lastOutput];
  if (unmounted) {
    NSDebugLLog(@"gwspace", @"GWUnmountHelper: umount succeeded (no sudo)");
    return YES;
  }
  if (GWTrimmedString(lastOutput)) {
    NSDebugLLog(@"gwspace", @"GWUnmountHelper: umount (no sudo) failed: %@", GWTrimmedString(lastOutput));
  }

  /* Try with sudo umount command (askpass if configured via env). */
  NSString *sudoPath = [self findSudoPath];
  unmounted = [self runCommand:sudoPath arguments:@[@"-A", @"-E", @"umount", mountPoint] output:&lastOutput];
  
  if (unmounted) {
    NSDebugLLog(@"gwspace", @"GWUnmountHelper: sudo umount succeeded");
    return YES;
  }
  
  /* Try force unmount */
  NSDebugLLog(@"gwspace", @"GWUnmountHelper: Normal unmount failed, trying force unmount (sudo umount -f)");
  unmounted = [self runCommand:sudoPath arguments:@[@"-A", @"-E", @"umount", @"-f", mountPoint] output:&lastOutput];
  
  if (unmounted) {
    NSDebugLLog(@"gwspace", @"GWUnmountHelper: Force unmount succeeded");
    return YES;
  }
  

#if defined(__linux__)
  /* Last resort: lazy unmount (Linux only) */
  NSDebugLLog(@"gwspace", @"GWUnmountHelper: Force unmount failed, trying lazy unmount (sudo umount -l)");
  unmounted = [self runCommand:sudoPath arguments:@[@"-A", @"-E", @"umount", @"-l", mountPoint] output:&lastOutput];

  if (unmounted) {
    NSDebugLLog(@"gwspace", @"GWUnmountHelper: Lazy unmount succeeded");
    return YES;
  }
#endif
  
  if (GWTrimmedString(lastOutput)) {
    NSDebugLLog(@"gwspace", @"GWUnmountHelper: ERROR - All unmount attempts failed for %@: %@", mountPoint, GWTrimmedString(lastOutput));
  } else {
    NSDebugLLog(@"gwspace", @"GWUnmountHelper: ERROR - All unmount attempts failed for %@", mountPoint);
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

+ (void)unmountAndEjectPathAsync:(NSString *)mountPoint
                      completion:(void (^)(BOOL, NSString *))completion
{
  if (!mountPoint || [mountPoint length] == 0)
    {
      if (completion)
        completion(NO, NSLocalizedString(@"Invalid mount point.", @""));
      return;
    }

  /* Prevent concurrent unmount of the same path.  With async execution
   * the main thread is no longer blocked, so a user could click eject
   * multiple times, spawning many background threads — each launching
   * its own sequence of umount commands. */
  @synchronized (inflightUnmounts)
    {
      if ([inflightUnmounts containsObject:mountPoint])
        {
          NSDebugLLog(@"gwspace", @"GWUnmountHelper: unmount already in flight for %@, skipping", mountPoint);
          return;
        }
      [inflightUnmounts addObject:mountPoint];
    }

  NSDictionary *ctx = [NSDictionary dictionaryWithObjectsAndKeys:
                                  mountPoint, @"mountPoint",
                                  [[completion copy] autorelease], @"completion",
                                  nil];
  [self performSelectorInBackground:@selector(_asyncUnmountThreadMain:)
                         withObject:ctx];
}

+ (void)_asyncUnmountThreadMain:(NSDictionary *)ctx
{
  NSAutoreleasePool *pool = [NSAutoreleasePool new];
  NSString *mountPoint = [ctx objectForKey:@"mountPoint"];
  void (^completion)(BOOL, NSString *) = [ctx objectForKey:@"completion"];

  NSString *error = nil;
  BOOL success = [self unmountPath:mountPoint devicePath:nil eject:YES error:&error];

  NSDictionary *result = [NSDictionary dictionaryWithObjectsAndKeys:
                                     [NSNumber numberWithBool:success], @"success",
                                     error ?: @"", @"error",
                                     mountPoint, @"mountPoint",
                                     completion, @"completion",
                                     nil];
  [self performSelectorOnMainThread:@selector(_asyncUnmountCompletion:)
                         withObject:result
                      waitUntilDone:NO];
  [pool drain];
}

+ (void)_asyncUnmountCompletion:(NSDictionary *)result
{
  BOOL success = [[result objectForKey:@"success"] boolValue];
  NSString *error = [result objectForKey:@"error"];
  NSString *mountPoint = [result objectForKey:@"mountPoint"];
  void (^completion)(BOOL, NSString *) = [result objectForKey:@"completion"];

  @synchronized (inflightUnmounts)
    {
      [inflightUnmounts removeObject:mountPoint];
    }

  if (completion)
    {
      completion(success, error);
      [completion release];
    }
}

+ (BOOL)runCommand:(NSString *)launchPath arguments:(NSArray *)arguments output:(NSString **)output
{
  if (output) {
    *output = nil;
  }
  if (!launchPath || [launchPath length] == 0 || !arguments) {
    NSDebugLLog(@"gwspace", @"GWUnmountHelper: ERROR - Invalid parameters to runCommand");
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

    /* Read pipe data incrementally while the process runs to prevent
     * pipe buffer deadlock (when process output > 64KB pipe capacity,
     * the process blocks writing and waitUntilExit hangs forever). */
    NSFileHandle *fh = [pipe fileHandleForReading];
    NSMutableData *accumulatedData = [NSMutableData data];
    NSData *chunk = nil;
    while ((chunk = [fh availableData]) && [chunk length] > 0) {
      [accumulatedData appendData:chunk];
    }
    [task waitUntilExit];
    data = accumulatedData;

    success = ([task terminationStatus] == 0);
  } @catch (NSException *e) {
    NSDebugLLog(@"gwspace", @"GWUnmountHelper: Exception running command %@: %@", launchPath, e);
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
