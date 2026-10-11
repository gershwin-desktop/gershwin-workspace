/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

#import <Foundation/Foundation.h>
#import "FinderInfoLocker.h"

#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>
#if defined(__linux__)
#include <linux/fs.h>
#include <sys/ioctl.h>
#endif

const char * const FinderInfoLockHelperFlag = "--set-immutable";

#if defined(UF_IMMUTABLE)
#define GW_BSD_FLAGS 1
#endif

#if defined(GW_BSD_FLAGS)
static NSError *posixError(int err)
{
  return [NSError errorWithDomain: NSPOSIXErrorDomain code: err userInfo: nil];
}
#endif

static NSError *textError(NSString *text)
{
  return [NSError errorWithDomain: @"GWFinderInfoErrorDomain"
                             code: 3
                         userInfo: [NSDictionary dictionaryWithObject: text
                                                               forKey: NSLocalizedDescriptionKey]];
}

#pragma mark - Privileged action

BOOL FinderInfoApplyImmutable(NSString *path, BOOL immutable, long requiredOwner,
                              NSString **failure)
{
#if defined(__linux__) && defined(FS_IMMUTABLE_FL)
  const char *cpath = [path fileSystemRepresentation];
  struct stat st;
  int flags = 0;
  int fd;
  NSString *why = nil;

  if ([path length] == 0 || [path isAbsolutePath] == NO
      || strlen(cpath) != [path lengthOfBytesUsingEncoding: NSUTF8StringEncoding]) {
    why = @"path must be absolute";
  } else if ((fd = open(cpath, O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC)) < 0) {
    /* O_NOFOLLOW makes a symlink fail with ELOOP: refuse it, never follow. */
    why = (errno == ELOOP) ? @"refusing to follow a symbolic link"
                           : [NSString stringWithFormat: @"cannot open: %s", strerror(errno)];
  } else {
    /* Everything below works on the descriptor, so the checked file is the
     * file that is changed even if the path is swapped meanwhile. */
    if (fstat(fd, &st) != 0)
      why = [NSString stringWithFormat: @"cannot stat: %s", strerror(errno)];
    else if (!S_ISREG(st.st_mode) && !S_ISDIR(st.st_mode))
      why = @"only regular files and folders can be locked";
    else if (requiredOwner >= 0 && st.st_uid != (uid_t)requiredOwner)
      why = @"the file belongs to another user";
    else if (ioctl(fd, FS_IOC_GETFLAGS, &flags) != 0)
      why = [NSString stringWithFormat: @"cannot read file flags: %s", strerror(errno)];
    else {
      flags = immutable ? (flags | FS_IMMUTABLE_FL) : (flags & ~FS_IMMUTABLE_FL);
      if (ioctl(fd, FS_IOC_SETFLAGS, &flags) != 0)
        why = [NSString stringWithFormat: @"cannot change file flags: %s", strerror(errno)];
    }
    close(fd);
  }
  if (why != nil && failure != NULL)
    *failure = why;
  return why == nil;
#else
  if (failure != NULL)
    *failure = @"not supported on this system";
  return NO;
#endif
}

int FinderInfoLockHelperMain(const char *argsPlistPath)
{
  NSAutoreleasePool *pool = [NSAutoreleasePool new];
  NSDictionary *args = [NSDictionary dictionaryWithContentsOfFile:
                          [NSString stringWithUTF8String: argsPlistPath]];
  NSString *path = [args objectForKey: @"Path"];
  NSNumber *flag = [args objectForKey: @"Immutable"];
  NSString *failure = nil;
  long owner = -1;
  const char *sudoUid = getenv("SUDO_UID");
  int status = 1;

  if (![path isKindOfClass: [NSString class]] || ![flag isKindOfClass: [NSNumber class]]
      || [args count] != 2) {
    failure = @"malformed arguments";
  } else {
    /* Through sudo the caller is not root: it may only touch its own files.
     * Started as root directly there is no one to protect from. */
    if (geteuid() == 0 && sudoUid != NULL)
      owner = strtol(sudoUid, NULL, 10);
    if (FinderInfoApplyImmutable(path, [flag boolValue], owner, &failure))
      status = 0;
  }
  if (status == 0)
    printf("DONE:\n");
  else
    printf("FATAL:%s\n", [failure UTF8String]);
  fflush(stdout);
  [pool release];
  return status;
}

#pragma mark - Locker

@implementation FinderInfoSystemLocker

+ (BOOL)isSupported
{
#if defined(GW_BSD_FLAGS) || (defined(__linux__) && defined(FS_IMMUTABLE_FL))
  return YES;
#else
  return NO;
#endif
}

