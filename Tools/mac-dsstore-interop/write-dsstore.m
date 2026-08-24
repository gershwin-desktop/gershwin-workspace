/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 */
#import <Foundation/Foundation.h>
#import "DSStore.h"

/* Reverse-interop writer: Gershwin emits a .DS_Store the way Workspace would,
 * so we can ship it to a real Mac and confirm Finder reads the icon positions
 * (and, where applicable, view style / window bounds) exactly. */
int main(int argc, char **argv)
{
  if (argc < 3) {
    fprintf(stderr, "usage: %s <out.DS_Store> <dirPath>\n", argv[0]);
    return 1;
  }
  NSString *outPath = [NSString stringWithUTF8String:argv[1]];

  DSStore *store = [DSStore createStoreAtPath:outPath withEntries:nil];
  if (store == nil) {
    fprintf(stderr, "FAILED to create store %s\n", [outPath UTF8String]);
    return 1;
  }

  /* Icon positions (Iloc) - the values Finder's AppleScript reports as the
   * item 'position' (top-left of the icon's bounds). */
  struct { const char *name; int x, y; } pos[] = {
    {"a.txt", 40, 40},
    {"b.txt", 200, 60},
    {"c.txt", 80, 220},
    {"d.txt", 300, 300}
  };
  for (int i = 0; i < 4; i++) {
    [store setIconLocationForFilename:[NSString stringWithUTF8String:pos[i].name]
                                     x:pos[i].x y:pos[i].y];
  }

  /* Per-folder view style (vstl) and window bounds (bwsp).  On 10.6 browser
   * mode these are not honoured per-folder, but we still emit them so the file
   * is spec-correct for spatial / 10.7+ Finder. */
  [store setViewStyleForDirectory:@"icnv"];
  DSStoreEntry *bw = [DSStoreEntry browserWindowEntryForFile:@"."
                                               windowBounds:NSMakeRect(100, 100, 520, 400)
                                               sidebarWidth:0];
  [store setEntry:bw];

  if (![store save]) {
    fprintf(stderr, "FAILED to save %s\n", [outPath UTF8String]);
    return 1;
  }
  printf("wrote %s\n", [outPath UTF8String]);
  return 0;
}
