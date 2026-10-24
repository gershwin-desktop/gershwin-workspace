/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

/* t_FindModuleName - name matching of the Find panel's name module, as used
 * by the panel (case-sensitive, as it always was) and by a folder window's
 * search field (case-insensitive).  Headless. */

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import "Testing.h"
#include "../../Workspace/Finder/Modules/FModuleName/FModuleName.m"

static NSString *const kCaseKey = @"caseInsensitive";

static BOOL matches(NSInteger how, NSString *what, BOOL ignoreCase, NSString *path)
{
  NSMutableDictionary *c = [NSMutableDictionary dictionary];
  id m;
  BOOL r;

  [c setObject: [NSNumber numberWithInteger: how] forKey: @"how"];
  [c setObject: what forKey: @"what"];
  if (ignoreCase)
    [c setObject: [NSNumber numberWithBool: YES] forKey: kCaseKey];
  m = [[FModuleName alloc] initWithSearchCriteria: c searchTool: nil];
  r = [m checkPath: path withAttributes: nil];
  [m release];
  return r;
}

int main(void)
{
  NSAutoreleasePool *arp = [NSAutoreleasePool new];

  START_SET("panel searches keep matching case");
  PASS(matches(0, @"notes", NO, @"/x/notes.txt"), "contains, same case");
  PASS(!matches(0, @"NOTES", NO, @"/x/notes.txt"), "contains, other case does not match");
  END_SET("panel searches keep matching case");

  START_SET("a case-insensitive search ignores case in every mode");
  PASS(matches(0, @"NOTES", YES, @"/x/Notes.txt"), "contains");
  PASS(matches(1, @"NOTES.TXT", YES, @"/x/notes.txt"), "is");
  PASS(!matches(2, @"NOTES", YES, @"/x/notes.txt"), "contains not");
  PASS(matches(2, @"zzz", YES, @"/x/notes.txt"), "contains not, absent");
  PASS(matches(3, @"NO", YES, @"/x/notes.txt"), "starts with");
  PASS(matches(4, @".TXT", YES, @"/x/notes.txt"), "ends with");
  PASS(!matches(4, @".md", YES, @"/x/notes.txt"), "ends with, other suffix");
  END_SET("a case-insensitive search ignores case in every mode");

  [arp release];
  return 0;
}