- (BOOL)isImmutableAtPath:(NSString *)path
{
#if defined(GW_BSD_FLAGS)
  struct stat st;

  return lstat([path fileSystemRepresentation], &st) == 0 && (st.st_flags & UF_IMMUTABLE) != 0;
#elif defined(__linux__) && defined(FS_IMMUTABLE_FL)
  int fd = open([path fileSystemRepresentation], O_RDONLY | O_NONBLOCK | O_NOFOLLOW | O_CLOEXEC);
  int flags = 0;
  BOOL immutable;

  if (fd < 0)
    return NO;
  /* A file system without attribute flags answers ENOTTY: not locked. */
  immutable = (ioctl(fd, FS_IOC_GETFLAGS, &flags) == 0) && (flags & FS_IMMUTABLE_FL);
  close(fd);
  return immutable;
#else
  return NO;
#endif
}

#if defined(GW_BSD_FLAGS)
- (BOOL)setImmutable:(BOOL)immutable atPath:(NSString *)path error:(NSError **)error
{
  const char *cpath = [path fileSystemRepresentation];
  struct stat st;
  unsigned long flags;

  if (lstat(cpath, &st) != 0) {
    if (error) *error = posixError(errno);
    return NO;
  }
  flags = st.st_flags;
  flags = immutable ? (flags | UF_IMMUTABLE) : (flags & ~(unsigned long)UF_IMMUTABLE);
  if (chflags(cpath, flags) != 0) {
    if (error) *error = posixError(errno);
    return NO;
  }
  return YES;
}
#else
- (BOOL)setImmutable:(BOOL)immutable atPath:(NSString *)path error:(NSError **)error
{
  NSString *executable = [[NSBundle mainBundle] executablePath];
  NSString *argsPath = [NSTemporaryDirectory() stringByAppendingPathComponent:
    [NSString stringWithFormat: @"FinderInfoLock-%d.plist", (int)getpid()]];
  NSDictionary *args = [NSDictionary dictionaryWithObjectsAndKeys:
    path, @"Path", [NSNumber numberWithBool: immutable], @"Immutable", nil];
  /* Escalate in-repo rather than through PackageManager's helper: that
     framework lives in gershwin-components, which is built after Workspace. */
  BOOL needsSudo = (geteuid() != 0);
  NSMutableDictionary *env = [[[[NSProcessInfo processInfo] environment] mutableCopy] autorelease];
  NSTask *task = [[[NSTask alloc] init] autorelease];
  NSPipe *pipe = [NSPipe pipe];
  NSData *out;
  NSString *text;
  BOOL ok;

  if (executable == nil || [args writeToFile: argsPath atomically: YES] == NO) {
    if (error) *error = textError(@"Could not prepare the privileged request.");
    return NO;
  }
  /* Path-only plist: nothing secret, removed as soon as the child is done. */
  [env setObject: @"/System/Library/Tools/SudoAskPass" forKey: @"SUDO_ASKPASS"];
  [env setObject: @"Workspace" forKey: @"ASKPASS_REQUESTER"];
  {
    NSArray *helperArgs = [NSArray arrayWithObjects:
      [NSString stringWithUTF8String: FinderInfoLockHelperFlag], argsPath, nil];

    if (needsSudo) {
      /* A bare name: sudo is in /usr/bin on Linux, elsewhere on other systems. */
      [task setLaunchPath: @"sudo"];
      [task setArguments: [[NSArray arrayWithObjects: @"-A", @"-E", executable, nil]
                            arrayByAddingObjectsFromArray: helperArgs]];
    } else {
      [task setLaunchPath: executable];
      [task setArguments: helperArgs];
    }
  }
  [task setEnvironment: env];
  [task setStandardOutput: pipe];

  @try {
    [task launch];
    out = [[pipe fileHandleForReading] readDataToEndOfFile];
    [task waitUntilExit];
  } @catch (NSException *e) {
    [[NSFileManager defaultManager] removeFileAtPath: argsPath handler: nil];
    if (error) *error = textError([e reason]);
    return NO;
  }
  [[NSFileManager defaultManager] removeFileAtPath: argsPath handler: nil];

  text = [[[NSString alloc] initWithData: out encoding: NSUTF8StringEncoding] autorelease];
  ok = ([task terminationStatus] == 0 && [text hasPrefix: @"DONE:"]);
  if (!ok && error) {
    NSRange r = [text rangeOfString: @"FATAL:"];

    *error = textError(r.location != NSNotFound
      ? [[text substringFromIndex: NSMaxRange(r)] stringByTrimmingCharactersInSet:
           [NSCharacterSet whitespaceAndNewlineCharacterSet]]
      : @"The administrator authorization was refused or failed.");
  }
  return ok;
}
#endif

@end
