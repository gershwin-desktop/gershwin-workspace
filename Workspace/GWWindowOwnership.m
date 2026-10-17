/* GWWindowOwnership.m
 *
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

#import "GWWindowOwnership.h"

NSString * const GWWindowClassInfoKey = @"GSX11WindowClass";

BOOL
GWWindowOwnershipReasonIsOwned(GWWindowOwnershipReason reason)
{
  return reason == GWWindowOwnedLaunchedProcess
         || reason == GWWindowOwnedDescendantProcess
         || reason == GWWindowOwnedClass;
}

NSString *
GWWindowOwnershipReasonDescription(GWWindowOwnershipReason reason)
{
  switch (reason)
    {
    case GWWindowNotOwnedOtherProcess:
      return @"window of another process";
    case GWWindowNotOwnedClassOfOtherBundle:
      return @"WM_CLASS names another bundle";
    case GWWindowNotOwnedTitleOnly:
      return @"only the title names the application";
    case GWWindowOwnedLaunchedProcess:
      return @"launched process";
    case GWWindowOwnedDescendantProcess:
      return @"process started by the launched one";
    case GWWindowOwnedClass:
      return @"WM_CLASS names the application";
    case GWWindowNotOwned:
    default:
      return @"no match";
    }
}

/* WM_CLASS is usually the program's name ("brave-origin", "google-chrome",
 * "XTerm") while the bundle is named for people ("Brave Origin", "Google
 * Chrome"); case and word separators are all that differs between them. */
NSString *
GWWindowOwnershipFolded(NSString *name)
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

NSArray *
GWWindowOwnershipClassHintsInInfo(NSDictionary *info)
{
  id value = [info objectForKey: GWWindowClassInfoKey];
  NSMutableArray *hints = [NSMutableArray array];

  if ([value isKindOfClass: [NSString class]])
    {
      [hints addObject: value];
    }
  else if ([value isKindOfClass: [NSArray class]])
    {
      NSUInteger i;

      for (i = 0; i < [value count]; i++)
        {
          id hint = [value objectAtIndex: i];

          if ([hint isKindOfClass: [NSString class]])
            [hints addObject: hint];
        }
    }
  return hints;
}

NSArray *
GWWindowOwnershipClassHintsForBundle(NSString *path)
{
  /* NSBundle caches every bundle it ever opened for the life of the
   * process; reading the plist directly keeps a rescan of every installed
   * application from pinning them all. GNUstep bundles keep it in
   * Resources/Info-gnustep.plist, others in Resources/Info.plist or, the
   * macOS layout, Contents/Info.plist. */
  NSArray *candidates = [NSArray arrayWithObjects:
    @"Resources/Info-gnustep.plist", @"Resources/Info.plist",
    @"Contents/Info.plist", nil];
  NSUInteger i;

  for (i = 0; i < [candidates count]; i++)
    {
      NSString *plist = [path stringByAppendingPathComponent:
                                [candidates objectAtIndex: i]];
      NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile: plist];

      if (info != nil)
        return GWWindowOwnershipClassHintsInInfo(info);
    }
  return [NSArray array];
}

NSDictionary *
GWWindowOwnershipClassMap(NSDictionary *applications, NSDictionary *hintsByPath)
{
  NSMutableDictionary *map = [NSMutableDictionary dictionary];
  /* Sorted, so that which of two alike bundles keeps a class does not
   * depend on hash order. */
  NSArray *names = [[applications allKeys]
                     sortedArrayUsingSelector: @selector(compare:)];
  NSUInteger i;

  for (i = 0; i < [names count]; i++)
    {
      NSString *name = [names objectAtIndex: i];
      NSString *path = [applications objectForKey: name];
      NSMutableArray *classes = [NSMutableArray arrayWithObject: name];
      NSUInteger j;

      [classes addObjectsFromArray: [hintsByPath objectForKey: path]];
      for (j = 0; j < [classes count]; j++)
        {
          NSString *folded = GWWindowOwnershipFolded([classes objectAtIndex: j]);

          if ([folded length] > 0 && [map objectForKey: folded] == nil)
            [map setObject: path forKey: folded];
        }
    }
  return map;
}

