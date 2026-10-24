/* t_GitBadgeAsync.m - the badge count an icon asks for while a folder is
 * laid out never runs git on the calling thread: it answers "not known
 * yet" at once and the count is computed by the background worker.
 *
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */
#import <Foundation/Foundation.h>
#import "Testing.h"
#include "../../GitContextMenu/GitContextMenu.m"

/* Counts git runs by thread instead of running git. */
@interface TCountingGit : GitContextMenu
{
@public
  NSUInteger mainThreadRuns;
  NSUInteger workerRuns;
}
@end

@implementation TCountingGit
- (NSString *)gitOutputForArgs:(NSArray *)args repo:(NSString *)repo
{
  if ([NSThread isMainThread])
    mainThreadRuns++;
  else
    workerRuns++;
  return @"";
}
@end

int main(void)
{
  NSAutoreleasePool *arp = [NSAutoreleasePool new];
  NSFileManager *fm = [NSFileManager defaultManager];
  NSString *repo = [NSTemporaryDirectory() stringByAppendingPathComponent:
                      [NSString stringWithFormat: @"t_GitBadgeAsync-%d", getpid()]];
  TCountingGit *git = [TCountingGit new];
  NSDate *limit;
  NSInteger count;
  FSNode *node;

  [fm removeFileAtPath: repo handler: nil];
  [fm createDirectoryAtPath: [repo stringByAppendingPathComponent: @".git"]
withIntermediateDirectories: YES
                 attributes: nil
                      error: NULL];
  node = [FSNode nodeWithPath: repo];

  count = [git badgeCountForNode: node];
  PASS(count == -1, "the first query answers \"not known yet\" at once");
  PASS(git->mainThreadRuns == 0, "it does not run git on the calling thread");

  limit = [NSDate dateWithTimeIntervalSinceNow: 10.0];
  while (git->workerRuns == 0 && [limit timeIntervalSinceNow] > 0)
    [[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: 0.05]];
  /* Let the result reach the cache. */
  [[NSRunLoop currentRunLoop] runUntilDate: [NSDate dateWithTimeIntervalSinceNow: 0.3]];
  PASS(git->workerRuns > 0, "the background worker computes the count");

  count = [git badgeCountForNode: node];
  PASS(count == 0, "the computed count is then answered from the cache");
  PASS(git->mainThreadRuns == 0, "no query ran git on the calling thread");

  [fm removeFileAtPath: repo handler: nil];
  [arp release];
  return 0;
}
