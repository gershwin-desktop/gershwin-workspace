/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

/* t_GWThumbnailerFileOps.m - when Workspace itself moves, renames, trashes
 * or deletes files, the Thumbnailer drops their entries in the thumbnail
 * store at once instead of leaving them to the daily check. This drives
 * the decision which paths an operation takes away, and the whole way from
 * a posted GWFileSystemDidChangeNotification to the entry being gone, with
 * the store in a private directory. Headless. */

#import <AppKit/AppKit.h>
#import "Testing.h"

#include <unistd.h>

#include "../../Workspace/Thumbnailer/GWThumbnailer.m"
#import "GWThumbnailPNG.h"

static NSDictionary *
operation(NSString *op, NSString *source, NSString *destination, NSArray *files)
{
  NSMutableDictionary *info = [NSMutableDictionary dictionary];

  [info setObject: op forKey: @"operation"];
  if (source) [info setObject: source forKey: @"source"];
  if (destination) [info setObject: destination forKey: @"destination"];
  if (files) [info setObject: files forKey: @"files"];
  return info;
}

int
main(void)
{
  NSAutoreleasePool *arp = [NSAutoreleasePool new];
  NSFileManager *fm = [NSFileManager defaultManager];
  NSString *base = [NSTemporaryDirectory() stringByAppendingPathComponent:
    [NSString stringWithFormat: @"t_GWThumbnailerFileOps.%d", getpid()]];
  NSString *dir = [base stringByAppendingPathComponent: @"Thumbnails"];
  NSString *src = [base stringByAppendingPathComponent: @"files"];
  NSString *file = [src stringByAppendingPathComponent: @"photo.png"];
  NSArray *two = [NSArray arrayWithObjects: @"a", @"b", nil];
  NSArray *expected;
  GWThumbnailStore *store;
  Thumbnailer *t;
  int i;

  [fm removeFileAtPath: base handler: nil];
  [fm createDirectoryAtPath: src withIntermediateDirectories: YES attributes: nil error: NULL];
  store = [[GWThumbnailStore alloc] initWithDirectory: dir pixelSize: 64];
  [GWThumbnailStore setSharedStore: store];
  NEED(PASS([[[GWThumbnailStore sharedStore] directory] hasPrefix: NSTemporaryDirectory()],
            "the store is a private one"));

  START_SET("paths an operation takes away")
    expected = [NSArray arrayWithObjects: @"/x/a", @"/x/b", nil];
    PASS_EQUAL([Thumbnailer sourcePathsOfFileOperation:
                 operation(@"NSWorkspaceMoveOperation", @"/x", @"/y", two)], expected,
               "a move names its files in the source folder");
    expected = [NSArray arrayWithObject: @"/x/old"];
    PASS_EQUAL([Thumbnailer sourcePathsOfFileOperation:
                 operation(@"WorkspaceRenameOperation", @"/x/old", @"/x/new", nil)], expected,
               "a rename names the old path");
    PASS([[Thumbnailer sourcePathsOfFileOperation:
            operation(@"NSWorkspaceDestroyOperation", nil, nil, two)] count] == 0,
         "an operation without source names nothing");
    PASS([[Thumbnailer sourcePathsOfFileOperation: @"not a dictionary"] count] == 0,
         "neither does a notification without operation info");
  END_SET("paths an operation takes away")

  START_SET("a notification drops the entry")
    [@"x" writeToFile: file atomically: NO];
    [store storeImageData: GWThumbnailPNGEncodeRGBA([NSMutableData dataWithLength: 16], 2, 2, nil)
                  forPath: file kind: GWThumbnailKindThumbnail source: nil];
    NEED(PASS([store entryForPath: file] != nil, "the file has an entry"));
    t = [Thumbnailer sharedThumbnailer];
    [t startAutomaticChecks];
    unlink([file fileSystemRepresentation]);
    [[NSNotificationCenter defaultCenter]
      postNotificationName: @"GWFileSystemDidChangeNotification"
                    object: operation(@"NSWorkspaceDestroyOperation", src, nil,
                                      [NSArray arrayWithObject: @"photo.png"])];
    for (i = 0; i < 300 && [store entryForPath: file] != nil; i++)
      {
        usleep(10000);
      }
    PASS([store entryForPath: file] == nil,
         "deleting the file through Workspace drops its entry");
  END_SET("a notification drops the entry")

  [GWThumbnailStore setSharedStore: nil];
  [fm removeFileAtPath: base handler: nil];
  [arp release];
  return 0;
}
