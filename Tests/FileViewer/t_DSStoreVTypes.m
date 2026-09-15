/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 */
/* Regression test: Gershwin must WRITE a .DS_Store that carries the folder
 * self-entry (".DS_Store" settings) plus child Iloc, and read it back
 * identically.  On macOS 10.6 Finder this file is honored (verified: child
 * Iloc preserved, view style = icon view) - see INTEROP_DSSTORE.md. */
#import <Foundation/Foundation.h>
#include "DSStore.h"

static int failures = 0;
#define CHECK(cond, msg) do { if (!(cond)) { failures++; printf("FAIL: %s (%s:%d)\n", msg, __FILE__, __LINE__); } else { printf("ok: %s\n", msg); } } while (0)

int main(void)
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    NSString *outPath = @"/tmp/vttest.DS_Store";
    [[NSFileManager defaultManager] removeFileAtPath:outPath handler:nil];

    DSStore *store = [DSStore createStoreAtPath:outPath withEntries:nil];
    CHECK(store != nil, "create store");

    [store setIconLocationForFilename:@"a.txt" x:40 y:40];
    [store setIconLocationForFilename:@"b.txt" x:200 y:60];
    [store setIconLocationForFilename:@"."     x:120 y:120];   /* folder self-entry Iloc */
    [store setViewStyleForDirectory:@"icnv"];
    [store setIconSizeForDirectory:64];
    [store setGridSpacingForDirectory:20];
    [store setEntry:[DSStoreEntry browserWindowEntryForFile:@"."
                                          windowBounds:NSMakeRect(0,0,800,600)
                                             sidebarWidth:150]];
    CHECK([store save], "save returns YES");

    /* Reload and verify round-trip. */
    DSStore *re = [[DSStore alloc] initWithPath:outPath];
    CHECK([re load], "reload returns YES");

    NSPoint a = [re iconLocationForFilename:@"a.txt"];
    CHECK(a.x == 40 && a.y == 40, "child a.txt Iloc == (40,40)");
    NSPoint dot = [re iconLocationForFilename:@"."];
    CHECK(dot.x == 120 && dot.y == 120, "folder self-entry Iloc == (120,120)");
    CHECK([[re viewStyleForDirectory] isEqualToString:@"icnv"], "vstl == icnv");
    CHECK([re iconSizeForDirectory] == 64, "icvo icon size == 64");
    CHECK([re gridSpacingForDirectory] == 20, "icsp grid spacing == 20");

    DSStoreEntry *bwsp = [re entryForFilename:@"." code:@"bwsp"];
    CHECK(bwsp != nil, "bwsp (window geometry) present on self-entry");

    [re release];
    [[NSFileManager defaultManager] removeFileAtPath:outPath handler:nil];

    if (failures == 0) printf("VIEWTYPES TEST PASSED\n");
    else printf("VIEWTYPES TEST FAILED (%d)\n", failures);
    [pool release];
    return failures ? 1 : 0;
}
