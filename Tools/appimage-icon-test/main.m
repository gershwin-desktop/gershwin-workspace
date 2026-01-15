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
    NSLog(@"appimage-icon-test: failed to list %@", dir);
    [pool drain];
    return 1;
  }

  NSWorkspace *ws = [NSWorkspace sharedWorkspace];
  NSUInteger tested = 0;
  NSUInteger succeeded = 0;

  for (NSString *name in contents) {
    if (!HasAppImageExtension(name)) {
      continue;
    }
    NSString *path = [dir stringByAppendingPathComponent: name];
    tested++;
    NSImage *image = [ws iconForFile: path];
    if (image != nil) {
      NSSize size = [image size];
      NSLog(@"appimage-icon-test: %@ -> icon %.0fx%.0f", name, size.width, size.height);
      succeeded++;
    } else {
      NSLog(@"appimage-icon-test: %@ -> no icon", name);
    }
  }

  NSLog(@"appimage-icon-test: processed %lu AppImages (%lu with icons)",
        (unsigned long)tested, (unsigned long)succeeded);

  [pool drain];
  return 0;
}
