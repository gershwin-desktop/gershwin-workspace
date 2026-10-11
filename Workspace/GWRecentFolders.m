/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-2.0-or-later
 */

#import "GWRecentFolders.h"

static NSString * const GWRecentFoldersDefaultsKey = @"GWRecentFolders";
static const NSUInteger GWRecentFoldersLimit = 10;

@implementation GWRecentFolders

+ (GWRecentFolders *)sharedRecentFolders
{
  static GWRecentFolders *shared = nil;

  if (shared == nil)
    {
      shared = [[GWRecentFolders alloc]
                 initWithDefaults: [NSUserDefaults standardUserDefaults]
                              key: GWRecentFoldersDefaultsKey
                            limit: GWRecentFoldersLimit];
    }
  return shared;
}

- (id)initWithDefaults:(NSUserDefaults *)aDefaults
                   key:(NSString *)aKey
                 limit:(NSUInteger)aLimit
{
  self = [super init];
  if (self)
    {
      defaults = [aDefaults retain];
      defaultsKey = [aKey copy];
      limit = aLimit;
    }
  return self;
}

- (void)dealloc
{
  [defaults release];
  [defaultsKey release];
  [super dealloc];
}

- (NSArray *)storedPaths
{
  id stored = [defaults arrayForKey: defaultsKey];

  return stored ? stored : [NSArray array];
}

- (void)noteFolderAtPath:(NSString *)path
{
  BOOL isDir = NO;
  NSMutableArray *list;

  if ([path length] == 0
      || [[NSFileManager defaultManager] fileExistsAtPath: path
                                              isDirectory: &isDir] == NO
      || isDir == NO)
    {
      return;
    }

  list = [NSMutableArray arrayWithArray: [self storedPaths]];
  [list removeObject: path];
  [list insertObject: path atIndex: 0];
  while ([list count] > limit)
    {
      [list removeLastObject];
    }
  [defaults setObject: list forKey: defaultsKey];
}

- (NSArray *)folderPaths
{
  NSMutableArray *result = [NSMutableArray array];
  NSEnumerator *e = [[self storedPaths] objectEnumerator];
  NSString *path;

  while ((path = [e nextObject]) != nil)
    {
      BOOL isDir = NO;

      if ([[NSFileManager defaultManager] fileExistsAtPath: path
                                                isDirectory: &isDir]
          && isDir && [result containsObject: path] == NO)
        {
          [result addObject: path];
        }
    }
  return result;
}

- (void)clear
{
  [defaults removeObjectForKey: defaultsKey];
}

@end
