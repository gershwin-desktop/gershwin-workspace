/* DockAdoption.m
 *
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-2.0-or-later
 */

#import "DockAdoption.h"
#import "GWWindowOwnership.h"

NSString * const DockAdoptionPIDKey = @"DockAdoptionPID";
NSString * const DockAdoptionInstanceKey = @"DockAdoptionInstance";
NSString * const DockAdoptionClassKey = @"DockAdoptionClass";
NSString * const DockAdoptionTitleKey = @"DockAdoptionTitle";
NSString * const DockAdoptionHiddenKey = @"DockAdoptionHidden";
NSString * const DockAdoptionSkipsTaskbarKey = @"DockAdoptionSkipsTaskbar";
NSString * const DockAdoptionPathKey = @"DockAdoptionPath";
NSString * const DockAdoptionNameKey = @"DockAdoptionName";

/* The bundles the windows of one process fit, by the rules every other
 * window question follows too. */
static NSSet *
DockAdoptionCandidates(NSArray *windows, NSDictionary *applications,
                       NSDictionary *classMap)
{
  NSMutableSet *candidates = [NSMutableSet set];
  NSEnumerator *e = [applications keyEnumerator];
  NSString *name;

  while ((name = [e nextObject]) != nil)
    {
      GWWindowOwnership *bundle = [[GWWindowOwnership alloc]
                                    initWithName: name
                                            path: [applications objectForKey: name]
                                     launchedPID: 0
                                      classHints: nil
                                        classMap: classMap
                                        ancestry: NULL];
      NSUInteger i;

      for (i = 0; i < [windows count]; i++)
        {
          NSDictionary *w = [windows objectAtIndex: i];

          if ([bundle ownsWindowPID: [[w objectForKey: DockAdoptionPIDKey] intValue]
                           instance: [w objectForKey: DockAdoptionInstanceKey]
                        windowClass: [w objectForKey: DockAdoptionClassKey]
                              title: [w objectForKey: DockAdoptionTitleKey]])
            {
              [candidates addObject: name];
              break;
            }
        }
      [bundle release];
    }
  return candidates;
}

NSArray *
DockAdoptionPlan(NSArray *clients, NSDictionary *applications,
                 NSDictionary *classMap, NSSet *trackedPaths)
{
  NSMutableArray *plan = [NSMutableArray array];
  NSMutableArray *order = [NSMutableArray array];
  NSMutableDictionary *byPID = [NSMutableDictionary dictionary];
  NSMutableSet *adopted = [NSMutableSet set];
  NSUInteger i;

  for (i = 0; i < [clients count]; i++)
    {
      NSDictionary *w = [clients objectAtIndex: i];
      NSNumber *pid = [w objectForKey: DockAdoptionPIDKey];
      NSMutableArray *windows;

      if ([pid intValue] <= 0)
        continue;
      /* GNUstep applications are adopted from the launched-applications
       * registry, which knows their bundle for certain. */
      if ([[w objectForKey: DockAdoptionClassKey] isEqualToString: @"GNUstep"])
        continue;
      /* Tooltips, splash screens and floating helpers do not stand for the
       * application, neither by their names nor by being on screen. */
      if ([[w objectForKey: DockAdoptionSkipsTaskbarKey] boolValue])
        continue;

      windows = [byPID objectForKey: pid];
      if (windows == nil)
        {
          windows = [NSMutableArray array];
          [byPID setObject: windows forKey: pid];
          [order addObject: pid];
        }
      [windows addObject: w];
    }

  for (i = 0; i < [order count]; i++)
    {
      NSNumber *pid = [order objectAtIndex: i];
      NSArray *windows = [byPID objectForKey: pid];
      NSSet *candidates = DockAdoptionCandidates(windows, applications, classMap);
      NSString *name;
      NSString *path;
      BOOL hidden = YES;
      NSUInteger j;

      if ([candidates count] != 1)
        continue;
      name = [candidates anyObject];
      path = [applications objectForKey: name];
      if ([trackedPaths containsObject: path] || [adopted containsObject: path])
        continue;

      for (j = 0; j < [windows count]; j++)
        {
          if ([[[windows objectAtIndex: j] objectForKey: DockAdoptionHiddenKey] boolValue] == NO)
            hidden = NO;
        }

      [adopted addObject: path];
      [plan addObject: [NSDictionary dictionaryWithObjectsAndKeys:
        path, DockAdoptionPathKey,
        name, DockAdoptionNameKey,
        pid, DockAdoptionPIDKey,
        [NSNumber numberWithBool: hidden], DockAdoptionHiddenKey, nil]];
    }

  return plan;
}
