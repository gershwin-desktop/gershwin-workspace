/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-2.0-or-later
 */
#import <Foundation/Foundation.h>
#import "Testing.h"

/* The label names have one home, the application table, which the Label
 * menu, the Find window and the Inspector all read; the search results window
 * title is in every language.  These read the tables of the source tree. */
int
main(void)
{
  NSAutoreleasePool *arp = [NSAutoreleasePool new];
  NSFileManager *fm = [NSFileManager defaultManager];
  NSString *root = [[fm currentDirectoryPath]
                     stringByAppendingPathComponent: @"../../Workspace/Resources"];
  NSString *insp = [[fm currentDirectoryPath]
                     stringByAppendingPathComponent: @"../../Inspector/Resources"];
  NSArray *names = @[ @"None", @"Red", @"Orange", @"Yellow", @"Green", @"Blue",
                      @"Purple", @"Grey" ];
  NSArray *dirs = [fm directoryContentsAtPath: root];
  NSString *dir;
  NSUInteger langs = 0;

  for (dir in dirs) {
    NSString *lang;
    NSDictionary *tbl;
    NSString *name;
    NSString *en;

    if (![dir hasSuffix: @".lproj"]) continue;
    lang = [dir stringByDeletingPathExtension];
    tbl = [NSDictionary dictionaryWithContentsOfFile: [NSString
      stringWithFormat: @"%@/%@/Localizable.strings", root, dir]];
    langs++;
    PASS(tbl != nil, "%s table readable", [lang UTF8String]);
    for (name in names) {
      PASS([tbl objectForKey: name] != nil, "%s has the label name %s",
           [lang UTF8String], [name UTF8String]);
    }
    en = [tbl objectForKey: @"Search Results"];
    PASS(en != nil, "%s localizes the search results title", [lang UTF8String]);
    if (![lang isEqual: @"English"]) {
      PASS(![en isEqual: @"Search Results"], "%s title is translated",
           [lang UTF8String]);
    }
  }
  PASS(langs == 14, "14 languages, found %lu", (unsigned long)langs);

  for (dir in [fm directoryContentsAtPath: insp]) {
    NSDictionary *tbl = [NSDictionary dictionaryWithContentsOfFile: [NSString
      stringWithFormat: @"%@/%@/FinderInfo.strings", insp, dir]];
    NSString *name;

    for (name in names) {
      PASS([tbl objectForKey: name] == nil,
           "Inspector %s has no second copy of the label name %s",
           [dir UTF8String], [name UTF8String]);
    }
  }
  /* Smart folders get the search folder icon, which must exist. */
  {
    NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile: [[fm
      currentDirectoryPath] stringByAppendingPathComponent:
      @"../../Workspace/WorkspaceInfo.plist"]];
    NSDictionary *t;
    NSString *icon = nil;

    for (t in [info objectForKey: @"NSTypes"]) {
      if ([[t objectForKey: @"NSUnixExtensions"] containsObject: @"savedSearch"])
        icon = [t objectForKey: @"NSIcon"];
    }
    PASS(icon != nil, "a .savedSearch file has an icon of its own");
    PASS(icon != nil && [fm fileExistsAtPath: [[[fm currentDirectoryPath]
      stringByAppendingPathComponent: @"../../Workspace/Resources/Icons"]
      stringByAppendingPathComponent: icon]], "the icon file exists");
  }
  [arp release];
  return 0;
}
