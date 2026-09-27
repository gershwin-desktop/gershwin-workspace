/* t_GWMountWatchStateDiff.m - headless coverage for the pure mount-list
 * diff MPointWatcher's watcher thread hands to the main thread: given an
 * old and a new snapshot of desktop volume paths, which paths were added,
 * which were removed, and that an identical pair changes nothing.  This is
 * the piece that decides whether -mountedVolumesDidChange fires at all, so
 * a bug here would mean icons that never appear/disappear, or a spurious
 * notification on every quiet wakeup.
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */
#import <Foundation/Foundation.h>
#import "Testing.h"
#import "../../Workspace/Desktop/GWMountWatchState.h"

int main(void)
{
  NSAutoreleasePool *arp = [NSAutoreleasePool new];

  {
    NSArray *oldList = [NSArray arrayWithObject: @"/media/usbstick"];
    NSArray *newList = [NSArray arrayWithObjects: @"/media/usbstick", @"/media/sdcard", nil];
    NSArray *added = nil, *removed = nil;

    GWMountWatchStateDiff(oldList, newList, &added, &removed);

    PASS(added != nil && [added containsObject: @"/media/sdcard"] && [added count] == 1,
         "a newly mounted volume is reported as added");
    PASS(removed != nil && [removed count] == 0,
         "nothing is reported removed when only a volume was added");
  }

  {
    NSArray *oldList = [NSArray arrayWithObjects: @"/media/usbstick", @"/media/sdcard", nil];
    NSArray *newList = [NSArray arrayWithObject: @"/media/sdcard"];
    NSArray *added = nil, *removed = nil;

    GWMountWatchStateDiff(oldList, newList, &added, &removed);

    PASS(removed != nil && [removed containsObject: @"/media/usbstick"] && [removed count] == 1,
         "an unmounted volume is reported as removed");
    PASS(added != nil && [added count] == 0,
         "nothing is reported added when only a volume was removed");
  }

  {
    NSArray *sameList = [NSArray arrayWithObjects: @"/media/usbstick", @"/media/sdcard", nil];
    NSArray *added = nil, *removed = nil;

    GWMountWatchStateDiff(sameList, sameList, &added, &removed);

    PASS([added count] == 0 && [removed count] == 0,
         "an identical snapshot reports no change at all");
  }

  {
    /* Both nil inputs (first call, before any snapshot exists) must not
     * crash and must report no change. */
    NSArray *added = nil, *removed = nil;

    GWMountWatchStateDiff(nil, nil, &added, &removed);

    PASS(added != nil && removed != nil && [added count] == 0 && [removed count] == 0,
         "nil old/new snapshots are treated as empty, not a crash");
  }

  [arp release];
  return 0;
}
