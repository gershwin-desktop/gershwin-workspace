/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-2.0-or-later
 */

/* Which directories are packages: one item, opened with their application,
 * browsable only through Open as Folder. */

#import <AppKit/AppKit.h>
#import "Testing.h"
#import "FSNode.h"
#import "GSFileMetadata.h"

static NSFileManager *fm;
static NSString *dir;

static FSNode *
dirNode(NSString *name)
{
  NSString *p = [dir stringByAppendingPathComponent: name];

  [fm createDirectoryAtPath: p attributes: nil];
  return [FSNode nodeWithPath: p];
}

int
main(void)
{
  NSAutoreleasePool *arp = [NSAutoreleasePool new];
  NSArray *pkgs = [NSArray arrayWithObjects: @"a.rtfd", @"a.pages", @"a.numbers",
    @"a.key", @"a.bundle", @"a.plugin", @"a.kext",
    @"a.prefPane", @"a.playground", @"A.PAGES", nil];
  NSArray *plain = [NSArray arrayWithObjects: @"a.savedSearch", @"plain",
    @"a.txt", @"a.lproj", @"a.framework", nil];
  NSString *n;
  FSNode *f, *b;
  GSFileMetadata *md;
  NSString *bp;
  int i;

  fm = [NSFileManager defaultManager];
  dir = [NSTemporaryDirectory () stringByAppendingPathComponent:
          [NSString stringWithFormat: @"t_FSNodePackages_%d", (int)getpid ()]];
  [fm removeFileAtPath: dir handler: nil];
  [fm createDirectoryAtPath: dir attributes: nil];

  for (i = 0; i < (int)[pkgs count]; i++) {
    n = [pkgs objectAtIndex: i];
    PASS([dirNode (n) isPackage], "%s is a package", [n UTF8String]);
  }
  for (i = 0; i < (int)[plain count]; i++) {
    n = [plain objectAtIndex: i];
    f = dirNode (n);
    PASS([f isPackage] == NO, "%s is a plain folder", [n UTF8String]);
  }

  /* a regular file named like a package is no package */
  [@"x" writeToFile: [dir stringByAppendingPathComponent: @"f.pages"] atomically: YES];
  PASS([[FSNode nodeWithPath: [dir stringByAppendingPathComponent: @"f.pages"]] isPackage] == NO,
       "a file named .pages is not a package");

  /* a bare .app without Info.plist stays a folder (existing rule) */
  PASS([dirNode (@"bare.app") isPackage] == NO, "bare .app without plist stays a folder");

  /* kHasBundle on a folder without a package extension */
  b = dirNode (@"bundlebit");
  bp = [b path];
  md = [[[GSFileMetadata alloc] init] autorelease];
  [md setHasBundle: YES];
  {
    NSError *err = nil;
    PASS([md writeToFileAtPath: bp error: &err], "kHasBundle written (%s)", [[err description] UTF8String]);
  }
  [GSFileMetadata invalidateCachedMetadataForPath: bp];
  PASS([[FSNode nodeWithPath: bp] isPackage], "folder with kHasBundle is a package");

  /* kHasBundle does not turn a file into a package */
  {
    NSString *fp = [dir stringByAppendingPathComponent: @"bit.txt"];
    [@"x" writeToFile: fp atomically: YES];
    md = [[[GSFileMetadata alloc] init] autorelease];
    [md setHasBundle: YES];
    [md writeToFileAtPath: fp error: NULL];
    [GSFileMetadata invalidateCachedMetadataForPath: fp];
    PASS([[FSNode nodeWithPath: fp] isPackage] == NO, "file with kHasBundle is no package");
  }

  [fm removeFileAtPath: dir handler: nil];
  [arp release];
  return 0;
}
