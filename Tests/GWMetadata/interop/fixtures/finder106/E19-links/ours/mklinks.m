/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 */
#import <Foundation/Foundation.h>
#import "FSNAlias.h"
#import "FSNLocationFile.h"

/* Writes the link files our p-links code produces, for pushing to the oracle. */
int main(int argc, char **argv)
{
  @autoreleasepool {
    NSString *out = [NSString stringWithUTF8String:argv[1]];
    NSString *base = @"/Users/user/Desktop/mi/lk";
    printf("%s\n", [[FSNAlias writeAliasFileForTargetPath:[base stringByAppendingPathComponent:@"a.txt"]
                                              inDirectory:out volumeName:@"Macintosh HD"] UTF8String]);
    printf("%s\n", [[FSNAlias writeAliasFileForTargetPath:[base stringByAppendingPathComponent:@"tdir"]
                                              inDirectory:out volumeName:@"Macintosh HD"] UTF8String]);
    printf("%s\n", [[FSNAlias writeAliasBookmarkForTargetPath:[base stringByAppendingPathComponent:@"b.txt"]
                                                  inDirectory:out volumeName:@"Macintosh HD"] UTF8String]);
    printf("%s\n", [[FSNLocationFile writeWeblocForURL:[NSURL URLWithString:@"http://example.com/gw?q=1"]
                                                 title:@"gw" inDirectory:out] UTF8String]);
  }
  return 0;
}
