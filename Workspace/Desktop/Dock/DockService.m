/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import "DockService.h"
#import "Dock.h"
#import "DockIcon.h"

@interface NSConnection (DockService)
+ (NSConnection *)currentConnection;
@end

NSString * const kDockServiceName = @"com.canonical.Unity.LauncherEntry";

@interface DockServiceImplementation : NSObject <DockService>
{
@private
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

static id connKey(NSConnection *conn)
{
  return [NSValue valueWithNonretainedObject:conn];
}

- (void)connectionDidDie:(NSNotification *)notif
{
  NSConnection *deadConn = [notif object];
  if (deadConn)
    {
      [_connections removeObjectForKey:connKey(deadConn)];
    }
}

- (void)registerAppWithName:(NSString *)appName
{
  if (appName == nil || [appName length] == 0)
    return;

  NSConnection *conn = [NSConnection currentConnection];
  if (conn == nil)
    return;

  [_connections setObject:appName forKey:connKey(conn)];
}

- (DockIcon *)iconForCaller
{
  NSConnection *conn = [NSConnection currentConnection];
  if (conn == nil)
    return nil;

  NSString *appName = [_connections objectForKey:connKey(conn)];
  if (appName == nil)
    return nil;

  return [_dock iconForApplicationName:appName];
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
