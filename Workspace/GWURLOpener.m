/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 */

#import <AppKit/AppKit.h>

#import "GWURLOpener.h"
#import "GWDetachedCommand.h"

@implementation GWURLOpener

- (NSArray *)applicationPathsForScheme:(NSString *)scheme
{
  NSWorkspace *ws = [NSWorkspace sharedWorkspace];
  NSMutableArray *names = [NSMutableArray array];
  NSMutableArray *paths = [NSMutableArray array];
  NSString *preferred = [ws getBestAppInRole: nil forScheme: scheme];
  NSEnumerator *e;
  NSString *name;

  if (preferred != nil)
    {
      [names addObject: preferred];
    }
  e = [[[[ws infoForScheme: scheme] allKeys]
         sortedArrayUsingSelector: @selector(compare:)] objectEnumerator];
  while ((name = [e nextObject]) != nil)
    {
      if ([names containsObject: name] == NO)
        {
          [names addObject: name];
        }
    }

  e = [names objectEnumerator];
  while ((name = [e nextObject]) != nil)
    {
      NSString *path = [ws fullPathForApplication: name];

      if (path != nil)
        {
          [paths addObject: path];
        }
    }
  return paths;
}

- (BOOL)openURL:(NSURL *)url error:(NSError **)error
{
  /* Read afresh on every open: a handler installed or chosen while
   * Workspace runs must count at once. */
  GWURLSchemeRegistry *registry = [[[GWURLSchemeRegistry alloc]
    initWithEnvironment: [[NSProcessInfo processInfo] environment]
      applicationSource: self] autorelease];
  GWURLHandler *handler = [registry handlerForURL: url error: error];
  NSString *what;

  if (handler == nil)
    {
      return NO;
    }
  if ([handler applicationPath] != nil)
    {
      /* NSWorkspace hands the URL to a running instance over DO and
       * launches the application with -GSOpenURL otherwise; it finds the
       * same application because the candidates came from it. */
      if ([[NSWorkspace sharedWorkspace] openURL: url])
        {
          return YES;
        }
      what = [handler applicationPath];
    }
  else
    {
      if ([GWDetachedCommand launchArguments: [handler arguments]])
        {
          return YES;
        }
      what = [handler desktopFilePath];
    }

  if (error != NULL)
    {
      *error = [NSError errorWithDomain: GWURLSchemeRegistryErrorDomain
                                   code: 2
                               userInfo: [NSDictionary dictionaryWithObject:
        [NSString stringWithFormat: @"%@ could not be started.", what]
                                                                forKey: NSLocalizedDescriptionKey]];
    }
  return NO;
}

@end
