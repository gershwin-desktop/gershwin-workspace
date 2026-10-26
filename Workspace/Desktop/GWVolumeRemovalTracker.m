/* GWVolumeRemovalTracker.m
 *
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

#import "GWVolumeRemovalTracker.h"

@implementation GWVolumeRemovalTracker

- (void)dealloc
{
  [announcements release];
  [reported release];
  [super dealloc];
}

- (id)initWithAnnouncementLifetime:(NSTimeInterval)seconds
{
  self = [super init];
  if (self)
    {
      lifetime = seconds;
      announcements = [NSMutableDictionary new];
      reported = [NSMutableSet new];
    }
  return self;
}

- (void)noteUnmountAnnouncedAtPath:(NSString *)path date:(NSDate *)date
{
  if (path == nil || date == nil)
    return;
  [announcements setObject: date forKey: path];
}

- (void)noteVolumeMountedAtPath:(NSString *)path
{
  if (path == nil)
    return;
  /* A new mount is a new removal to judge: an announcement made for the
   * previous mount, or an alert already shown for it, must not decide
   * what happens when this one disappears. */
  [announcements removeObjectForKey: path];
  [reported removeObject: path];
}

/* Consumes a still valid announcement for path.  An announcement covers
 * one removal only, and it expires so that an unmount that was announced
 * but then failed does not silence a later yank of the same volume. */
- (BOOL)consumeAnnouncementForPath:(NSString *)path date:(NSDate *)now
{
  NSDate *announced = [announcements objectForKey: path];

  if (announced == nil)
    return NO;
  [announcements removeObjectForKey: path];
  return ([now timeIntervalSinceDate: announced] < lifetime);
}

- (NSArray *)removalsToReportForVanishedPaths:(NSArray *)vanished
                                         date:(NSDate *)now
{
  NSMutableArray *result = [NSMutableArray array];

  for (NSString *path in vanished)
    {
      if ([path isEqualToString: @"/"] || [result containsObject: path])
        continue;
      /* The alert runs a modal loop in which the mount watcher keeps
       * delivering the same vanished volume; one removal is one alert. */
      if ([reported containsObject: path])
        continue;
      [reported addObject: path];
      if ([self consumeAnnouncementForPath: path date: now])
        continue;
      [result addObject: path];
    }
  return result;
}

- (NSArray *)confirmedRemovalsAmongPaths:(NSArray *)candidates
                                    date:(NSDate *)now
{
  NSMutableArray *result = [NSMutableArray array];

  for (NSString *path in candidates)
    {
      if ([result containsObject: path])
        continue;
      /* The announcement travels through the distributed notification
       * center while the mount table change comes from our own watcher
       * thread, so it can arrive a moment after the volume vanished. */
      if ([self consumeAnnouncementForPath: path date: now])
        continue;
      [result addObject: path];
    }
  return result;
}

@end
