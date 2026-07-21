/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

#define _GNU_SOURCE
#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <sys/socket.h>
#import <unistd.h>

#if defined(__linux__)
#elif defined(__FreeBSD__) || defined(__OpenBSD__) || defined(__NetBSD__)
#import <sys/sysctl.h>
#import <sys/param.h>
#elif defined(__APPLE__)
#import <libproc.h>
#endif

#import "DockService.h"
#import "Dock.h"
#import "DockIcon.h"

NSString * const kDockServiceName = @"DockIcon";

static id connKey(NSConnection *conn)
{
  return [NSValue valueWithNonretainedObject:conn];
}

static pid_t pidForConnection(NSConnection *conn)
{
  // Try sendPort (client's port) first - it may contain the client's PID
  NSPort *port = [conn sendPort];
  if (port == nil)
    port = [conn receivePort];

  if (port == nil)
    return -1;

  // Try socket FD (NSSocketPort) - Linux only; BSDs use NSMessagePort
  NSInteger fd = -1;
  NSInteger count = 0;
  [(id)port getFds:&fd count:&count];
#if defined(__linux__) && defined(SO_PEERCRED)
  if (count >= 1 && fd >= 0)
    {
      struct ucred cred;
      socklen_t len = sizeof(cred);
      if (getsockopt(fd, SOL_SOCKET, SO_PEERCRED, &cred, &len) == 0)
        return cred.pid;
    }
#else
  (void)fd;
  (void)count;
#endif

  // Fallback: parse PID from NSMessagePort description
  // Format: "<NSMessagePort ... file name /tmp/.../NSMessagePort/ports/<PID>.<N>"
  NSString *desc = [port description];
  NSRange portsRange = [desc rangeOfString:@"/ports/"];
  if (portsRange.location != NSNotFound)
    {
      NSString *afterPorts = [desc substringFromIndex:NSMaxRange(portsRange)];
      NSRange dotRange = [afterPorts rangeOfString:@"."];
      if (dotRange.location != NSNotFound)
        {
          NSString *pidStr = [afterPorts substringToIndex:dotRange.location];
          return (pid_t)[pidStr intValue];
        }
    }

  return -1;
}

// On OpenBSD, exe path must be obtained via KERN_PROC_ARGV since
// KERN_PROC_PATHNAME is not available.
#if defined(__OpenBSD__)
static NSString *exePathForPID_openbsd(pid_t pid)
{
  int mib[4] = {CTL_KERN, KERN_PROC_ARGS, pid, KERN_PROC_ARGV};
  size_t size = 0;
  if (sysctl(mib, 4, NULL, &size, NULL, 0) != 0 || size <= 0)
    return nil;
  char *buf = malloc(size);
  if (!buf)
    return nil;
  NSString *path = nil;
  if (sysctl(mib, 4, buf, &size, NULL, 0) == 0)
    {
      char **argv = (char **)buf;
      if (argv[0] != NULL)
        path = [NSString stringWithUTF8String:argv[0]];
    }
  free(buf);
  return path;
}
#endif

static NSString *exePathForPID(pid_t pid)
{
  if (pid <= 0)
    return nil;

  char resolved[4096];

#if defined(__linux__)
  {
    char exeLink[64];
    snprintf(exeLink, sizeof(exeLink), "/proc/%d/exe", pid);
    ssize_t len = readlink(exeLink, resolved, sizeof(resolved) - 1);
    if (len <= 0)
      return nil;
    resolved[len] = '\0';
    return [NSString stringWithUTF8String:resolved];
  }
#elif defined(__APPLE__)
  {
    int ret = proc_pidpath(pid, resolved, sizeof(resolved));
    if (ret <= 0)
      return nil;
    return [NSString stringWithUTF8String:resolved];
  }
#elif defined(__FreeBSD__) || defined(__NetBSD__)
  {
    int mib[4] = {CTL_KERN, KERN_PROC_ARGS, pid, KERN_PROC_PATHNAME};
    size_t bufsize = sizeof(resolved);
    if (sysctl(mib, 4, resolved, &bufsize, NULL, 0) != 0)
      return nil;
    return [NSString stringWithUTF8String:resolved];
  }
#elif defined(__OpenBSD__)
  {
    return exePathForPID_openbsd(pid);
  }
#else
  return nil;
#endif
}

static NSString *bundlePathForPID(pid_t pid)
{
  if (pid <= 0)
    return nil;

  NSString *path = exePathForPID(pid);
  if (path == nil)
    return nil;

  while (path && [path isEqualToString:@"/"] == NO)
    {
      if ([[path pathExtension] isEqualToString:@"app"])
        return path;
      path = [path stringByDeletingLastPathComponent];
    }
  return nil;
}

