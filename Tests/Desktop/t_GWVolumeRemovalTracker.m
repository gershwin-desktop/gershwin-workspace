/* t_GWVolumeRemovalTracker.m - ObjectTesting coverage for the decision
 * which vanished volumes the desktop reports as "removed without being
 * properly ejected".  Headless, Foundation-only.
 *
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */
#import <Foundation/Foundation.h>
#import "Testing.h"
#import "../../Workspace/Desktop/GWVolumeRemovalTracker.h"

static NSString * const kStick = @"/media/admin/DATATRAVELE";

int main(void)
{
  NSAutoreleasePool *arp = [NSAutoreleasePool new];
  NSDate *t0 = [NSDate dateWithTimeIntervalSinceReferenceDate: 1000.0];
  NSArray *stickOnly = [NSArray arrayWithObject: kStick];

  START_SET("announced unmount")
  {
    GWVolumeRemovalTracker *tr = [[GWVolumeRemovalTracker alloc]
                                   initWithAnnouncementLifetime: 30.0];
    [tr noteUnmountAnnouncedAtPath: kStick date: t0];
    NSArray *r = [tr removalsToReportForVanishedPaths: stickOnly
                                                 date: [t0 dateByAddingTimeInterval: 5.0]];
    PASS([r count] == 0,
         "a volume announced as about to be unmounted (another app's "
         "WillUnmount) is not reported when it disappears 5 s later");
    r = [tr removalsToReportForVanishedPaths: stickOnly
                                        date: [t0 dateByAddingTimeInterval: 6.0]];
    PASS([r count] == 0, "nor on the following watcher tick");
    [tr release];
  }
  END_SET("announced unmount")

  START_SET("unannounced removal")
  {
    GWVolumeRemovalTracker *tr = [[GWVolumeRemovalTracker alloc]
                                   initWithAnnouncementLifetime: 30.0];
    NSArray *twice = [NSArray arrayWithObjects: kStick, kStick, nil];
    NSArray *r = [tr removalsToReportForVanishedPaths: twice date: t0];
    PASS_EQUAL(r, stickOnly,
               "a yanked volume (no announcement) is reported exactly once, "
               "even when it is listed twice in one tick");
    r = [tr confirmedRemovalsAmongPaths: r
                                   date: [t0 dateByAddingTimeInterval: 1.0]];
    PASS_EQUAL(r, stickOnly, "and the deferred confirmation keeps it");
    int i, reported = 0;
    for (i = 1; i <= 5; i++)
      {
        r = [tr removalsToReportForVanishedPaths: stickOnly
                                            date: [t0 dateByAddingTimeInterval: 3.0 * i]];
        reported += (int)[r count];
      }
    PASS(reported == 0,
         "repeated watcher ticks (re-entered from the alert's modal loop) "
         "seeing the same vanished volume add no further alert");
    [tr release];
  }
  END_SET("unannounced removal")

  START_SET("announcement limits")
  {
    GWVolumeRemovalTracker *tr = [[GWVolumeRemovalTracker alloc]
                                   initWithAnnouncementLifetime: 30.0];
    [tr noteUnmountAnnouncedAtPath: kStick date: t0];
    NSArray *r = [tr removalsToReportForVanishedPaths: stickOnly
                                                 date: [t0 dateByAddingTimeInterval: 31.0]];
    PASS_EQUAL(r, stickOnly,
               "an announcement whose unmount never happened expires, so a "
               "later yank of the still-mounted volume alerts");

    [tr noteVolumeMountedAtPath: kStick];
    [tr noteUnmountAnnouncedAtPath: kStick date: t0];
    r = [tr removalsToReportForVanishedPaths: stickOnly
                                        date: [t0 dateByAddingTimeInterval: 1.0]];
    PASS([r count] == 0, "announced removal after a remount is silent");
    [tr noteVolumeMountedAtPath: kStick];
    r = [tr removalsToReportForVanishedPaths: stickOnly
                                        date: [t0 dateByAddingTimeInterval: 2.0]];
    PASS_EQUAL(r, stickOnly,
               "an announcement covers one removal only: the next mount "
               "yanked without one alerts again");

    [tr noteVolumeMountedAtPath: kStick];
    r = [tr removalsToReportForVanishedPaths: stickOnly
                                        date: [t0 dateByAddingTimeInterval: 3.0]];
    [tr noteUnmountAnnouncedAtPath: kStick
                              date: [t0 dateByAddingTimeInterval: 3.2]];
    r = [tr confirmedRemovalsAmongPaths: r
                                   date: [t0 dateByAddingTimeInterval: 4.0]];
    PASS([r count] == 0,
         "an announcement that arrives just after the mount table changed "
         "(distributed notification racing the watcher) still cancels the alert");

    NSArray *root = [NSArray arrayWithObject: @"/"];
    r = [tr removalsToReportForVanishedPaths: root date: t0];
    PASS([r count] == 0, "the root volume is never reported");
    [tr release];
  }
  END_SET("announcement limits")

  [arp release];
  return 0;
}