NSDictionary *
GWWindowOwnershipApplicationsInAppList(NSDictionary *appList)
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

static NSString *
GWWindowOwnershipAppListPath(void)
{
  return [[[NSSearchPathForDirectoriesInDomains(NSLibraryDirectory,
                                                NSUserDomainMask, YES)
             objectAtIndex: 0]
            stringByAppendingPathComponent: @"Services"]
           stringByAppendingPathComponent: @".GNUstepAppList"];
}

NSDictionary *
GWWindowOwnershipInstalledApplications(void)
{
  NSData *data = [NSData dataWithContentsOfFile: GWWindowOwnershipAppListPath()];
  id list = nil;

  if (data != nil)
    list = [NSDeserializer deserializePropertyListFromData: data
                                         mutableContainers: NO];
  if ([list isKindOfClass: [NSDictionary class]] == NO)
    return nil;
  return GWWindowOwnershipApplicationsInAppList(list);
}

/* Asked from the main thread and from the Dock's and the app monitor's
 * worker threads; rebuilt only when make_services rewrote the list, since
 * a rebuild reads every installed bundle's Info.plist. */
static NSDictionary *installedClassMap = nil;
static NSDate *installedClassMapDate = nil;
static unsigned long long installedClassMapSize = 0;

NSDictionary *
GWWindowOwnershipInstalledClassMap(void)
{
  NSDictionary *attrs = [[NSFileManager defaultManager]
                          attributesOfItemAtPath: GWWindowOwnershipAppListPath()
                                           error: NULL];
  NSDate *date = [attrs fileModificationDate];
  unsigned long long size = [attrs fileSize];
  NSDictionary *result;

  @synchronized ([GWWindowOwnership class])
    {
      if (installedClassMap == nil
          || (date != installedClassMapDate
              && [date isEqualToDate: installedClassMapDate] == NO)
          || size != installedClassMapSize)
        {
          NSAutoreleasePool *pool = [NSAutoreleasePool new];
          NSDictionary *apps = GWWindowOwnershipInstalledApplications();
          NSMutableDictionary *hints = [NSMutableDictionary dictionary];
          NSEnumerator *e = [apps objectEnumerator];
          NSString *path;

          while ((path = [e nextObject]) != nil)
            {
              NSArray *h = GWWindowOwnershipClassHintsForBundle(path);

              if ([h count] > 0)
                [hints setObject: h forKey: path];
            }
          [installedClassMap release];
          installedClassMap = [GWWindowOwnershipClassMap(apps, hints) retain];
          [installedClassMapDate release];
          installedClassMapDate = [date retain];
          installedClassMapSize = size;
          [pool release];
        }
      result = [[installedClassMap retain] autorelease];
    }
  return result;
}

/* The title test only explains a refusal: the application's name at the
 * start or end of the title as a whole word. */
static BOOL
GWWindowOwnershipTitleNames(NSString *title, NSString *name)
{
  NSCharacterSet *word = [NSCharacterSet alphanumericCharacterSet];
  NSUInteger tl = [title length];
  NSUInteger nl = [name length];

  if (nl == 0 || tl < nl)
    return NO;
  if ([[title substringToIndex: nl] caseInsensitiveCompare: name] == NSOrderedSame
      && (tl == nl || [word characterIsMember: [title characterAtIndex: nl]] == NO))
    return YES;
  if (tl > nl
      && [[title substringFromIndex: tl - nl] caseInsensitiveCompare: name] == NSOrderedSame
      && [word characterIsMember: [title characterAtIndex: tl - nl - 1]] == NO)
    return YES;
  return NO;
}

@implementation GWWindowOwnership