static NSString *appNameForPID(pid_t pid)
{
  // Try NSWorkspace launchedApplications (works for running GUI apps)
  NSArray *apps = [[NSWorkspace sharedWorkspace] launchedApplications];
  for (NSDictionary *app in apps)
    {
      if ([[app objectForKey:@"NSApplicationProcessIdentifier"] intValue] == pid)
        {
          return [app objectForKey:@"NSApplicationName"];
        }
    }

  // Fallback: extract app name from bundle path
  NSString *bundlePath = bundlePathForPID(pid);
  if (bundlePath)
    {
      NSString *name = [[bundlePath lastPathComponent] stringByDeletingPathExtension];
      if (name && [name length] > 0)
        return name;

      // Try reading from Info.plist
      NSString *plistPath = [bundlePath stringByAppendingPathComponent:@"Info.plist"];
      NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:plistPath];
      NSString *bundleName = [info objectForKey:@"CFBundleName"];
      if (bundleName)
        return bundleName;
    }

#if defined(__linux__)
  {
    char cmd[64];
    snprintf(cmd, sizeof(cmd), "/proc/%d/comm", pid);
    FILE *f = fopen(cmd, "r");
    if (f)
      {
        char buf[256] = {0};
        if (fgets(buf, sizeof(buf), f))
          {
            size_t len = strlen(buf);
            if (len > 0 && buf[len - 1] == '\n')
              buf[len - 1] = '\0';
            fclose(f);
            return [NSString stringWithUTF8String:buf];
          }
        fclose(f);
      }
  }
#elif defined(__FreeBSD__) || defined(__NetBSD__)
#ifdef KERN_PROC_COMM
  {
    int mib[4] = {CTL_KERN, KERN_PROC_ARGS, pid, KERN_PROC_COMM};
    char buf[256];
    size_t bufsize = sizeof(buf);
    if (sysctl(mib, 4, buf, &bufsize, NULL, 0) == 0)
      return [NSString stringWithUTF8String:buf];
  }
#endif
#elif defined(__OpenBSD__)
  {
    NSString *exePath = exePathForPID_openbsd(pid);
    return [exePath lastPathComponent];
  }
#endif

  return nil;
}

/* Proxy that stores calling connection in thread dictionary before forwarding */
@interface DOConnectionProxy : NSObject
{
  id _target;
  NSConnection *_connection;
}
- (id)initWithTarget:(id)target connection:(NSConnection *)conn;
@end

@implementation DOConnectionProxy

- (id)initWithTarget:(id)target connection:(NSConnection *)conn
{
  self = [super init];
  if (self)
    {
      _target = target;
      _connection = conn;
    }
  return self;
}

- (BOOL)respondsToSelector:(SEL)sel
{
  return [_target respondsToSelector:sel];
}

- (NSMethodSignature *)methodSignatureForSelector:(SEL)sel
{
  return [_target methodSignatureForSelector:sel];
}

- (void)forwardInvocation:(NSInvocation *)inv
{
  [[[NSThread currentThread] threadDictionary] setObject:_connection
                                                   forKey:@"DockServiceCallingConnection"];
  [inv invokeWithTarget:_target];
  [[[NSThread currentThread] threadDictionary] removeObjectForKey:@"DockServiceCallingConnection"];
}

@end

@interface DockServiceImplementation : NSObject <DockService>
{
  Dock *_dock;
  NSMutableDictionary *_connections;
}
- (id)initWithDock:(Dock *)dock;
@end

@implementation DockServiceImplementation

- (id)initWithDock:(Dock *)dock
{
  self = [super init];
  if (self)
    {
      _dock = dock;
      _connections = [NSMutableDictionary new];
      [[NSNotificationCenter defaultCenter] addObserver:self
                                               selector:@selector(connectionDidDie:)
                                                   name:NSConnectionDidDieNotification
                                                 object:nil];
    }
  return self;
}

- (void)dealloc
{
  [[NSNotificationCenter defaultCenter] removeObserver:self];
  RELEASE(_connections);
  [super dealloc];
}

- (void)connectionDidDie:(NSNotification *)notif
{
  NSConnection *deadConn = [notif object];
  if (deadConn)
    {
      [_connections removeObjectForKey:connKey(deadConn)];
    }
}

