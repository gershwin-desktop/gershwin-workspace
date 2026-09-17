/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */
 
#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>

static BOOL HasAppImageExtension(NSString *name)
{
  NSString *lower = [name lowercaseString];
  return [lower hasSuffix:@".appimage"];
}

int main(int argc, char **argv)
{
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  NSString *dir = nil;

  if (argc > 1) {
    dir = [NSString stringWithUTF8String: argv[1]];
  } else {
    dir = [@"~/Downloads" stringByExpandingTildeInPath];
  }

  NSFileManager *fm = [NSFileManager defaultManager];
  NSArray *contents = [fm directoryContentsAtPath: dir];
  if (contents == nil) {
    [pool drain];
    return 1;
  }

  NSWorkspace *ws = [NSWorkspace sharedWorkspace];

  for (NSString *name in contents) {
    if (!HasAppImageExtension(name)) {
      continue;
    }
    NSString *path = [dir stringByAppendingPathComponent: name];
    [ws iconForFile: path];
    }

  [pool drain];
  return 0;
}
