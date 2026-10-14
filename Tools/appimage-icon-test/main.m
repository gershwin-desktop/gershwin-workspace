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
  int failures = 0;

  for (NSString *name in contents) {
    if (!HasAppImageExtension(name)) {
      continue;
    }
    NSString *path = [dir stringByAppendingPathComponent: name];
    NSImage *icon = [ws iconForFile: path];

    if (icon == nil) {
      printf("%s: no icon\n", [name UTF8String]);
      failures++;
    } else {
      printf("%s: %.0fx%.0f\n", [name UTF8String],
        [icon size].width, [icon size].height);
    }
  }

  [pool drain];
  return failures ? 1 : 0;
}