- (BOOL)connection:(NSConnection *)ancestor shouldMakeNewConnection:(NSConnection *)newConn
{
  pid_t pid = pidForConnection(newConn);
  NSString *appName = nil;
  if (pid > 0)
    appName = appNameForPID(pid);
  if (appName == nil || [appName length] == 0)
    {
      appName = [NSString stringWithFormat:@"pid-%d", (int)pid];
    }
  [_connections setObject:appName forKey:connKey(newConn)];

  DOConnectionProxy *proxy;
  proxy = [[DOConnectionProxy alloc] initWithTarget:self connection:newConn];
  [newConn setRootObject:proxy];
  [proxy release];
  return YES;
}

- (DockIcon *)iconForCaller
{
  NSConnection *conn;
  conn = [[[NSThread currentThread] threadDictionary] objectForKey:@"DockServiceCallingConnection"];
  if (conn == nil)
    return nil;

  NSString *appName = [_connections objectForKey:connKey(conn)];
  if (appName == nil)
    return nil;

  DockIcon *icon = [_dock iconForApplicationPath:appName];
  if (icon == nil)
    {
      pid_t pid = pidForConnection(conn);
      NSString *appPath = bundlePathForPID(pid);
      if (appPath == nil)
        appPath = [[NSWorkspace sharedWorkspace] fullPathForApplication:appName];
      if (appPath)
        {
          icon = [_dock addIconForApplicationAtPath:appPath withName:appName atIndex:-1];
          if (icon)
            {
              [icon setLaunched:YES];
              [_dock tile];
            }
        }
    }
  return icon;
}

- (void)setBadgeCount:(int64_t)count
{
  DockIcon *icon = [self iconForCaller];
  if (icon)
    {
      [icon setBadgeCount:MAX(0, count)];
      [icon setCountVisible:YES];
    }
}

- (void)setCountVisible:(BOOL)visible
{
  DockIcon *icon = [self iconForCaller];
  if (icon)
    {
      [icon setCountVisible:visible];
    }
}

- (void)setProgressValue:(double)value
{
  DockIcon *icon = [self iconForCaller];
  if (icon)
    {
      [icon setProgressValue:fmax(-1.0, fmin(1.0, value))];
      [icon setProgressVisible:YES];
    }
}

- (void)setProgressVisible:(BOOL)visible
{
  DockIcon *icon = [self iconForCaller];
  if (icon)
    {
      [icon setProgressVisible:visible];
    }
}

- (void)setUrgent:(BOOL)urgent
{
  DockIcon *icon = [self iconForCaller];
  if (icon)
    {
      [icon setUrgent:urgent];
    }
}

- (void)clearAll
{
  DockIcon *icon = [self iconForCaller];
  if (icon)
    {
      [icon setCountVisible:NO];
      [icon setProgressVisible:NO];
      [icon setUrgent:NO];
    }
}

@end

static DockServiceImplementation *sharedService = nil;

void DockServiceStart(id dock)
{
  if (sharedService == nil)
    {
      sharedService = [[DockServiceImplementation alloc] initWithDock:dock];
      NSConnection *conn = [NSConnection defaultConnection];
      [conn setRootObject:sharedService];
      [conn setDelegate:sharedService];
      [conn registerName:kDockServiceName];
    }
}

void DockServiceStop(void)
{
  if (sharedService)
    {
      DESTROY(sharedService);
    }
}

NSString *DockServiceAppNameFromUri(NSString *appUri)
{
  NSString *name = appUri;
  NSRange prefixRange = [name rangeOfString:@"application://"];
  if (prefixRange.location != NSNotFound)
    {
      name = [name substringFromIndex:NSMaxRange(prefixRange)];
    }
  if ([name hasSuffix:@".desktop"])
    {
      name = [name substringToIndex:[name length] - [@".desktop" length]];
    }
  return name;
}

void DockServiceApplyProperties(NSDictionary *properties, DockIcon *icon)
{
  NSNumber *countVal = [properties objectForKey:@"count"];
  NSNumber *progressVal = [properties objectForKey:@"progress"];
  NSNumber *countVis = [properties objectForKey:@"count-visible"];
  NSNumber *progressVis = [properties objectForKey:@"progress-visible"];
  NSNumber *urgentVal = [properties objectForKey:@"urgent"];

  if (countVal)
    {
      int64_t clamped = MAX(0, [countVal longLongValue]);
      [icon setBadgeCount:clamped];
    }
  if (countVis)
    {
      [icon setCountVisible:[countVis boolValue]];
    }
  if (progressVal)
    {
      double clamped = fmax(-1.0, fmin(1.0, [progressVal doubleValue]));
      [icon setProgressValue:clamped];
    }
  if (progressVis)
    {
      [icon setProgressVisible:[progressVis boolValue]];
    }
  if (urgentVal)
    {
      [icon setUrgent:[urgentVal boolValue]];
    }
}
