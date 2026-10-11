/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 */
#import <AppKit/AppKit.h>
#import "DSStoreInfo.h"

/* cvwriter <dir> <x> <y> <w> <h> <sidebarWidth> <toolbar 0|1>: Workspace's own
 * DSStoreInfo writes a column view folder's records into the parent store, the
 * way the file viewer saves them, so the oracle can check Finder reads them. */
int main(int argc, char **argv)
{
  @autoreleasepool {
    if (argc != 8) {
      fprintf(stderr, "usage: cvwriter <dir> <x> <y> <w> <h> <sidebar> <toolbar>\n");
      return 1;
    }
    [NSApplication sharedApplication];
    DSStoreInfo *info = [DSStoreInfo infoForDirectoryPath:
      [NSString stringWithUTF8String:argv[1]] loadImmediately:NO];
    [info setViewStyle:DSStoreViewStyleColumn];
    [info setHasViewStyle:YES];
    [info setWindowFrame:NSMakeRect(atof(argv[2]), atof(argv[3]), atof(argv[4]), atof(argv[5]))];
    [info setHasWindowFrame:YES];
    [info setSidebarWidth:atoi(argv[6])];
    [info setHasSidebarWidth:YES];
    [info setShowToolbar:atoi(argv[7]) != 0];
    [info setHasShowToolbar:YES];
    if (![info saveToParentStore]) {
      fprintf(stderr, "cvwriter: saveToParentStore failed\n");
      return 2;
    }
  }
  return 0;
}
