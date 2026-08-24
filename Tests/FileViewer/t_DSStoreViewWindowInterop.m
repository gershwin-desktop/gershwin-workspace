/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 */
/* View-style + window-geometry interop: every view style (vstl) plus the
 * browser window frame (bwsp) and legacy window geometry (fwi0) must
 * round-trip through the writer/reader.  macOS acceptance of these records
 * (Finder actually applies the view and window frame) is verified separately
 * on the reference Mac mini; see INTEROP_DSSTORE.md. */
#import <Foundation/Foundation.h>
#include "DSStore.h"

static int failures = 0;
#define CHECK(cond, msg) do { if (!(cond)) { failures++; printf("FAIL: %s (%s:%d)\n", msg, __FILE__, __LINE__); } else { printf("ok: %s\n", msg); } } while (0)

static BOOL rectEq(NSRect a, NSRect b) {
    return fabs(a.origin.x-b.origin.x)<1 && fabs(a.origin.y-b.origin.y)<1 &&
           fabs(a.size.width-b.size.width)<1 && fabs(a.size.height-b.size.height)<1;
}

static NSString *fixture(NSString *name)
{
  return [[[NSString stringWithUTF8String:__FILE__]
            stringByDeletingLastPathComponent] stringByAppendingPathComponent:name];
}

int main(void)
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    NSString *outPath = @"/tmp/vwtest.DS_Store";
    [[NSFileManager defaultManager] removeFileAtPath:outPath handler:nil];

    DSStore *store = [DSStore createStoreAtPath:outPath withEntries:nil];
    CHECK(store != nil, "create store");

    /* ---- View styles (vstl) ---- */
    struct { NSString *s; } styles[] = {
        {@"icnv"}, {@"Nlsv"}, {@"clmv"}, {@"glyv"}, {@"Flwv"}
    };
    for (int i = 0; i < 5; i++) {
        DSStore *s = [DSStore createStoreAtPath:outPath withEntries:nil];
        [s setViewStyleForDirectory:styles[i].s];
        [s save];
        DSStore *r = [[DSStore alloc] initWithPath:outPath];
        [r load];
        NSString *msg = [NSString stringWithFormat:@"vstl round-trip %@", styles[i].s];
        CHECK([[r viewStyleForDirectory] isEqualToString:styles[i].s], [msg UTF8String]);
        [r release];
    }

    /* ---- Browser window frame (bwsp) ---- */
    [store setEntry:[DSStoreEntry browserWindowEntryForFile:@"." windowBounds:NSMakeRect(100,120,480,360) sidebarWidth:140]];
    /* ---- Legacy window geometry (fwi0) ---- */
    [store setEntry:[DSStoreEntry windowGeometryEntryForFile:@"." rect:NSMakeRect(10,20,300,400) viewStyle:@"icnv"]];
    /* ---- List view settings (lsvp) decoded on read ---- */
    [store setListViewSettings:[NSDictionary dictionaryWithObjectsAndKeys:
        [NSNumber numberWithInt:14], @"textSize",
        [NSNumber numberWithInt:48], @"iconSize", nil]];

    CHECK([store save], "save returns YES");

    DSStore *re = [[DSStore alloc] initWithPath:outPath];
    CHECK([re load], "reload returns YES");

    NSDictionary *bw = [re browserWindowDictionaryForDirectory];
    CHECK(bw != nil, "bwsp dict present");
    CHECK(bw && [[bw objectForKey:@"SidebarWidth"] intValue] == 140, "bwsp SidebarWidth == 140");
    NSRect bwr = [re browserWindowBoundsForDirectory];
    CHECK(rectEq(bwr, NSMakeRect(100,120,480,360)), "bwsp WindowBounds == (100,120,480,360)");

    NSRect fwr = [re windowGeometryRectForDirectory];
    CHECK(rectEq(fwr, NSMakeRect(10,20,300,400)), "fwi0 rect == (10,20,300,400)");

    NSDictionary *ls = [re listViewSettingsForDirectory];
    CHECK(ls != nil && [[ls objectForKey:@"textSize"] intValue] == 14, "lsvp decoded textSize == 14");

    [re release];

    /* Reverse: read a real Mac 10.6 .DS_Store (only Iloc is present - this
     * Finder build stores view/window state outside .DS_Store).  The reader
     * must load it without error and correctly report the ABSENCE of view/
     * window records (it must not invent or crash on real Mac output). */
    DSStore *mac = [[DSStore alloc] initWithPath:fixture(@"ds_viewlist.DS_Store")];
    CHECK([mac load], "reverse: load real Mac .DS_Store");
    CHECK([mac viewStyleForDirectory] == nil, "reverse: Mac file has no vstl (viewStyle nil)");
    CHECK(rectEq([mac browserWindowBoundsForDirectory], NSZeroRect), "reverse: Mac file has no bwsp (bounds zero)");
    CHECK(rectEq([mac windowGeometryRectForDirectory], NSZeroRect), "reverse: Mac file has no fwi0 (rect zero)");
    /* Child icon positions must be readable from the real Mac file. */
    NSPoint ap = [mac iconLocationForFilename:@"a.txt"];
    CHECK(ap.x == 92 && ap.y == 31, "reverse: a.txt Iloc (92,31) from Mac file");
    [mac release];
    [[NSFileManager defaultManager] removeFileAtPath:outPath handler:nil];

    if (failures == 0) printf("VIEWWINDOW INTEROP TEST PASSED\n");
    else printf("VIEWWINDOW INTEROP TEST FAILED (%d)\n", failures);
    [pool release];
    return failures ? 1 : 0;
}
