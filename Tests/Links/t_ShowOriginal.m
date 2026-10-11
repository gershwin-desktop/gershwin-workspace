/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 */
#import <Foundation/Foundation.h>
#import "Testing.h"
#import "FSNAliasFile.h"
#include <unistd.h>

int main(void)
{
  NSAutoreleasePool *arp = [NSAutoreleasePool new];
  NSFileManager *fm = [NSFileManager defaultManager];
  NSString *root = [NSString stringWithFormat: @"/tmp/t_ShowOriginal.%d", getpid()];
  NSString *deep = [root stringByAppendingPathComponent: @"deep/er"];
  NSString *orig = [deep stringByAppendingPathComponent: @"orig.txt"];
  NSString *plain = [root stringByAppendingPathComponent: @"plain.txt"];
  NSString *aliasDir = [root stringByAppendingPathComponent: @"aliases"];
  NSString *alias, *link, *broken, *relLink;

  [fm removeFileAtPath: root handler: nil];
  [fm createDirectoryAtPath: deep withIntermediateDirectories: YES attributes: nil error: NULL];
  [fm createDirectoryAtPath: aliasDir withIntermediateDirectories: YES attributes: nil error: NULL];
  [@"x" writeToFile: orig atomically: YES encoding: NSUTF8StringEncoding error: NULL];
  [@"y" writeToFile: plain atomically: YES encoding: NSUTF8StringEncoding error: NULL];

  alias = [FSNAlias writeAliasFileForPath: orig inDirectory: aliasDir];
  link = [aliasDir stringByAppendingPathComponent: @"abslink"];
  relLink = [aliasDir stringByAppendingPathComponent: @"rellink"];
  broken = [aliasDir stringByAppendingPathComponent: @"broken"];
  [fm createSymbolicLinkAtPath: link pathContent: orig];
  [fm createSymbolicLinkAtPath: relLink pathContent: @"../deep/er/orig.txt"];
  [fm createSymbolicLinkAtPath: broken pathContent: @"nowhere.txt"];

  NEED(PASS(alias != nil, "alias file written"));

  PASS_EQUAL([FSNAlias originalOfItemAtPath: alias],
             [orig stringByResolvingSymlinksInPath],
             "an alias file resolves to its original");
  PASS_EQUAL([FSNAlias originalOfItemAtPath: link],
             [orig stringByResolvingSymlinksInPath],
             "an absolute symlink resolves to its target");
  PASS_EQUAL([FSNAlias originalOfItemAtPath: relLink],
             [orig stringByResolvingSymlinksInPath],
             "a relative symlink resolves against its own folder");
  PASS([FSNAlias originalOfItemAtPath: broken] == nil,
       "a dangling symlink has no original");
  PASS([FSNAlias originalOfItemAtPath: plain] == nil,
       "a plain file has no original");

  PASS([FSNAlias canShowOriginalForPaths: [NSArray arrayWithObject: alias]],
       "one alias enables Show Original");
  PASS([FSNAlias canShowOriginalForPaths: [NSArray arrayWithObject: broken]],
       "a dangling symlink still enables it, to report the missing original");
  PASS(![FSNAlias canShowOriginalForPaths: [NSArray arrayWithObject: plain]],
       "a plain file does not");
  PASS(![FSNAlias canShowOriginalForPaths: [NSArray array]],
       "no selection does not");
  NSArray *two = [NSArray arrayWithObjects: alias, link, nil];
  PASS(![FSNAlias canShowOriginalForPaths: two],
       "two aliases do not");

  [fm moveItemAtPath: orig toPath: [root stringByAppendingPathComponent: @"moved.txt"] error: NULL];
  PASS([FSNAlias originalOfItemAtPath: link] == nil,
       "a symlink whose target went away has no original");

  [fm removeFileAtPath: root handler: nil];
  [arp release];
  return 0;
}
