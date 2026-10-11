/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 */

#import <Foundation/Foundation.h>

@class GWSavedSearchRunner;

/*
 * The window of an opened Spotlight smart folder (.savedSearch): the files
 * it finds in a list like a folder's, and above it what could not be
 * searched or was approximated. Updates while the search runs.
 */
@interface GWSmartFolder : NSObject
{
  NSWindow *win;
  NSTextField *statusField;
  NSTextField *countField;
  NSTableView *table;
  NSScrollView *scroll;
  GWSavedSearchRunner *runner;
  NSString *filePath;
  NSMutableArray *nodes;
}

/* Shows the window for the file, or the existing one. NO with a message
 * in an alert when the file is not a saved search. */
+ (BOOL)openSavedSearchAtPath:(NSString *)path;

- (NSWindow *)window;

@end
