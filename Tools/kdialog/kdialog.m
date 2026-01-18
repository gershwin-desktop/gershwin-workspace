/*
 * kdialog.m: Minimal kdialog-compatible frontend for GNUstep file panels
 *
 * Copyright (C) 2026 Free Software Foundation, Inc.
 *
 * SPDX-License-Identifier: GPL-2.0-or-later
 */

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>

static void printSelection(NSArray *paths, BOOL separateOutput)
{
  if (!paths || [paths count] == 0) {
    return;
  }

  NSString *separator = separateOutput ? @"\n" : @" ";
  NSString *output = [paths componentsJoinedByString:separator];
  fprintf(stdout, "%s\n", [output UTF8String]);
}

int main(int argc, char **argv)
{
  NSAutoreleasePool *pool = [NSAutoreleasePool new];
  [NSApplication sharedApplication];

  NSArray *arguments = [[NSProcessInfo processInfo] arguments];
  BOOL getOpen = NO;
  BOOL getSave = NO;
  BOOL getDirectory = NO;
  BOOL allowMultiple = NO;
  BOOL separateOutput = NO;
  NSString *title = nil;
  NSString *initialPath = nil;

  for (NSUInteger i = 1; i < [arguments count]; i++) {
    NSString *arg = [arguments objectAtIndex:i];
    if ([arg isEqualToString:@"--getopenfilename"]) {
      getOpen = YES;
    } else if ([arg isEqualToString:@"--getsavefilename"]) {
      getSave = YES;
    } else if ([arg isEqualToString:@"--getexistingdirectory"]) {
      getDirectory = YES;
    } else if ([arg isEqualToString:@"--multiple"]) {
      allowMultiple = YES;
    } else if ([arg isEqualToString:@"--separate-output"]) {
      separateOutput = YES;
    } else if ([arg isEqualToString:@"--title"] && i + 1 < [arguments count]) {
      title = [arguments objectAtIndex:++i];
    } else if (![arg hasPrefix:@"--"] && !initialPath) {
      initialPath = arg;
    }
  }

  if (!getOpen && !getSave && !getDirectory) {
    fprintf(stderr, "kdialog: no supported action specified\n");
    [pool release];
    return 1;
  }

  NSString *directory = nil;
  NSString *filename = nil;
  if (initialPath) {
    BOOL isDir = NO;
    BOOL exists = [[NSFileManager defaultManager] fileExistsAtPath:initialPath isDirectory:&isDir];
    if (exists && isDir) {
      directory = initialPath;
    } else if (exists) {
      directory = [initialPath stringByDeletingLastPathComponent];
      filename = [initialPath lastPathComponent];
    } else {
      directory = [initialPath stringByDeletingLastPathComponent];
      if ([directory length] == 0 || [directory isEqualToString:initialPath]) {
        directory = nil;
      }
      filename = [initialPath lastPathComponent];
    }
  }

  NSInteger result = NSCancelButton;
  NSArray *paths = nil;

  if (getSave) {
    NSSavePanel *panel = [NSSavePanel savePanel];
    if ([title length] > 0) {
      [panel setTitle:title];
    }
    result = [panel runModalForDirectory:directory file:filename];
    if (result == NSOKButton) {
      NSString *path = [panel filename];
      if (path) {
        paths = [NSArray arrayWithObject:path];
      }
    }
  } else {
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    if ([title length] > 0) {
      [panel setTitle:title];
    }
    [panel setAllowsMultipleSelection:allowMultiple];
    [panel setCanChooseDirectories:getDirectory];
    [panel setCanChooseFiles:!getDirectory];
    result = [panel runModalForDirectory:directory file:filename types:nil];
    if (result == NSOKButton) {
      if (allowMultiple) {
        paths = [panel filenames];
      } else {
        NSString *path = [panel filename];
        if (path) {
          paths = [NSArray arrayWithObject:path];
        }
      }
    }
  }

  if (result != NSOKButton || !paths) {
    [pool release];
    return 1;
  }

  printSelection(paths, separateOutput);
  [pool release];
  return 0;
}
