/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 */
#import <Foundation/Foundation.h>
#import "Testing.h"
#include <stdlib.h>
/* The tables are file-static; the test checks them against MDKit's own. */
#include "GWSavedSearch.m"

static NSDate *fixedNow;

static NSString *
tr(NSString *raw)
{
  GWSavedSearch *s = [GWSavedSearch savedSearchWithRawQuery: raw scopes: nil];

  return [s mdkQueryStringAtDate: fixedNow];
}

static GWSavedSearch *
fixture(NSString *dir, NSString *name)
{
  NSString *err = nil;
  NSString *path = [[dir stringByAppendingPathComponent: name]
                    stringByAppendingPathExtension: @"savedSearch"];
  GWSavedSearch *s = [GWSavedSearch savedSearchWithContentsOfFile: path
                                                            error: &err];

  if (s == nil) {
    NSLog(@"fixture %@: %@", path, err);
  }
  return s;
}

/* The size and date terms of a query, as text; the index never sees them. */
static NSString *
trd(NSString *raw)
{
  GWSavedSearch *s = [GWSavedSearch savedSearchWithRawQuery:
    [raw stringByAppendingString: @" && kMDItemFSName = \"z\""] scopes: nil];
  NSMutableArray *out = [NSMutableArray array];
  NSDictionary *d;

  if ([s mdkQueryStringAtDate: fixedNow] == nil) {
    return nil;
  }
  for (d in [s fileTerms]) {
    [out addObject: [NSString stringWithFormat: @"%@ %@ %.0f",
      [d objectForKey: @"attribute"], [d objectForKey: @"operator"],
      [[d objectForKey: @"value"] doubleValue]]];
  }
  return [out componentsJoinedByString: @" & "];
}

static NSString *
refSecs(NSString *utc)
{
  NSDate *d = [NSDate dateWithString: utc];

  return [NSString stringWithFormat: @"%.0f",
          [d timeIntervalSinceReferenceDate]];
}

