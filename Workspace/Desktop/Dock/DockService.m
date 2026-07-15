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

NSString * const kDockServiceName = @"com.canonical.Unity.LauncherEntry";
NSString * const kDockObjectPath  = @"/com/canonical/unity/launcherentry";

@interface DockServiceImplementation : NSObject <DockService>
{
@private
  id _dock; // weak ref
  NSMutableDictionary *_entries;
}
- (id)initWithDock:(id)dock;
- (NSString *)appNameFromUri:(NSString *)appUri;
- (void)applyProperties:(NSDictionary *)properties toIcon:(DockIcon *)icon;
@end

@implementation DockServiceImplementation

- (id)initWithDock:(id)dock
{
  self = [super init];
  if (self)
    {
      _dock = dock;
      _entries = [NSMutableDictionary new];
    }
  return self;
}

- (void)dealloc
{
  RELEASE(_entries);
  [super dealloc];
}

- (NSString *)appNameFromUri:(NSString *)appUri
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

- (void)update:(NSString *)appUri properties:(NSDictionary *)properties
{
  if (appUri == nil || properties == nil)
    return;

  NSMutableDictionary *entry = [_entries objectForKey:appUri];
  if (entry == nil)
    {
      entry = [NSMutableDictionary dictionary];
      [_entries setObject:entry forKey:appUri];
    }
  [entry addEntriesFromDictionary:properties];

  NSString *appName = [self appNameFromUri:appUri];
  if (appName == nil)
    return;

  DockIcon *icon = [_dock iconForApplicationName:appName];
  if (icon)
    {
      [self applyProperties:properties toIcon:icon];
    }
}

- (NSDictionary *)query
{
  NSString *appUri = [[_entries allKeys] lastObject];
  if (appUri == nil)
    {
      return @{};
    }
  return @{
    @"appUri": appUri,
    @"properties": [_entries objectForKey:appUri] ?: @{}
  };
}

- (void)applyProperties:(NSDictionary *)properties toIcon:(DockIcon *)icon
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
