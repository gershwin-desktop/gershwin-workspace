/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 */
#import <Foundation/Foundation.h>
#import "DSStore.h"

static void dump(NSString *path)
{
  DSStore *store = [DSStore storeWithPath:path];
  if (![store load]) {
    fprintf(stderr, "FAILED to load %s\n", [path UTF8String]);
    return;
  }
  printf("=== %s ===\n", [path UTF8String]);
  printf("viewStyle(dir) = %s\n", [[store viewStyleForDirectory] UTF8String]);
  NSArray *fns = [store allFilenames];
  printf("files with entries (%lu):\n", (unsigned long)[fns count]);
  for (NSString *fn in fns) {
    NSPoint p = [store iconLocationForFilename:fn];
    NSArray *codes = [store allCodesForFilename:fn];
    printf("  %-12s Iloc=(%.0f,%.0f) codes=%s\n",
           [fn UTF8String], p.x, p.y,
           [[codes componentsJoinedByString:@","] UTF8String]);
  }
  // directory-level chrome/view
  printf("iconSize(dir) = %d\n", [store iconSizeForDirectory]);
  printf("sidebarWidth(dir) = %d\n", [store sidebarWidthForDirectory]);
  printf("showToolbar(dir) = %d\n", [store showToolbarForDirectory]);
  printf("showSidebar(dir) = %d\n", [store showSidebarForDirectory]);
  printf("showStatusBar(dir) = %d\n", [store showStatusBarForDirectory]);
  printf("showPathBar(dir) = %d\n", [store showPathBarForDirectory]);
  printf("sortBy(dir) = %s\n", [[store sortByForDirectory] UTF8String]);
}

int main(int argc, char **argv)
{
  for (int i = 1; i < argc; i++) {
    dump([NSString stringWithUTF8String:argv[i]]);
  }
  return 0;
}
