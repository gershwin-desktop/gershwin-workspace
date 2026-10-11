/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 */

#import "GWSavedSearchRunner.h"
#import "GWSavedSearch.h"
#import "MDKQuery.h"

@implementation GWSavedSearchRunner

- (void)dealloc
{
  [query setDelegate: nil];
  [query release];
  [search release];
  [results release];
  [statusText release];
  [super dealloc];
}

- (id)initWithSavedSearch:(GWSavedSearch *)aSearch delegate:(id)aDelegate
{
  self = [super init];
  search = [aSearch retain];
  delegate = aDelegate;
  results = [NSMutableArray new];
  return self;
}

- (BOOL)start
{
  NSString *text = [search mdkQueryStringAtDate: [NSDate date]];

  [statusText release];
  statusText = [[search statusText] copy];
  if (text == nil) {
    return NO;
  }
  [results removeAllObjects];
  [query setDelegate: nil];
  [query release];
  /* A malformed translation must not be hidden: let MDKit's exception
   * surface instead of showing an empty folder. */
  query = [[MDKQuery queryFromString: text
                       inDirectories: [search searchPaths]] retain];
  [query setReportRawResults: YES];
  [query setDelegate: self];
  running = YES;
  [query startGathering];
  return YES;
}

- (void)stop
{
  [query stopQuery];
  running = NO;
}

- (BOOL)isRunning { return running; }
- (NSArray *)resultPaths { return results; }
- (NSString *)statusText { return statusText; }

- (void)appendRawResults:(NSArray *)lines
{
  [results addObjectsFromArray: lines];
  if ([delegate respondsToSelector:
       @selector(savedSearchRunnerDidChangeResults:)]) {
    [delegate savedSearchRunnerDidChangeResults: self];
  }
}

- (void)queryDidEndGathering:(MDKQuery *)q
{
  running = NO;
  if ([delegate respondsToSelector: @selector(savedSearchRunnerDidFinish:)]) {
    [delegate savedSearchRunnerDidFinish: self];
  }
}

@end