int main(void)
{
  CREATE_AUTORELEASE_POOL(arp);
  GWSavedSearch *s;
  NSString *q, *err = nil;
  NSString *tmp = [NSTemporaryDirectory()
                   stringByAppendingPathComponent: @"gw-savedsearch-test"];

  setenv("TZ", "UTC", 1);
  [NSTimeZone setDefaultTimeZone: [NSTimeZone timeZoneWithName: @"UTC"]];
  fixedNow = [NSDate dateWithString: @"2009-10-12 15:30:00 +0000"];
  [[NSFileManager defaultManager] createDirectoryAtPath: tmp
                            withIntermediateDirectories: YES
                                             attributes: nil error: NULL];

  /* names: Finder writes cdw modifiers, MDKit knows c */
  PASS_EQUAL(tr(@"kMDItemFSName = \"*foo*\"cdw"),
             @"GSMDItemFSName == \"*foo*\"c", "name contains");
  PASS_EQUAL(tr(@"kMDItemFSName == \"Foo\""),
             @"GSMDItemFSName == \"Foo\"", "no c modifier stays case sensitive");
  s = [GWSavedSearch savedSearchWithRawQuery: @"kMDItemFSName = \"a\"cdw"
                                      scopes: nil];
  [s mdkQueryStringAtDate: fixedNow];
  PASS([[s notes] count] == 1 && [[s unsupportedTerms] count] == 0,
       "d and w are reported as approximated, not dropped silently");

  /* dates */
  PASS_EQUAL(trd(@"kMDItemFSContentChangeDate >= $time.today(-7)"),
             ([NSString stringWithFormat:
               @"GSMDItemFSModificationDate >= %@",
               refSecs(@"2009-10-05 00:00:00 +0000")]),
             "last 7 days is seven days before midnight");
  PASS_EQUAL(trd(@"kMDItemFSContentChangeDate >= $time.now(-3600)"),
             ([NSString stringWithFormat:
               @"GSMDItemFSModificationDate >= %@",
               refSecs(@"2009-10-12 14:30:00 +0000")]), "now minus seconds");
  PASS_EQUAL(trd(@"kMDItemFSContentChangeDate >= $time.this_month"),
             ([NSString stringWithFormat:
               @"GSMDItemFSModificationDate >= %@",
               refSecs(@"2009-10-01 00:00:00 +0000")]), "this month");
  PASS_EQUAL(trd(@"kMDItemFSCreationDate < $time.iso(2009-10-12T10:00:00Z)"),
             ([NSString stringWithFormat: @"GSMDItemFSCreationDate < %@",
               refSecs(@"2009-10-12 10:00:00 +0000")]), "iso time");
  PASS_EQUAL(trd(@"InRange(kMDItemFSContentChangeDate,$time.today(-1),$time.today(1))"),
             ([NSString stringWithFormat:
               @"GSMDItemFSModificationDate >= %@ & "
               @"GSMDItemFSModificationDate <= %@",
               refSecs(@"2009-10-11 00:00:00 +0000"),
               refSecs(@"2009-10-13 00:00:00 +0000")]), "InRange");

  /* numbers, compounds, negation */
  PASS_EQUAL(trd(@"kMDItemFSSize > 1048576"), @"GSMDItemFSSize > 1048576",
             "size is checked on the file");
  PASS(tr(@"kMDItemFSSize > 5") == nil, "size alone cannot be searched");
  PASS(tr(@"kMDItemFSName = \"a\" || kMDItemFSSize > 5") == nil,
       "size inside or is refused");
  PASS_EQUAL(tr(@"kMDItemFSName = \"a*\"c && (kMDItemTitle = \"b\" || kMDItemAlbum = \"c\")"),
             @"(GSMDItemFSName == \"a*\"c && (GSMDItemTitle == \"b\" || GSMDItemAlbum == \"c\"))",
             "and or nesting");
  PASS_EQUAL(tr(@"!(kMDItemFSName = \"a\"c && kMDItemPixelWidth > 5)"),
             @"(GSMDItemFSName != \"a\"c || GSMDItemPixelWidth <= 5)",
             "not by De Morgan");
  PASS_EQUAL(tr(@"kMDItemFSName != \"a\"c"), @"GSMDItemFSName != \"a\"c",
             "!= is not a negation");

  /* content types */
  q = tr(@"kMDItemContentTypeTree = 'public.image'");
  PASS(q && [q hasPrefix: @"(GSMDItemFSExtension == \"png\" || "]
       && [q rangeOfString: @"\"jpg\""].location != NSNotFound,
       "public.image becomes an extension list");
  PASS_EQUAL(tr(@"kMDItemContentTypeTree = 'public.folder'"),
             @"GSMDItemFSType == \"NSDirectoryFileType\"", "folders");
  PASS_EQUAL(tr(@"kMDItemContentTypeTree != 'com.apple.application-bundle'"),
             @"GSMDItemFSType != \"NSApplicationFileType\"", "not applications");
  PASS_EQUAL(tr(@"kMDItemContentType = 'com.adobe.pdf'"),
             @"(GSMDItemFSExtension == \"pdf\")", "pdf by leaf type");
  PASS(tr(@"kMDItemContentType = 'public.image'") == nil,
       "a container type is no leaf content type");
  PASS(tr(@"kMDItemContentTypeTree = 'com.example.unknown'") == nil,
       "unknown content type is refused");

  /* refusals are named and stop the search */
  s = [GWSavedSearch savedSearchWithRawQuery:
       @"kMDItemFSName = \"a\"c && kMDItemFSLabel = 6" scopes: nil];
  PASS([s mdkQueryStringAtDate: fixedNow] == nil
       && [[s unsupportedTerms] count] == 1
       && [[[s unsupportedTerms] objectAtIndex: 0]
           hasPrefix: @"kMDItemFSLabel == 6"],
       "an unindexed attribute (label) is refused and named");
  PASS([[s statusText] rangeOfString: @"kMDItemFSLabel"].location
       != NSNotFound, "status text names the term");
  PASS(tr(@"kMDItemFSName = \"50%\"c") == nil, "SQL wildcard in text refused");
  PASS(tr(@"kMDItemFSName = \"a_b\"c") == nil, "LIKE underscore refused");
  PASS(tr(@"kMDItemFSName = \"a_b\"") != nil, "underscore is fine for GLOB");
  PASS(tr(@"kMDItemFSName < \"a\"") == nil, "text order refused");
  PASS(tr(@"kMDItemFSName = \"a") == nil, "syntax error refused");
  PASS(tr(@"kMDItemFSName = \"a\" &&") == nil, "dangling && refused");
  PASS(tr(@"kMDItemFSSize > \"a\"") == nil, "number against text refused");
  s = [GWSavedSearch savedSearchWithRawQuery: @"kMDItemFSName = \"a\"c "
       @"&& kMDItemLastUsedDate > 5 && kMDItemKind = 'Folder'" scopes: nil];
  [s mdkQueryStringAtDate: fixedNow];
  PASS([[s unsupportedTerms] count] == 2, "every unsupported term is listed");

  /* files and scopes */
  {
    NSString *f = [tmp stringByAppendingPathComponent: @"a.savedSearch"];
    NSDictionary *pl = [NSDictionary dictionaryWithObjectsAndKeys:
      [NSNumber numberWithInt: 1], @"CompatibleVersion",
      @"kMDItemFSName = \"x*\"cdw", @"RawQuery",
      [NSDictionary dictionaryWithObjectsAndKeys:
       @"kMDItemFSName = \"x*\"cdw", @"RawQuery",
       [NSArray arrayWithObjects: @"/usr/bin", @"kMDQueryScopeHome", nil],
       @"SearchScopes",
       [NSNumber numberWithBool: YES], @"FinderFilesOnly", nil],
      @"RawQueryDict", nil];

    [pl writeToFile: f atomically: YES];
    s = [GWSavedSearch savedSearchWithContentsOfFile: f error: &err];
    PASS(s != nil, "loads a saved search file");
    PASS_EQUAL([s searchPaths],
               ([NSArray arrayWithObjects: @"/usr/bin", NSHomeDirectory(), nil]),
               "folder and home scopes");
    PASS([s finderFilesOnly] && [[s notes] count] == 2,
         "finder-files-only is reported as not applied");

    [[NSDictionary dictionaryWithObjectsAndKeys: @"kMDItemFSName = \"x\"",
      @"RawQuery", [NSArray arrayWithObject: @"kMDQueryScopeComputer"],
      @"FXScopeArrayOfPaths", nil] writeToFile: f atomically: YES];
    s = [GWSavedSearch savedSearchWithContentsOfFile: f error: &err];
    PASS(s != nil, "minimal file");
    [[NSDictionary dictionaryWithObjectsAndKeys: @"kMDItemFSName = \"x\"",
      @"RawQuery", [NSArray arrayWithObject: @"kMDQueryScopeComputer"],
      @"SearchScopes", nil] writeToFile: f atomically: YES];
    s = [GWSavedSearch savedSearchWithContentsOfFile: f error: &err];
    PASS(s != nil && [s searchPaths] == nil, "computer scope searches all");
    s = [GWSavedSearch savedSearchWithRawQuery: @"kMDItemFSName = \"x\""
                                        scopes: [NSArray arrayWithObject:
                                                 @"kMDQueryScopeNetwork"]];
    PASS([s mdkQueryStringAtDate: fixedNow] == nil
         && [[s unsupportedTerms] count] == 1, "network scope is refused");

    [[NSDictionary dictionaryWithObjectsAndKeys:
      [NSNumber numberWithInt: 2], @"CompatibleVersion",
      @"kMDItemFSName = \"x\"", @"RawQuery", nil]
     writeToFile: f atomically: YES];
    PASS([GWSavedSearch savedSearchWithContentsOfFile: f error: &err] == nil
         && err != nil, "a newer format is refused with a message");
    PASS([GWSavedSearch savedSearchWithContentsOfFile:
          [tmp stringByAppendingPathComponent: @"missing"] error: &err] == nil,
         "missing file");
  }

  /* writing */
  s = [GWSavedSearch savedSearchWithMDKitQuery:
       @"(GSMDItemFSName == \"foo*\"c && GSMDItemFSSize > 5)"
                                   searchPaths: nil error: &err];
  PASS(s != nil, "MDKit query converts");
  PASS_EQUAL([s rawQuery],
             @"(kMDItemFSName == \"foo*\"c && kMDItemFSSize > 5)",
             "raw query written");
  PASS_EQUAL([s scopes],
             [NSArray arrayWithObject: @"kMDQueryScopeComputer"],
             "no paths means the computer scope");
  {
    NSDictionary *pl = [s propertyList];
    NSDictionary *rqd = [pl objectForKey: @"RawQueryDict"];

    PASS([[pl objectForKey: @"CompatibleVersion"] intValue] == 1
         && [rqd objectForKey: @"RawQuery"] != nil
         && [rqd objectForKey: @"SearchScopes"] != nil
         && [[pl objectForKey: @"SearchCriteria"]
             objectForKey: @"FXScopeArrayOfPaths"] != nil,
         "plist carries the keys Finder reads");
  }
  s = [GWSavedSearch savedSearchWithMDKitQuery:
       [NSString stringWithFormat: @"GSMDItemFSModificationDate >= %@",
        refSecs(@"2009-10-05 00:00:00 +0000")]
                                   searchPaths: [NSArray arrayWithObject:
                                                 @"/tmp"] error: &err];
  PASS_EQUAL([s rawQuery],
             ([NSString stringWithFormat:
               @"kMDItemContentModificationDate >= %@.000000",
               refSecs(@"2009-10-05 00:00:00 +0000")]),
             "dates are written as absolute times like the Finder does");
  PASS_EQUAL(trd([s rawQuery]), ([NSString stringWithFormat:
             @"GSMDItemFSModificationDate >= %@",
             refSecs(@"2009-10-05 00:00:00 +0000")]), "date round trip");
  s = [GWSavedSearch savedSearchWithMDKitQuery:
       @"GSMDItemFSExtension == \"png\" || GSMDItemFSType == \"NSDirectoryFileType\""
                                   searchPaths: nil error: &err];
  PASS_EQUAL([s rawQuery],
             @"(kMDItemFSName == \"*.png\"c || kMDItemContentTypeTree == 'public.folder')",
             "extension and folder");
  PASS([GWSavedSearch savedSearchWithMDKitQuery: @"GSMDItemWords == \"a\""
                                    searchPaths: nil error: &err] == nil
       && [err rangeOfString: @"GSMDItemWords"].location != NSNotFound,
       "no guess for an attribute Spotlight lacks");
  {
    NSString *f = [tmp stringByAppendingPathComponent: @"out.savedSearch"];

    PASS([s writeToFile: f atomically: YES], "written");
    PASS_EQUAL([[GWSavedSearch savedSearchWithContentsOfFile: f error: &err]
                rawQuery], [s rawQuery], "written file reads back");
  }

  /* E36: files the 10.6 Finder wrote or ships */
  {
    NSString *dir = @"../GWMetadata/interop/fixtures/finder106/E36-smart-folders";
    NSArray *label = [NSArray arrayWithObjects:
      @"finder-written-Desktop-e35-smart-desk", nil];
    NSString *name;
    GWSavedSearch *f;

    f = fixture(dir, @"finder-written-Saved-Searches-e35-smart");
    q = [f mdkQueryStringAtDate: fixedNow];
    PASS(q != nil && [q rangeOfString: @"GSMDItemFSExtension == \"png\""]
         .location != NSNotFound
         && [q rangeOfString: @"GSMDItemFSName == \"*x*\"c"].location
         != NSNotFound && [[f fileTerms] count] == 2,
         "E36 Finder file (image, modified range, name contains) translates");
    PASS([[f unsupportedTerms] count] == 0 && [[f notes] count] >= 1,
         "E36 Finder file has notes and nothing unsupported");
    f = fixture(dir, [label objectAtIndex: 0]);
    PASS([f mdkQueryStringAtDate: fixedNow] == nil
         && [[[f unsupportedTerms] objectAtIndex: 0]
             hasPrefix: @"kMDItemFSLabel == 6"],
         "E36 file label is refused");
    f = fixture(dir, @"canned-All-Images");
    q = [f mdkQueryStringAtDate: fixedNow];
    PASS(q != nil && [q hasPrefix: @"(GSMDItemFSExtension == \"png\""],
         "canned All Images: the (true) wrapper and group id 13");
    PASS([f searchPaths] == nil, "canned search covers the computer");
    f = fixture(dir, @"canned-Today");
    PASS([f mdkQueryStringAtDate: fixedNow] == nil
         && [[f unsupportedTerms] count] == 2
         && [[[f unsupportedTerms] objectAtIndex: 0]
             hasPrefix: @"kMDItemLastUsedDate"],
         "canned Today: last opened date refused, group id 9 understood");
    f = fixture(dir, @"canned-All-Documents");
    PASS([f mdkQueryStringAtDate: fixedNow] == nil
         && [[[f unsupportedTerms] objectAtIndex: 0]
             hasPrefix: @"kMDItemContentTypeTree == 'public.content'"],
         "canned All Documents: public.content refused");
    f = fixture(dir, @"hand-crit");
    PASS_EQUAL([f mdkQueryStringAtDate: fixedNow],
               @"GSMDItemFSName == \"*.txt\"c", "hand-crit translates");
    PASS_EQUAL([f searchPaths],
               [NSArray arrayWithObject: @"/Users/user/Desktop/mi/e35"],
               "hand-crit folder scope");
    /* the one file the Finder opened, structure vs what we write */
    {
      NSDictionary *hand = [NSDictionary dictionaryWithContentsOfFile:
        [[dir stringByAppendingPathComponent: @"hand-crit"]
         stringByAppendingPathExtension: @"savedSearch"]];
      GWSavedSearch *mine = [GWSavedSearch savedSearchWithRawQuery:
        @"kMDItemFSName = \"*.txt\"c" scopes: [NSArray arrayWithObject:
                                              @"/Users/user/Desktop/mi/e35"]];
      NSDictionary *pl = [mine propertyList];
      NSDictionary *hc = [hand objectForKey: @"SearchCriteria"];
      NSDictionary *mc = [pl objectForKey: @"SearchCriteria"];
      NSString *k;
      BOOL all = (hc != nil && mc != nil);

      for (k in [hc allKeys]) {
        all = all && [[mc objectForKey: k] isEqual: [hc objectForKey: k]];
      }
      PASS(all, "SearchCriteria has the keys and values of the file the Finder opened");
      PASS_EQUAL([[pl objectForKey: @"RawQueryDict"] objectForKey:
                  @"SearchScopes"],
                 [[hand objectForKey: @"RawQueryDict"] objectForKey:
                  @"SearchScopes"], "scopes as in hand-crit");
      pl = [[GWSavedSearch savedSearchWithRawQuery: @"kMDItemFSName = \"a\""
              scopes: [NSArray arrayWithObject: @"kMDQueryScopeComputer"]]
            propertyList];
      PASS([[[pl objectForKey: @"SearchCriteria"] objectForKey: @"FXScope"]
            intValue] == 1396925814, "this Mac scope code");
      {
        NSArray *two = [NSArray arrayWithObjects: @"/a", @"/b", nil];

        PASS([[GWSavedSearch savedSearchWithRawQuery: @"kMDItemFSName = \"a\""
                                              scopes: two]
              propertyList] == nil, "several folders are not written");
      }
    }
    PASS_EQUAL(tr(@"(true) && (kMDItemFSName = \"a\")"),
               @"GSMDItemFSName == \"a\"", "true drops out of &&");
    PASS(tr(@"(true)") == nil, "a query that is only true is refused");
    PASS(tr(@"_kMDItemGroupId = 99") == nil, "unknown group id refused");
  }

  /* size and dates are checked on the file */
  {
    NSString *f = [tmp stringByAppendingPathComponent: @"five.txt"];
    GWSavedSearch *g;

    [@"12345" writeToFile: f atomically: YES encoding: NSUTF8StringEncoding
                    error: NULL];
    g = [GWSavedSearch savedSearchWithRawQuery:
         @"kMDItemFSName = \"five*\" && kMDItemFSSize >= 5 && kMDItemFSSize < 6"
                                        scopes: nil];
    PASS([g mdkQueryStringAtDate: fixedNow] != nil
         && [g fileMatchesFileTerms: f], "size inside the range matches");
    g = [GWSavedSearch savedSearchWithRawQuery:
         @"kMDItemFSName = \"five*\" && kMDItemFSSize > 5" scopes: nil];
    [g mdkQueryStringAtDate: fixedNow];
    PASS([g fileMatchesFileTerms: f] == NO, "size outside the range fails");
    g = [GWSavedSearch savedSearchWithRawQuery:
         @"kMDItemFSName = \"five*\" && kMDItemFSContentChangeDate >= $time.now(-60)"
                                        scopes: nil];
    [g mdkQueryStringAtDate: [NSDate date]];
    PASS([g fileMatchesFileTerms: f], "recent file matches a recent date");
    PASS([g fileMatchesFileTerms: [tmp stringByAppendingPathComponent: @"gone"]]
         == NO, "missing file fails");
  }

  /* the table only names attributes MDKit has, of the type it has */
  {
    NSString *plist = [@"../../GWMetadata/MDKit/Resources"
                       stringByAppendingPathComponent: @"attributes.plist"];
    NSDictionary *attrs = [[NSDictionary dictionaryWithContentsOfFile: plist]
                           objectForKey: @"attributes"];
    unsigned i;
    BOOL ok = (attrs != nil);

    for (i = 0; ok && i < ATTR_COUNT; i++) {
      NSDictionary *a = [attrs objectForKey:
                         [NSString stringWithUTF8String: attrMap[i].mdk]];
      int t = [[a objectForKey: @"type"] intValue];

      ok = (a != nil)
        && ((attrMap[i].type == AttrString && (t == 0 || t == 1))
            || (attrMap[i].type == AttrNumber && t == 2)
            || (attrMap[i].type == AttrDate && t == 3));
      if (!ok) {
        NSLog(@"bad table row %s", attrMap[i].mdk);
      }
    }
    PASS(ok, "attribute table matches MDKit attributes.plist");
  }

  [[NSFileManager defaultManager] removeItemAtPath: tmp error: NULL];
  RELEASE(arp);
  return 0;
}
