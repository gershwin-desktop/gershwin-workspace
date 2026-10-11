/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 */
#import <Foundation/Foundation.h>
#import "Testing.h"
#import "GWFindCriteria.h"
#import "GWSavedSearch.h"
#include <stdlib.h>

static NSString *
raw(NSDictionary *criteria)
{
  NSString *err = nil;
  NSArray *one = [NSArray arrayWithObject: @"/Users/x"];

  return [[GWFindCriteria savedSearchForCriteria: criteria searchPaths: one
                                       recursive: YES error: &err] rawQuery];
}

static NSDictionary *
d(NSString *module, NSDictionary *c)
{
  return [NSDictionary dictionaryWithObject: c forKey: module];
}

int main(void)
{
  CREATE_AUTORELEASE_POOL(arp);
  NSString *err = nil;
  NSArray *one = [NSArray arrayWithObject: @"/Users/x"];
  GWSavedSearch *s;
  NSDictionary *na;
  NSArray *two;

  setenv("TZ", "UTC", 1);
  [NSTimeZone setDefaultTimeZone: [NSTimeZone timeZoneWithName: @"UTC"]];

  #define N(how, text) d(@"FModuleName", [NSDictionary dictionaryWithObjectsAndKeys: \
    [NSNumber numberWithInt: how], @"how", text, @"what", nil])
  PASS_EQUAL(raw(N(0, @"foo")), @"kMDItemFSName == \"*foo*\"", "contains");
  PASS_EQUAL(raw(N(1, @"foo")), @"kMDItemFSName == \"foo\"", "is");
  PASS_EQUAL(raw(N(2, @"foo")), @"kMDItemFSName != \"*foo*\"", "not contains");
  PASS_EQUAL(raw(N(3, @"foo")), @"kMDItemFSName == \"foo*\"", "starts");
  PASS_EQUAL(raw(N(4, @"foo")), @"kMDItemFSName == \"*foo\"", "ends");
  PASS(raw(N(0, @"a*b")) == nil, "wildcard in the text refused");

  /* the module compares size >> 10 */
  PASS_EQUAL(raw(d(@"FModuleSize", [NSDictionary dictionaryWithObjectsAndKeys:
    [NSNumber numberWithInt: 0], @"how", [NSNumber numberWithLong: 5], @"what", nil])),
    @"kMDItemFSSize >= 6144", "greater than 5 KB means at least 6 KB");
  PASS_EQUAL(raw(d(@"FModuleSize", [NSDictionary dictionaryWithObjectsAndKeys:
    [NSNumber numberWithInt: 1], @"how", [NSNumber numberWithLong: 5], @"what", nil])),
    @"kMDItemFSSize < 5120", "less than 5 KB");

  PASS_EQUAL(raw(d(@"FModuleKind", [NSDictionary dictionaryWithObjectsAndKeys:
    [NSNumber numberWithInt: 0], @"how", [NSNumber numberWithInt: 1], @"what", nil])),
    @"kMDItemContentTypeTree == 'public.folder'", "folders");
  PASS_EQUAL(raw(d(@"FModuleKind", [NSDictionary dictionaryWithObjectsAndKeys:
    [NSNumber numberWithInt: 1], @"how", [NSNumber numberWithInt: 4], @"what", nil])),
    @"kMDItemContentTypeTree != 'com.apple.application'", "not applications");
  PASS(raw(d(@"FModuleKind", [NSDictionary dictionaryWithObjectsAndKeys:
    [NSNumber numberWithInt: 0], @"how", [NSNumber numberWithInt: 3], @"what", nil]))
    == nil, "links have no equivalent");

  /* dates */
  PASS_EQUAL(raw(d(@"FModuleModDate", [NSDictionary dictionaryWithObjectsAndKeys:
    [NSNumber numberWithInt: 1], @"how", [NSNumber numberWithDouble: 604800], @"limit",
    [NSDate date], @"date", nil])),
    @"kMDItemContentModificationDate >= $time.now(-604800)", "within a week");
  PASS_EQUAL(raw(d(@"FModuleCrDate", [NSDictionary dictionaryWithObjectsAndKeys:
    [NSNumber numberWithInt: 0], @"how", [NSDate date], @"date", nil])),
    @"kMDItemFSCreationDate >= $time.today", "today");
  {
    NSDate *day = [NSDate dateWithString: @"2009-10-05 15:00:00 +0000"];
    double mid = [[NSDate dateWithString: @"2009-10-05 00:00:00 +0000"]
                  timeIntervalSinceReferenceDate];

    PASS_EQUAL(raw(d(@"FModuleModDate", [NSDictionary dictionaryWithObjectsAndKeys:
      [NSNumber numberWithInt: 2], @"how", day, @"date", nil])),
      ([NSString stringWithFormat: @"kMDItemContentModificationDate < %.6f", mid]),
      "before a day");
    PASS_EQUAL(raw(d(@"FModuleModDate", [NSDictionary dictionaryWithObjectsAndKeys:
      [NSNumber numberWithInt: 3], @"how", day, @"date", nil])),
      ([NSString stringWithFormat: @"kMDItemContentModificationDate >= %.6f",
        mid + 86400]), "after a day");
    PASS_EQUAL(raw(d(@"FModuleModDate", [NSDictionary dictionaryWithObjectsAndKeys:
      [NSNumber numberWithInt: 4], @"how", day, @"date", nil])),
      ([NSString stringWithFormat:
        @"(kMDItemContentModificationDate >= %.6f && "
        @"kMDItemContentModificationDate < %.6f)", mid, mid + 86400]),
      "exactly a day");
  }

  /* label (Finder colour number) and tags */
  #define LB(how, num) d(@"FModuleLabel", [NSDictionary dictionaryWithObjectsAndKeys: \
    [NSNumber numberWithInt: how], @"how", [NSNumber numberWithInt: num], @"what", nil])
  #define TG(how, text) d(@"FModuleTags", [NSDictionary dictionaryWithObjectsAndKeys: \
    [NSNumber numberWithInt: how], @"how", text, @"what", nil])
  PASS_EQUAL(raw(LB(0, 6)), @"kMDItemFSLabel == 6", "label is red");
  PASS_EQUAL(raw(LB(1, 6)), @"kMDItemFSLabel != 6", "label is not red");
  PASS_EQUAL(raw(LB(0, 0)), @"kMDItemFSLabel == 0", "no label");
  PASS(raw(LB(0, 8)) == nil, "no colour 8");
  PASS_EQUAL(raw(TG(0, @"Taxes")), @"kMDItemUserTags == \"Taxes\"", "tag is");
  PASS_EQUAL(raw(TG(1, @"ax")), @"kMDItemUserTags == \"*ax*\"", "tag contains");
  PASS(raw(TG(0, @"a*b")) == nil, "wildcard in a tag refused");
  PASS(raw(TG(0, @"")) == nil, "empty tag refused");
  s = [GWFindCriteria savedSearchForCriteria: LB(0, 6)
                                 searchPaths: one recursive: YES error: &err];
  PASS_EQUAL([s mdkQueryStringAtDate: [NSDate date]],
             @"GSMDItemFSLabel == \"6\"", "the label search reads back");

  /* what cannot be expressed is named */
  s = [GWFindCriteria savedSearchForCriteria:
       d(@"FModuleContents", [NSDictionary dictionaryWithObject: @"x" forKey: @"what"])
                                 searchPaths: one recursive: YES error: &err];
  PASS(s == nil && [err rangeOfString: @"FModuleContents"].location != NSNotFound,
       "contents are refused by name");
  na = N(0, @"a");
  PASS([GWFindCriteria savedSearchForCriteria: na searchPaths: one
                                    recursive: NO error: &err] == nil
       && [err rangeOfString: @"one folder level"].location != NSNotFound,
       "non recursive refused");
  two = [NSArray arrayWithObjects: @"/a", @"/b", nil];
  PASS([GWFindCriteria savedSearchForCriteria: na searchPaths: two
                                    recursive: YES error: &err] == nil,
       "several folders refused");
  PASS([GWFindCriteria savedSearchForCriteria: [NSDictionary dictionary]
                                  searchPaths: one recursive: YES error: &err] == nil,
       "nothing to search for");

  /* scope and the file written */
  s = [GWFindCriteria savedSearchForCriteria: N(0, @"a")
                                 searchPaths: [NSArray arrayWithObject: @"/"]
                                   recursive: YES error: &err];
  PASS_EQUAL([s scopes], [NSArray arrayWithObject: @"kMDQueryScopeComputer"],
             "the root folder is the whole computer");
  s = [GWFindCriteria savedSearchForCriteria:
       [NSDictionary dictionaryWithObjectsAndKeys:
        [NSDictionary dictionaryWithObjectsAndKeys:
         [NSNumber numberWithInt: 0], @"how", @"foo", @"what", nil], @"FModuleName",
        [NSDictionary dictionaryWithObjectsAndKeys:
         [NSNumber numberWithInt: 1], @"how", [NSNumber numberWithInt: 1], @"what", nil],
        @"FModuleKind", nil]
                                 searchPaths: one recursive: YES error: &err];
  PASS_EQUAL([s rawQuery],
             @"kMDItemContentTypeTree != 'public.folder' && kMDItemFSName == \"*foo*\"",
             "modules are joined with and in module name order");
  PASS([s mdkQueryStringAtDate: [NSDate date]] != nil
       && [[s unsupportedTerms] count] == 0,
       "what the Find window writes, the reader understands");
  PASS([[[s propertyList] objectForKey: @"SearchCriteria"]
        objectForKey: @"CurrentFolderPath"] != nil, "Finder's mandatory criteria");
  RELEASE(arp);
  return 0;
}
