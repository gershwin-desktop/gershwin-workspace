/* GWMountWatchState.m
 *
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

#import "GWMountWatchState.h"

void GWMountWatchStateDiff(NSArray *oldPaths, NSArray *newPaths,
                           NSArray **added, NSArray **removed)
{
  NSMutableArray *addedPaths = [NSMutableArray array];
  NSMutableArray *removedPaths = [NSMutableArray array];

  /* Set membership, not nested array scans: the mount table can hold
   * dozens of entries once network shares are involved. */
  NSSet *oldSet = [NSSet setWithArray: (oldPaths ? oldPaths : [NSArray array])];
  NSSet *newSet = [NSSet setWithArray: (newPaths ? newPaths : [NSArray array])];

  for (NSString *path in newSet)
    {
      if (![oldSet containsObject: path])
        {
          [addedPaths addObject: path];
        }
    }

  for (NSString *path in oldSet)
    {
      if (![newSet containsObject: path])
        {
          [removedPaths addObject: path];
        }
    }

  if (added != NULL)
    {
      *added = addedPaths;
    }
  if (removed != NULL)
    {
      *removed = removedPaths;
    }
}
