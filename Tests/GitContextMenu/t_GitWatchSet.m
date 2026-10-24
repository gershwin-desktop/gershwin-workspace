/* t_GitWatchSet.m - which folders the git badge extension watches and
 * badges, and when it recounts: a repository root and its .git are watched,
 * no folder of the working tree; a folder that only contains a repository
 * further down, or one inside a checkout, gets no badge; a window becoming
 * key recounts the shown repositories only. Needs git.
 *
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */
#import <Foundation/Foundation.h>
#import "Testing.h"
#include "../../GitContextMenu/GitContextMenu.m"

/* Records which repositories git ran in, on which thread. */
@interface TRecordingGit : GitContextMenu
{
@public
  NSMutableArray *workerRepos;
  NSUInteger mainThreadRuns;
}
- (void)markShown:(NSString *)root count:(NSUInteger)count;
@end

@implementation TRecordingGit
- (NSString *)gitOutputForArgs:(NSArray *)args repo:(NSString *)repo
{
  if ([NSThread isMainThread])
    mainThreadRuns++;
  else
    @synchronized (self) { [workerRepos addObject: repo]; }
  return @"";
}
/* What -startWatchingNode: and -stopWatchingNode: record, without the
   fswatcher connection they also set up. */
- (void)markShown:(NSString *)root count:(NSUInteger)count
{
  [repoRefcounts setObject: [NSNumber numberWithUnsignedInteger: count] forKey: root];
}
@end

/* git lives in /usr/local/bin on the BSDs, so find it the way the bundle
   does instead of hardcoding a path. */
static void run(GitContextMenu *git, NSString *dir, NSArray *args)
{
  NSString *path = [git gitLaunchPath];
  NSTask *t;

  if (path == nil)
    {
      fprintf(stderr, "git not found in PATH\n");
      exit(1);
    }
  t = [NSTask new];
  [t setLaunchPath: path];
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
  run(git, repo, [NSArray arrayWithObjects: @"init", @"-q", nil]);
  run(git, repo, [NSArray arrayWithObjects: @"add", @"src/lib/code.c", nil]);

  watched = [git watchPathsForRepoRoot: repo];
  PASS([watched containsObject: repo], "the repository root is watched");
  PASS([watched containsObject: [repo stringByAppendingPathComponent: @".git"]],
       ".git is watched (commits, checkouts, the index)");
  PASS([watched count] == 2, "no folder of the working tree is watched, tracked or not");

  PASS_EQUAL([git repoRootForNode: [FSNode nodeWithPath: repo]], repo,
             "a repository root gets a badge and watches");
  PASS([git repoRootForNode: [FSNode nodeWithPath: parent]] == nil,
       "a folder that only contains a repository below gets none");
  PASS([git repoRootForNode: [FSNode nodeWithPath: [repo stringByAppendingPathComponent: @"src"]]] == nil,
       "a folder inside a checkout gets none");
  PASS([git badgeCountForNode: [FSNode nodeWithPath: parent]] == 0,
       "the parent of a repository has no count");

  {
    TRecordingGit *rec = [TRecordingGit new];
    NSString *other = [parent stringByAppendingPathComponent: @"hidden-checkout"];
    NSDate *limit;

    rec->workerRepos = [NSMutableArray new];
    touch([other stringByAppendingPathComponent: @"a.c"]);
    run(git, other, [NSArray arrayWithObjects: @"init", @"-q", nil]);
    [rec markShown: repo count: 1];
    [rec markShown: other count: 0];

    [[NSNotificationCenter defaultCenter]
      postNotificationName: NSWindowDidBecomeKeyNotification object: nil];
    limit = [NSDate dateWithTimeIntervalSinceNow: 10.0];
    while ([rec->workerRepos count] == 0 && [limit timeIntervalSinceNow] > 0)
      [[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: 0.05]];
    [[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: 0.5]];
    PASS([rec->workerRepos containsObject: repo],
         "a window becoming key recounts a shown repository");
    PASS([rec->workerRepos containsObject: other] == NO,
         "but not one whose icons are gone");
    PASS(rec->mainThreadRuns == 0, "the recount runs off the main thread");
    [rec->workerRepos release];
    [rec release];
  }

  [fm removeFileAtPath: parent handler: nil];
  [git release];
  [arp release];
  return 0;
}
