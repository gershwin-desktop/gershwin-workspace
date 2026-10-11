/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 */

#import <Foundation/Foundation.h>

@class GWSavedSearch;

/*
 * Runs a saved search through the metadata daemon and reports the paths it
 * finds, the way a folder reports its contents. Needs a run loop.
 */
@interface GWSavedSearchRunner : NSObject
{
  GWSavedSearch *search;
  id query;
  NSMutableArray *results;
  NSString *statusText;
  id delegate;
  BOOL running;
}

- (id)initWithSavedSearch:(GWSavedSearch *)aSearch delegate:(id)aDelegate;

/* NO when the search has unsupported terms: nothing is run, and -statusText
 * says why. */
- (BOOL)start;
- (void)stop;
- (BOOL)isRunning;

/* Absolute paths found so far, in the order they arrived. */
- (NSArray *)resultPaths;

/* What the window should show besides the results, or nil. */
- (NSString *)statusText;

@end

@interface NSObject (GWSavedSearchRunnerDelegate)
- (void)savedSearchRunnerDidChangeResults:(GWSavedSearchRunner *)runner;
- (void)savedSearchRunnerDidFinish:(GWSavedSearchRunner *)runner;
@end
