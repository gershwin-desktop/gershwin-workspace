/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 */

#import "GWFindCriteria.h"
#import <MDKit/GWSavedSearch.h>

/* The pop-up positions the Find modules store in "how" and "what". */
enum { NameContains, NameIs, NameNotContains, NameStarts, NameEnds };
enum { SizeGreater, SizeLess };
enum { KindIs, KindIsNot };
enum { KindPlain, KindFolder, KindExecutable, KindLink, KindApplication };
enum { DateToday, DateWithin, DateBefore, DateAfter, DateExactly };

#define DAY 86400.0

@implementation GWFindCriteria

static NSString *
nameTerm(NSDictionary *c, NSString **why)
{
  NSString *s = [c objectForKey: @"what"];
  int how = [[c objectForKey: @"how"] intValue];

  /* Spotlight wildcards would change what the text means. */
  if ([s rangeOfString: @"*"].location != NSNotFound
      || [s rangeOfString: @"\""].location != NSNotFound
      || [s rangeOfString: @"\\"].location != NSNotFound) {
    *why = NSLocalizedString(@"names with *, \" or \\", @"");
    return nil;
  }
  switch (how) {
    case NameContains:
      return [NSString stringWithFormat: @"kMDItemFSName == \"*%@*\"", s];
    case NameIs:
      return [NSString stringWithFormat: @"kMDItemFSName == \"%@\"", s];
    case NameNotContains:
      return [NSString stringWithFormat: @"kMDItemFSName != \"*%@*\"", s];
    case NameStarts:
      return [NSString stringWithFormat: @"kMDItemFSName == \"%@*\"", s];
    case NameEnds:
      return [NSString stringWithFormat: @"kMDItemFSName == \"*%@\"", s];
  }
  *why = NSLocalizedString(@"name", @"");
  return nil;
}

/* The module compares whole kilobytes (size >> 10). */
static NSString *
sizeTerm(NSDictionary *c)
{
  long long kb = [[c objectForKey: @"what"] longLongValue];

  if ([[c objectForKey: @"how"] intValue] == SizeGreater) {
    return [NSString stringWithFormat: @"kMDItemFSSize >= %lld",
            (kb + 1) * 1024];
  }
  return [NSString stringWithFormat: @"kMDItemFSSize < %lld", kb * 1024];
}

static NSString *
kindTerm(NSDictionary *c, NSString **why)
{
  int what = [[c objectForKey: @"what"] intValue];
  NSString *op = ([[c objectForKey: @"how"] intValue] == KindIs) ? @"==" : @"!=";

  if (what == KindFolder) {
    return [NSString stringWithFormat:
            @"kMDItemContentTypeTree %@ 'public.folder'", op];
  }
  if (what == KindApplication) {
    return [NSString stringWithFormat:
            @"kMDItemContentTypeTree %@ 'com.apple.application'", op];
  }
  *why = NSLocalizedString(@"kinds other than folder and application", @"");
  return nil;
}

static NSString *
dateTerm(NSDictionary *c, NSString *attr, NSString **why)
{
  int how = [[c objectForKey: @"how"] intValue];
  NSDate *date = [c objectForKey: @"date"];
  double limit = [[c objectForKey: @"limit"] doubleValue];
  NSCalendar *cal = [NSCalendar currentCalendar];
  double day = 0;

  if (how == DateToday) {
    return [NSString stringWithFormat: @"%@ >= $time.today", attr];
  }
  if (how == DateWithin) {
    return [NSString stringWithFormat: @"%@ >= $time.now(-%.0f)", attr, limit];
  }
  if (how != DateBefore && how != DateAfter && how != DateExactly) {
    *why = NSLocalizedString(@"date", @"");
    return nil;
  }
  /* The module compares calendar days, so the day's start is the bound. */
  day = [[cal dateFromComponents: [cal components:
          NSYearCalendarUnit | NSMonthCalendarUnit | NSDayCalendarUnit
                                        fromDate: date]]
         timeIntervalSinceReferenceDate];
  if (how == DateBefore) {
    return [NSString stringWithFormat: @"%@ < %.6f", attr, day];
  }
  if (how == DateAfter) {
    return [NSString stringWithFormat: @"%@ >= %.6f", attr, day + DAY];
  }
  return [NSString stringWithFormat: @"(%@ >= %.6f && %@ < %.6f)", attr, day,
          attr, day + DAY];
}

+ (GWSavedSearch *)savedSearchForCriteria:(NSDictionary *)criteria
                              searchPaths:(NSArray *)paths
                                recursive:(BOOL)recursive
                                    error:(NSString **)error
{
  NSMutableArray *terms = [NSMutableArray array];
  NSMutableArray *refused = [NSMutableArray array];
  NSString *module;
  NSArray *scopes;

  for (module in [[criteria allKeys] sortedArrayUsingSelector:
                  @selector(compare:)]) {
    NSDictionary *c = [criteria objectForKey: module];
    NSString *why = nil;
    NSString *term = nil;

    if ([module isEqualToString: @"FModuleName"]) {
      term = nameTerm(c, &why);
    } else if ([module isEqualToString: @"FModuleSize"]) {
      term = sizeTerm(c);
    } else if ([module isEqualToString: @"FModuleKind"]) {
      term = kindTerm(c, &why);
    } else if ([module isEqualToString: @"FModuleModDate"]) {
      term = dateTerm(c, @"kMDItemContentModificationDate", &why);
    } else if ([module isEqualToString: @"FModuleCrDate"]) {
      term = dateTerm(c, @"kMDItemFSCreationDate", &why);
    } else {
      why = module;
    }
    if (term) {
      [terms addObject: term];
    } else {
      [refused addObject: why ? why : module];
    }
  }
  if (recursive == NO) {
    [refused addObject: NSLocalizedString(@"searching one folder level only",
                                          @"")];
  }
  if ([paths count] != 1) {
    [refused addObject: NSLocalizedString(@"searching several folders", @"")];
  }
  if ([refused count]) {
    if (error) {
      *error = [NSString stringWithFormat:
                NSLocalizedString(@"A smart folder cannot express: %@", @""),
                [refused componentsJoinedByString: @"; "]];
    }
    return nil;
  }
  if ([terms count] == 0) {
    if (error) {
      *error = NSLocalizedString(@"No search criteria!", @"");
    }
    return nil;
  }
  scopes = [NSArray arrayWithObject:
            [[paths objectAtIndex: 0] isEqualToString: @"/"]
            ? @"kMDQueryScopeComputer" : [paths objectAtIndex: 0]];
  return [GWSavedSearch savedSearchWithRawQuery:
          [terms componentsJoinedByString: @" && "] scopes: scopes];
}

@end
