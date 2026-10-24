/* t_GitWatchSet.m - which folders the git badge extension watches and
 * badges: a repository root, its .git and the folders holding tracked files;
 * not untracked folders deep in a checkout, not a folder that only contains
 * a repository further down, not a folder inside a checkout. Needs git.
 *
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */
#import <Foundation/Foundation.h>
#import "Testing.h"
#include "../../GitContextMenu/GitContextMenu.m"

static void run(NSString *dir, NSArray *args)
{
  NSTask *t = [NSTask new];

  [t setLaunchPath: @"/usr/bin/git"];
  [t setArguments: args];
  [t setCurrentDirectoryPath: dir];
  [t setStandardOutput: [NSFileHandle fileHandleWithNullDevice]];
  [t setStandardError: [NSFileHandle fileHandleWithNullDevice]];
  [t launch];
  [t waitUntilExit];
  [t release];
}

static void touch(NSString *path)
{
  [[NSFileManager defaultManager] createDirectoryAtPath: [path stringByDeletingLastPathComponent]
                            withIntermediateDirectories: YES
                                             attributes: nil
                                                  error: NULL];
  [@"x" writeToFile: path atomically: NO];
}

int main(void)
{
  NSAutoreleasePool *arp = [NSAutoreleasePool new];
  NSFileManager *fm = [NSFileManager defaultManager];
  NSString *parent = [NSTemporaryDirectory() stringByAppendingPathComponent:
                        [NSString stringWithFormat: @"t_GitWatchSet-%d", getpid()]];
  NSString *repo = [parent stringByAppendingPathComponent: @"checkout"];
  GitContextMenu *git = [GitContextMenu new];
  NSArray *watched;

  [fm removeFileAtPath: parent handler: nil];
  touch([repo stringByAppendingPathComponent: @"src/lib/code.c"]);
  touch([repo stringByAppendingPathComponent: @"build/deep/tree/out.o"]);
  run(repo, [NSArray arrayWithObjects: @"init", @"-q", nil]);
  run(repo, [NSArray arrayWithObjects: @"add", @"src/lib/code.c", nil]);

  watched = [git directoriesToWatchForRepo: repo];
  PASS([watched containsObject: repo], "the repository root is watched");
  PASS([watched containsObject: [repo stringByAppendingPathComponent: @".git"]],
       ".git is watched (commits, checkouts, the index)");
  PASS([watched containsObject: [repo stringByAppendingPathComponent: @"src"]]
       && [watched containsObject: [repo stringByAppendingPathComponent: @"src/lib"]],
       "folders holding tracked files are watched");
  PASS([watched containsObject: [repo stringByAppendingPathComponent: @"build"]] == NO
       && [watched containsObject: [repo stringByAppendingPathComponent: @"build/deep"]] == NO
       && [watched containsObject: [repo stringByAppendingPathComponent: @"build/deep/tree"]] == NO,
       "untracked folders are not watched");
  PASS([watched count] == 4, "nothing else is watched");

  PASS_EQUAL([git repoRootForNode: [FSNode nodeWithPath: repo]], repo,
             "a repository root gets a badge and watches");
  PASS([git repoRootForNode: [FSNode nodeWithPath: parent]] == nil,
       "a folder that only contains a repository below gets none");
  PASS([git repoRootForNode: [FSNode nodeWithPath: [repo stringByAppendingPathComponent: @"src"]]] == nil,
       "a folder inside a checkout gets none");
  PASS([git badgeCountForNode: [FSNode nodeWithPath: parent]] == 0,
       "the parent of a repository has no count");

  [fm removeFileAtPath: parent handler: nil];
  [git release];
  [arp release];
  return 0;
}
