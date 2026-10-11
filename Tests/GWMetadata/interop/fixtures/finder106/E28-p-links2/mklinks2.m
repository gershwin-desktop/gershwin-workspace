/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 */
#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import "FSNAlias.h"
#import "FSNLocationFile.h"
#import "GSFileMetadata.h"

/* Writes the p-links2 (952191a2) link files plus "._" sidecars, so the oracle
 * receives the forks the way a copy from a non-HFS volume would carry them. */
static void out(NSString *p)
{
  if (p == nil) { fprintf(stderr, "write failed\n"); exit(2); }
  if (![[GSFileMetadata metadataForFileAtPath:p] writeSidecarToFileAtPath:p error:NULL]) {
    fprintf(stderr, "sidecar failed for %s\n", [p UTF8String]); exit(3);
  }
  printf("%s\n", [p UTF8String]);
}

int main(int argc, char **argv)
{
  @autoreleasepool {
    [NSApplication sharedApplication];
    NSString *dir = [NSString stringWithUTF8String:argv[1]];
    NSString *base = @"/Users/user/Desktop/mi/lk2";
    out([FSNAlias writeAliasFileForTargetPath:[base stringByAppendingPathComponent:@"a.txt"] inDirectory:dir volumeName:@"Macintosh HD"]);
    out([FSNAlias writeAliasFileForTargetPath:[base stringByAppendingPathComponent:@"tdir"] inDirectory:dir volumeName:@"Macintosh HD"]);
    out([FSNAlias writeAliasBookmarkForTargetPath:[base stringByAppendingPathComponent:@"b.txt"] inDirectory:dir volumeName:@"Macintosh HD"]);
    out([FSNLocationFile writeWeblocForURL:[NSURL URLWithString:@"http://example.com/gw?q=1"] title:@"web" inDirectory:dir]);
    out([FSNLocationFile writeWeblocForURL:[NSURL URLWithString:@"ftp://ftp.example.org/"] title:@"ftp" inDirectory:dir]);
    out([FSNLocationFile writeWeblocForURL:[NSURL URLWithString:@"mailto:a@example.com"] title:@"mail" inDirectory:dir]);
  }
  return 0;
}
