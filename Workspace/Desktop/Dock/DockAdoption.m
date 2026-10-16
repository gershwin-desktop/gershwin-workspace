/* DockAdoption.m
 *
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-2.0-or-later
 */

#import "DockAdoption.h"

NSString * const DockAdoptionPIDKey = @"DockAdoptionPID";
NSString * const DockAdoptionInstanceKey = @"DockAdoptionInstance";
NSString * const DockAdoptionClassKey = @"DockAdoptionClass";
NSString * const DockAdoptionTitleKey = @"DockAdoptionTitle";
NSString * const DockAdoptionHiddenKey = @"DockAdoptionHidden";
NSString * const DockAdoptionSkipsTaskbarKey = @"DockAdoptionSkipsTaskbar";
NSString * const DockAdoptionPathKey = @"DockAdoptionPath";
NSString * const DockAdoptionNameKey = @"DockAdoptionName";

/* WM_CLASS is usually the program's name ("brave-origin", "google-chrome",
 * "XTerm") while the bundle is named for people ("Brave Origin", "Google
 * Chrome"); case and word separators are all that differs between them. */
static NSString *
DockAdoptionFolded(NSString *name)
{
  NSMutableString *folded = [NSMutableString stringWithCapacity: [name length]];
  NSUInteger i;

  for (i = 0; i < [name length]; i++)
    {
      unichar c = [name characterAtIndex: i];

      if (c != ' ' && c != '-' && c != '_')
        [folded appendFormat: @"%C", c];
    }
  return [folded lowercaseString];
}

static BOOL
DockAdoptionIsWordCharacter(unichar c)
{
  return [[NSCharacterSet alphanumericCharacterSet] characterIsMember: c];
}

/* The Dock's name matching (-[GWX11ClientSnapshot windowsMatchingName:]):
 * the string begins or ends with the name. Against every bundle at once it
 * also has to end at a word boundary, or a bundle called "Go" would claim
 * every window whose title begins with "Google". */
static BOOL
DockAdoptionHasWordAtEdge(NSString *str, NSString *word)
{
  NSUInteger sl = [str length];
  NSUInteger wl = [word length];

  if (wl == 0 || sl < wl)
    return NO;
  if ([[str substringToIndex: wl] caseInsensitiveCompare: word] == NSOrderedSame
      && (sl == wl || DockAdoptionIsWordCharacter([str characterAtIndex: wl]) == NO))
    return YES;
  /* sl > wl here: an equal-length match was already found above. */
  if ([[str substringFromIndex: sl - wl] caseInsensitiveCompare: word] == NSOrderedSame
      && DockAdoptionIsWordCharacter([str characterAtIndex: sl - wl - 1]) == NO)
    return YES;
  return NO;
}

NSDictionary *
DockAdoptionApplicationsInAppList(NSDictionary *appList)
{
  NSMutableDictionary *named = [NSMutableDictionary dictionary];
  NSEnumerator *e = [appList keyEnumerator];
  id key;

  while ((key = [e nextObject]) != nil)
    {
      id path = [appList objectForKey: key];

      if ([key isKindOfClass: [NSString class]]
          && [path isKindOfClass: [NSString class]]
          && [[key pathExtension] isEqualToString: @"app"])
        [named setObject: path forKey: [key stringByDeletingPathExtension]];
    }
  return named;
}

/* The bundles every window of one process fits: by WM_CLASS first, since a
 * class names the program while a title is whatever the program shows (an
 * xterm titled "Terminal" is not Terminal.app); by name only when no class
 * names a bundle. */
static NSSet *
DockAdoptionCandidates(NSArray *windows, NSDictionary *applications)
{
  NSMutableSet *byClass = [NSMutableSet set];
  NSMutableSet *byName = [NSMutableSet set];
  NSEnumerator *e = [applications keyEnumerator];
  NSString *name;

  while ((name = [e nextObject]) != nil)
    {
      NSString *folded = DockAdoptionFolded(name);
      NSUInteger i;

      for (i = 0; i < [windows count]; i++)
        {
          NSDictionary *w = [windows objectAtIndex: i];
          NSString *cls = [w objectForKey: DockAdoptionClassKey];
          NSString *instance = [w objectForKey: DockAdoptionInstanceKey];
          NSString *title = [w objectForKey: DockAdoptionTitleKey];

          if ((cls != nil && [DockAdoptionFolded(cls) isEqualToString: folded])
              || (instance != nil && [DockAdoptionFolded(instance) isEqualToString: folded]))
            [byClass addObject: name];
          else if ((title != nil && DockAdoptionHasWordAtEdge(title, name))
                   || (cls != nil && DockAdoptionHasWordAtEdge(cls, name)))
            [byName addObject: name];
        }
    }
  return ([byClass count] > 0) ? byClass : byName;
}

NSArray *
DockAdoptionPlan(NSArray *clients, NSDictionary *applications,
                 NSSet *trackedPaths)
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
      NSSet *candidates = DockAdoptionCandidates(windows, applications);
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
