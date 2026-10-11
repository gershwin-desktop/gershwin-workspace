/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-2.0-or-later
 */

#import <Foundation/Foundation.h>
#import "Testing.h"
#include "../../Workspace/GWRecentFolders.m"

int main(void)
{
  NSAutoreleasePool *arp = [NSAutoreleasePool new];
  NSFileManager *fm = [NSFileManager defaultManager];
  NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
  NSString *key = [NSString stringWithFormat: @"GWRecentFoldersTest%d", (int)getpid()];
  NSString *root = [NSTemporaryDirectory() stringByAppendingPathComponent:
                      [NSString stringWithFormat: @"gwrecent-%d", (int)getpid()]];
  NSMutableArray *dirs = [NSMutableArray array];
  GWRecentFolders *r;
  NSArray *got;
  NSUInteger i;

  [fm removeFileAtPath: root handler: nil];
  for (i = 0; i < 4; i++)
    {
      NSString *d = [root stringByAppendingPathComponent:
                       [NSString stringWithFormat: @"d%d", (int)i]];
      [fm createDirectoryAtPath: d withIntermediateDirectories: YES
                     attributes: nil error: NULL];
      [dirs addObject: d];
    }
  [fm createFileAtPath: [root stringByAppendingPathComponent: @"file.txt"]
              contents: [NSData data] attributes: nil];
  [ud removeObjectForKey: key];

  r = [[GWRecentFolders alloc] initWithDefaults: ud key: key limit: 3];
  PASS([[r folderPaths] count] == 0, "starts empty");

  [r noteFolderAtPath: [dirs objectAtIndex: 0]];
  [r noteFolderAtPath: [dirs objectAtIndex: 1]];
  got = [r folderPaths];
  PASS([[got objectAtIndex: 0] isEqual: [dirs objectAtIndex: 1]]
       && [got count] == 2, "most recent first");

  [r noteFolderAtPath: [dirs objectAtIndex: 0]];
  got = [r folderPaths];
  PASS([got count] == 2 && [[got objectAtIndex: 0] isEqual: [dirs objectAtIndex: 0]],
       "noting a folder again moves it to the front without a duplicate");

  [r noteFolderAtPath: [root stringByAppendingPathComponent: @"file.txt"]];
  [r noteFolderAtPath: [root stringByAppendingPathComponent: @"nonexistent"]];
  PASS([[r folderPaths] count] == 2, "files and missing paths are ignored");

  [r noteFolderAtPath: [dirs objectAtIndex: 2]];
  [r noteFolderAtPath: [dirs objectAtIndex: 3]];
  got = [r folderPaths];
  PASS([got count] == 3 && [[got objectAtIndex: 0] isEqual: [dirs objectAtIndex: 3]]
       && [got containsObject: [dirs objectAtIndex: 1]] == NO,
       "list is capped at the limit, oldest dropped");

  [fm removeFileAtPath: [dirs objectAtIndex: 3] handler: nil];
  got = [r folderPaths];
  PASS([got count] == 2 && [[got objectAtIndex: 0] isEqual: [dirs objectAtIndex: 2]],
       "folders deleted meanwhile are dropped");

  [r release];
  r = [[GWRecentFolders alloc] initWithDefaults: ud key: key limit: 3];
  PASS([[r folderPaths] count] == 2, "list survives a new instance (persisted)");

  [r clear];
  PASS([[r folderPaths] count] == 0, "Clear Menu empties the list");
  [r release];

  [ud removeObjectForKey: key];
  [fm removeFileAtPath: root handler: nil];
  [arp release];
  return 0;
}
