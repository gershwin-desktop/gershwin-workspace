/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

#import "GWExtensionsManager.h"
#import "FSNode.h"

@implementation GWExtensionsManager
{
  NSMutableArray *extensions;
}

+ (GWExtensionsManager *)defaultManager
{
  static GWExtensionsManager *mgr = nil;
  if (mgr == nil)
    {
      mgr = [[GWExtensionsManager alloc] init];
    }
  return mgr;
}

- (id)init
{
  self = [super init];
  if (self)
    {
      extensions = [NSMutableArray new];
    }
  return self;
}

- (void)dealloc
{
  RELEASE (extensions);
  [super dealloc];
}

/* Discover .gwext bundles across all domains, exactly like the Inspector loads
 * its .inspector viewers (Inspector/Contents.m). */
- (void)loadExtensions
{
  NSFileManager *fm = [NSFileManager defaultManager];
  NSEnumerator *enumerator;
  NSString *dir;
  CREATE_AUTORELEASE_POOL (pool);

  enumerator = [NSSearchPathForDirectoriesInDomains
                 (NSLibraryDirectory, NSAllDomainsMask, YES) objectEnumerator];

  while ((dir = [enumerator nextObject]) != nil)
    {
      NSString *bundlesDir = [dir stringByAppendingPathComponent: @"Bundles"];
      NSArray *bnames = [fm directoryContentsAtPath: bundlesDir];
      NSUInteger i;

      for (i = 0; i < [bnames count]; i++)
        {
          NSString *bname = [bnames objectAtIndex: i];

          if ([[bname pathExtension] isEqual: @"gwext"])
            {
              NSString *bpath = [bundlesDir stringByAppendingPathComponent: bname];
              NSBundle *bundle = [NSBundle bundleWithPath: bpath];
              Class principalClass;

              if (bundle == nil)
                {
                  continue;
                }

              principalClass = [bundle principalClass];
              if (principalClass == nil)
                {
                  continue;
                }

              if ([principalClass conformsToProtocol: @protocol(GWorkspaceExtension)] == NO)
                {
                  continue;
                }

              {
                id ext = [[principalClass alloc] init];
                if (ext != nil)
                  {
                    [extensions addObject: ext];
                    [ext release];
                  }
              }
            }
        }
    }

  RELEASE (pool);
}

- (void)appendContextMenuItems:(NSMenu *)menu forNodes:(NSArray *)nodes
{
  NSUInteger i;

  for (i = 0; i < [extensions count]; i++)
    {
      id <GWorkspaceExtension> ext = [extensions objectAtIndex: i];

      if ([ext respondsToSelector: @selector(extensionCanHandleNodes:)] == NO)
        {
          continue;
        }
      if ([ext extensionCanHandleNodes: nodes] == NO)
        {
          continue;
        }
      if ([ext respondsToSelector: @selector(extensionAppendToContextMenu:forNodes:)])
        {
          [ext extensionAppendToContextMenu: menu forNodes: nodes];
        }
    }
}

#pragma mark - FSNodeRepDecorationDelegate

- (NSImage *)badgeImageForNode:(FSNode *)node
{
  NSUInteger i;

  for (i = 0; i < [extensions count]; i++)
    {
      id <GWorkspaceExtension> ext = [extensions objectAtIndex: i];

      if ([ext respondsToSelector: @selector(badgeImageForNode:)])
        {
          NSImage *img = [ext badgeImageForNode: node];
          if (img != nil)
            {
              return img;
            }
        }
    }

  return nil;
}

@end