- (id)initWithName:(NSString *)name
              path:(NSString *)path
       launchedPID:(pid_t)pid
        classHints:(NSArray *)hints
          classMap:(NSDictionary *)map
          ancestry:(GWProcessAncestryFunction)ancestryFunction
{
  self = [super init];
  if (self != nil)
    {
      NSMutableSet *classes = [NSMutableSet set];
      NSEnumerator *e;
      NSString *folded;
      NSUInteger i;

      appName = [name copy];
      appPath = [path copy];
      launchedPID = pid;
      classMap = [map retain];
      ancestry = ancestryFunction;
      descends = [NSMutableDictionary new];

      if ([name length] > 0)
        [classes addObject: GWWindowOwnershipFolded(name)];
      for (i = 0; i < [hints count]; i++)
        [classes addObject: GWWindowOwnershipFolded([hints objectAtIndex: i])];
      /* The map knows the bundle's declared classes too, so a caller that
       * only has the name and path still honours GSX11WindowClass. */
      if (path != nil)
        {
          e = [map keyEnumerator];
          while ((folded = [e nextObject]) != nil)
            {
              if ([[map objectForKey: folded] isEqual: path])
                [classes addObject: folded];
            }
        }
      [classes removeObject: @""];
      ownClasses = [classes copy];
    }
  return self;
}

- (void)dealloc
{
  [appName release];
  [appPath release];
  [classMap release];
  [ownClasses release];
  [descends release];
  [super dealloc];
}

- (NSString *)appName
{
  return appName;
}

- (NSString *)appPath
{
  return appPath;
}

- (pid_t)launchedPID
{
  return launchedPID;
}

/* An application often has many windows, and each answer walks the
 * process table, so it is asked once per process. */
- (BOOL)processDescendsFromLaunched:(pid_t)pid
{
  NSNumber *key = [NSNumber numberWithInt: (int)pid];
  NSNumber *known = [descends objectForKey: key];

  if (known == nil)
    {
      known = [NSNumber numberWithBool:
                 (ancestry != NULL && ancestry(pid, launchedPID))];
      [descends setObject: known forKey: key];
    }
  return [known boolValue];
}

/* Another bundle's claim on the window's class, if any. A class that also
 * names this application is not another's claim: two bundles of the same
 * name (a copy in ~/Applications) fold alike. */
- (BOOL)classIsClaimedByOtherBundle:(NSString *)folded
{
  NSString *claimant;

  if ([folded length] == 0 || [ownClasses containsObject: folded])
    return NO;
  claimant = [classMap objectForKey: folded];
  return claimant != nil && [claimant isEqual: appPath] == NO;
}

- (GWWindowOwnershipReason)reasonForWindowPID:(pid_t)pid
                                     instance:(NSString *)instance
                                  windowClass:(NSString *)windowClass
                                        title:(NSString *)title
{
  NSString *foldedInstance = (instance != nil) ? GWWindowOwnershipFolded(instance) : nil;
  NSString *foldedClass = (windowClass != nil) ? GWWindowOwnershipFolded(windowClass) : nil;
  BOOL claimedByOther = [self classIsClaimedByOtherBundle: foldedInstance]
                        || [self classIsClaimedByOtherBundle: foldedClass];

  if (launchedPID > 0)
    {
      /* The process we started is ours for certain, whatever it calls
       * itself: a wrapper .app may exec a program of any name. */
      if (pid == launchedPID)
        return GWWindowOwnedLaunchedProcess;
      if (pid > 0 && [self processDescendsFromLaunched: pid])
        {
          /* A process it started may be another application altogether
           * (a terminal running a browser); its class says so. */
          if (claimedByOther)
            return GWWindowNotOwnedClassOfOtherBundle;
          return GWWindowOwnedDescendantProcess;
        }
      return GWWindowNotOwnedOtherProcess;
    }

  if (claimedByOther)
    return GWWindowNotOwnedClassOfOtherBundle;
  if ((foldedInstance != nil && [ownClasses containsObject: foldedInstance])
      || (foldedClass != nil && [ownClasses containsObject: foldedClass]))
    return GWWindowOwnedClass;
  if (title != nil && GWWindowOwnershipTitleNames(title, appName))
    return GWWindowNotOwnedTitleOnly;
  return GWWindowNotOwned;
}

- (BOOL)ownsWindowPID:(pid_t)pid
             instance:(NSString *)instance
          windowClass:(NSString *)windowClass
                title:(NSString *)title
{
  return GWWindowOwnershipReasonIsOwned([self reasonForWindowPID: pid
                                                        instance: instance
                                                     windowClass: windowClass
                                                           title: title]);
}

@end
