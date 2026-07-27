/*
 * GWUnmountHelper.m
 *
 * Copyright (c) 2026 Simon Peter
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "GWUnmountHelper.h"
#import <AppKit/AppKit.h>

/* Set this env var to YES to get verbose NSLog output from this module. */
#define GWUMOUNT_VERBOSE ([[[NSProcessInfo processInfo] environment] objectForKey:@"GWUMOUNT_VERBOSE"] != nil)

static NSString *GWTrimmedString(NSString *s)
{
  if (!s) {
    return nil;
  }
  return [s stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

static NSMutableSet *inflightUnmounts = nil;
static NSString *resolvedUmountPath = nil;
static NSString *resolvedSudoPath = nil;
static NSString *resolvedWhichPath = nil;

/* Checked first, in this order.  Prevents picking up broken wrappers
 * from /System/Library/Tools/ or /Local/Library/Tools/. */
static NSString * const standardPaths[] = {
  @"/usr/sbin",
  @"/usr/bin",
  @"/sbin",
  @"/bin",
};

static NSString *resolveInPath(NSString *name)
{
  for (unsigned i = 0; i < sizeof(standardPaths) / sizeof(standardPaths[0]); i++)
    {
      NSString *full = [standardPaths[i] stringByAppendingPathComponent:name];
      if ([[NSFileManager defaultManager] isExecutableFileAtPath:full])
        return full;
    }

  NSString *pathEnv = [[[NSProcessInfo processInfo] environment] objectForKey:@"PATH"];
  if (pathEnv)
    {
      NSArray *dirs = [pathEnv componentsSeparatedByString:@":"];
      for (NSString *dir in dirs)
        {
          NSString *full = [dir stringByAppendingPathComponent:name];
          if ([[NSFileManager defaultManager] isExecutableFileAtPath:full])
            {
              if (GWUMOUNT_VERBOSE)
                NSLog(@"GWUnmountHelper: resolveInPath(%@) falling back to PATH entry: %@", name, full);
              return full;
            }
        }
    }
  if (GWUMOUNT_VERBOSE)
    NSLog(@"GWUnmountHelper: resolveInPath(%@) NOT FOUND in any standard dir or PATH, returning bare name", name);
  return name;
}

@implementation GWUnmountHelper

+ (void)initialize
{
  if (inflightUnmounts == nil)
    {
      inflightUnmounts = [NSMutableSet new];
      resolvedUmountPath = [resolveInPath(@"umount") copy];
      resolvedSudoPath = [resolveInPath(@"sudo") copy];
      resolvedWhichPath = [resolveInPath(@"which") copy];

      if (GWUMOUNT_VERBOSE)
        {
          NSLog(@"GWUnmountHelper: initialize resolved paths:");
          NSLog(@"GWUnmountHelper:   umount -> %@", resolvedUmountPath);
          NSLog(@"GWUnmountHelper:   sudo   -> %@", resolvedSudoPath);
          NSLog(@"GWUnmountHelper:   which  -> %@", resolvedWhichPath);
        }
    }
}

+ (NSString *)findSudoPath
{
  return resolvedSudoPath ?: @"sudo";
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
    if (GWUMOUNT_VERBOSE) NSLog(@"GWUnmountHelper: unmountPath called with nil/empty mountPoint");
    if (errorString) {
      *errorString = NSLocalizedString(@"Invalid mount point.", @"");
    }
    return NO;
  }

  if (GWUMOUNT_VERBOSE)
    NSLog(@"GWUnmountHelper: unmountPath \"%@\" devicePath=\"%@\" eject=%d thread=%@",
          mountPoint, devicePath, shouldEject, [NSThread currentThread]);

  /* Tell interested views (Desktop) that this unmount is expected. */
  NSDictionary *unmountInfo = [NSDictionary dictionaryWithObject:mountPoint forKey:@"NSDevicePath"];
  [[NSNotificationCenter defaultCenter]
    postNotificationName:NSWorkspaceWillUnmountNotification
                  object:[NSWorkspace sharedWorkspace]
                userInfo:unmountInfo];

  BOOL unmounted = NO;

  if (shouldEject) {
    NSWorkspace *ws = [NSWorkspace sharedWorkspace];
    if (GWUMOUNT_VERBOSE) NSLog(@"GWUnmountHelper: trying NSWorkspace unmountAndEjectDeviceAtPath:%@", mountPoint);
    unmounted = [ws unmountAndEjectDeviceAtPath:mountPoint];
    if (unmounted) {
      if (GWUMOUNT_VERBOSE) NSLog(@"GWUnmountHelper: NSWorkspace unmount succeeded");
      return YES;
    }
    if (GWUMOUNT_VERBOSE) NSLog(@"GWUnmountHelper: NSWorkspace unmount failed, falling through to umount");
  }

  NSString *lastOutput = nil;

  /* ----- step 1: umount (no sudo) ----- */
  if (GWUMOUNT_VERBOSE)
    NSLog(@"GWUnmountHelper: step1: %@ %@", resolvedUmountPath, [mountPoint description]);
  unmounted = [self runCommand:resolvedUmountPath arguments:@[mountPoint] output:&lastOutput];
  if (unmounted) {
    if (GWUMOUNT_VERBOSE) NSLog(@"GWUnmountHelper: step1 succeeded");
    return YES;
  }
  if (GWUMOUNT_VERBOSE)
    NSLog(@"GWUnmountHelper: step1 failed (status=non-zero) output=%@", GWTrimmedString(lastOutput));

  /* ----- step 2: sudo -A -E umount ----- */
  if (GWUMOUNT_VERBOSE)
    NSLog(@"GWUnmountHelper: step2: %@ -A -E %@ %@", resolvedSudoPath, resolvedUmountPath, mountPoint);
  unmounted = [self runCommand:resolvedSudoPath arguments:@[@"-A", @"-E", resolvedUmountPath, mountPoint] output:&lastOutput];
  if (unmounted) {
    if (GWUMOUNT_VERBOSE) NSLog(@"GWUnmountHelper: step2 succeeded");
    return YES;
  }
  if (GWUMOUNT_VERBOSE)
    NSLog(@"GWUnmountHelper: step2 failed output=%@", GWTrimmedString(lastOutput));

  /* ----- step 3: sudo -A -E umount -f ----- */
  if (GWUMOUNT_VERBOSE)
    NSLog(@"GWUnmountHelper: step3: %@ -A -E %@ -f %@", resolvedSudoPath, resolvedUmountPath, mountPoint);
  unmounted = [self runCommand:resolvedSudoPath arguments:@[@"-A", @"-E", resolvedUmountPath, @"-f", mountPoint] output:&lastOutput];
  if (unmounted) {
    if (GWUMOUNT_VERBOSE) NSLog(@"GWUnmountHelper: step3 succeeded");
    return YES;
  }
  if (GWUMOUNT_VERBOSE)
    NSLog(@"GWUnmountHelper: step3 failed output=%@", GWTrimmedString(lastOutput));

#if defined(__linux__)
  /* ----- step 4: sudo -A -E umount -l (Linux only) ----- */
  if (GWUMOUNT_VERBOSE)
    NSLog(@"GWUnmountHelper: step4: %@ -A -E %@ -l %@", resolvedSudoPath, resolvedUmountPath, mountPoint);
  unmounted = [self runCommand:resolvedSudoPath arguments:@[@"-A", @"-E", resolvedUmountPath, @"-l", mountPoint] output:&lastOutput];
  if (unmounted) {
    if (GWUMOUNT_VERBOSE) NSLog(@"GWUnmountHelper: step4 succeeded");
    return YES;
  }
  if (GWUMOUNT_VERBOSE)
    NSLog(@"GWUnmountHelper: step4 failed output=%@", GWTrimmedString(lastOutput));
#endif

  if (GWUMOUNT_VERBOSE)
    NSLog(@"GWUnmountHelper: ALL STEPS FAILED for %@ lastOutput=%@", mountPoint, GWTrimmedString(lastOutput));

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
      if (GWUMOUNT_VERBOSE) NSLog(@"GWUnmountHelper: unmountAndEjectPathAsync called with nil/empty path");
      if (completion)
        completion(NO, NSLocalizedString(@"Invalid mount point.", @""));
      return;
    }

  if (GWUMOUNT_VERBOSE)
    NSLog(@"GWUnmountHelper: unmountAndEjectPathAsync \"%@\"", mountPoint);

  @synchronized (inflightUnmounts)
    {
      if ([inflightUnmounts containsObject:mountPoint])
        {
          if (GWUMOUNT_VERBOSE)
            NSLog(@"GWUnmountHelper: inflight guard DROPPED duplicate unmount request for \"%@\"", mountPoint);
          return;
        }
      [inflightUnmounts addObject:mountPoint];
      if (GWUMOUNT_VERBOSE)
        NSLog(@"GWUnmountHelper: inflight guard added \"%@\" (count=%lu)", mountPoint, (unsigned long)[inflightUnmounts count]);
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

  if (GWUMOUNT_VERBOSE)
    NSLog(@"GWUnmountHelper: background thread started for \"%@\"", mountPoint);

  NSString *error = nil;
  BOOL success = [self unmountPath:mountPoint devicePath:nil eject:YES error:&error];

  if (GWUMOUNT_VERBOSE)
    NSLog(@"GWUnmountHelper: background thread done for \"%@\" success=%d error=%@", mountPoint, success, error);

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
      if (GWUMOUNT_VERBOSE)
        NSLog(@"GWUnmountHelper: inflight guard removed \"%@\" (count=%lu)", mountPoint, (unsigned long)[inflightUnmounts count]);
    }

  if (GWUMOUNT_VERBOSE)
    NSLog(@"GWUnmountHelper: completion on main thread success=%d error=\"%@\"", success, error);

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
    if (GWUMOUNT_VERBOSE) NSLog(@"GWUnmountHelper: runCommand called with nil launchPath or arguments");
    return NO;
  }

  if (GWUMOUNT_VERBOSE)
    NSLog(@"GWUnmountHelper: runCommand launchPath=%@ args=%@", launchPath,
          [arguments componentsJoinedByString:@" "]);

  NSTask *task = [[NSTask alloc] init];
  [task setLaunchPath:launchPath];
  [task setArguments:arguments];

  NSPipe *pipe = [NSPipe pipe];
  [task setStandardOutput:pipe];
  [task setStandardError:pipe];

  NSDictionary *env = [[NSProcessInfo processInfo] environment];
  if (env) {
    [task setEnvironment:env];
  }

  BOOL success = NO;
  NSData *data = nil;

  @try {
    [task launch];

    if (GWUMOUNT_VERBOSE)
      NSLog(@"GWUnmountHelper: process launched (pid=%d)", [task processIdentifier]);

    NSFileHandle *fh = [pipe fileHandleForReading];
    NSMutableData *accumulatedData = [NSMutableData data];
    NSData *chunk = nil;
    while ((chunk = [fh availableData]) && [chunk length] > 0) {
      [accumulatedData appendData:chunk];
    }
    [task waitUntilExit];
    data = accumulatedData;

    success = ([task terminationStatus] == 0);

    if (GWUMOUNT_VERBOSE)
      NSLog(@"GWUnmountHelper: process exited status=%d output-length=%lu", [task terminationStatus],
            (unsigned long)[data length]);

  } @catch (NSException *e) {
    if (GWUMOUNT_VERBOSE) NSLog(@"GWUnmountHelper: exception running %@: %@", launchPath, e);
    success = NO;
  } @finally {
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
