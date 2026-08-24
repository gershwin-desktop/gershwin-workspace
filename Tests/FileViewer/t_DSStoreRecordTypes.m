/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 */
/* Comprehensive round-trip test: exercise EVERY record type the DSStore
 * writer supports (folder self-entry "." settings + per-file records),
 * save, reload, and assert each value round-trips.  This is the Gershwin
 * side of macOS .DS_Store interoperability; see INTEROP_DSSTORE.md.
 * Mac acceptance of the multi-type file is verified separately on the
 * reference Mac mini (Finder must honor Iloc and not reject the file). */
#import <Foundation/Foundation.h>
#include "DSStore.h"

static int failures = 0;
#define CHECK(cond, msg) do { if (!(cond)) { failures++; printf("FAIL: %s (%s:%d)\n", msg, __FILE__, __LINE__); } else { printf("ok: %s\n", msg); } } while (0)

int main(void)
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    NSString *outPath = @"/tmp/rttest.DS_Store";
    [[NSFileManager defaultManager] removeFileAtPath:outPath handler:nil];

    DSStore *store = [DSStore createStoreAtPath:outPath withEntries:nil];
    CHECK(store != nil, "create store");

    /* ---- Folder self-entry (".") view/window settings ---- */
    [store setIconLocationForFilename:@"." x:120 y:120];
    [store setViewStyleForDirectory:@"icnv"];
    [store setIconSizeForDirectory:64];
    [store setGridSpacingForDirectory:20];
    [store setTextSizeForDirectory:14];
    [store setLabelPositionForDirectory:DSStoreLabelPositionRight];
    [store setShowItemInfoForDirectory:YES];
    [store setShowIconPreviewForDirectory:YES];
    [store setIconArrangementForDirectory:DSStoreIconArrangementGrid];
    [store setSortByForDirectory:@"name"];
    [store setSidebarWidthForDirectory:150];
    [store setShowToolbarForDirectory:YES];
    [store setShowSidebarForDirectory:YES];
    [store setShowPathBarForDirectory:YES];
    [store setShowStatusBarForDirectory:YES];
    [store setBackgroundColorForDirectory:[SimpleColor colorWithRed:0.5f green:0.2f blue:0.8f alpha:1.0f]];
    [store setShowRelativeDatesForDirectory:YES];
    /* setListViewSettings must run before the column-width/visibility setters
     * below: each column setter merges into the shared "lsvp" record, so the
     * lsvp written here must exist first or it would be overwritten. */
    [store setListViewSettings:[NSDictionary dictionaryWithObjectsAndKeys:
        [NSNumber numberWithInt:12], @"textSize",
        [NSNumber numberWithInt:32], @"iconSize", nil]];
    [store setColumnWidthForDirectory:@"name" width:120];
    [store setColumnVisibleForDirectory:@"date" visible:NO];
    [store setEntry:[DSStoreEntry browserWindowEntryForFile:@"." windowBounds:NSMakeRect(0,0,800,600) sidebarWidth:150]];
    [store setEntry:[DSStoreEntry windowGeometryEntryForFile:@"." rect:NSMakeRect(10,20,300,400) viewStyle:@"icnv"]];

    /* ---- Per-file records on a.txt ---- */
    [store setIconLocationForFilename:@"a.txt" x:40 y:40];
    [store setLabelColorForFilename:@"a.txt" color:DSStoreLabelColorRed];
    [store setCommentsForFilename:@"a.txt" comments:@"hello world"];
    [store setLogicalSizeForFilename:@"a.txt" size:12345];
    [store setPhysicalSizeForFilename:@"a.txt" size:67890];
    NSDate *mod = [NSDate dateWithTimeIntervalSince1970:1000000000.0];
    [store setModificationDateForFilename:@"a.txt" date:mod];

    CHECK([store save], "save returns YES");

    /* ---- Reload and verify round-trip ---- */
    DSStore *re = [[DSStore alloc] initWithPath:outPath];
    CHECK([re load], "reload returns YES");

    NSPoint dot = [re iconLocationForFilename:@"."];
    CHECK(dot.x == 120 && dot.y == 120, "self-entry Iloc == (120,120)");
    CHECK([[re viewStyleForDirectory] isEqualToString:@"icnv"], "vstl == icnv");
    CHECK([re iconSizeForDirectory] == 64, "icvo icon size == 64");
    CHECK([re gridSpacingForDirectory] == 20, "icsp grid spacing == 20");
    CHECK([re textSizeForDirectory] == 14, "lsvt text size == 14");
    CHECK([re labelPositionForDirectory] == DSStoreLabelPositionRight, "lblp == right");
    CHECK([re showItemInfoForDirectory] == YES, "info == YES");
    CHECK([re showIconPreviewForDirectory] == YES, "prvw == YES");
    CHECK([re iconArrangementForDirectory] == DSStoreIconArrangementGrid, "iarr == grid");
    CHECK([[re sortByForDirectory] isEqualToString:@"name"], "GRP0 == name");
    CHECK([re sidebarWidthForDirectory] == 150, "fwsw == 150");
    CHECK([re showToolbarForDirectory] == YES, "fgtb/stbr == YES");
    CHECK([re showSidebarForDirectory] == YES, "fwse/ssbr == YES");
    CHECK([re showPathBarForDirectory] == YES, "fvpb/pbar == YES");
    CHECK([re showStatusBarForDirectory] == YES, "fvtb/sbar == YES");

    SimpleColor *bg = [re backgroundColorForDirectory];
    float r,g,b,a;
    [bg getRed:&r green:&g blue:&b alpha:&a];
    CHECK(r > 0.49f && r < 0.51f && b > 0.79f && b < 0.81f, "BKGD color round-trip");
    CHECK([re showRelativeDatesForDirectory] == YES, "cvlc (relative dates) == YES");
    CHECK([re columnWidthForDirectory:@"name"] == 120, "lsvp column name width == 120");
    CHECK([re columnVisibleForDirectory:@"date"] == NO, "lsvp column date visible == NO");

    DSStoreEntry *lsvp = [re entryForFilename:@"." code:@"lsvp"];
    CHECK(lsvp != nil && [[lsvp value] isKindOfClass:[NSData class]], "lsvp present + plist data");
    if (lsvp && [[lsvp value] isKindOfClass:[NSData class]]) {
        NSDictionary *ld = [NSPropertyListSerialization propertyListWithData:(NSData *)[lsvp value]
                                            options:NSPropertyListImmutable format:NULL error:NULL];
        CHECK(ld != nil && [[ld objectForKey:@"textSize"] intValue] == 12, "lsvp textSize == 12");
    }
    DSStoreEntry *bwsp = [re entryForFilename:@"." code:@"bwsp"];
    CHECK(bwsp != nil && [[bwsp value] isKindOfClass:[NSData class]], "bwsp present + plist data");
    if (bwsp && [[bwsp value] isKindOfClass:[NSData class]]) {
        NSDictionary *bd = [NSPropertyListSerialization propertyListWithData:(NSData *)[bwsp value]
                                            options:NSPropertyListImmutable format:NULL error:NULL];
        CHECK(bd != nil && [bd objectForKey:@"WindowBounds"] != nil, "bwsp WindowBounds present");
    }
    DSStoreEntry *fwi0 = [re entryForFilename:@"." code:@"fwi0"];
    CHECK(fwi0 != nil, "fwi0 (window geometry) present");
    if (fwi0 && [[fwi0 value] isKindOfClass:[NSData class]] && [[fwi0 value] length] >= 16) {
        NSData *fd = (NSData *)[fwi0 value];
        const unsigned char *fb = [fd bytes];
        /* stored big-endian: byte0 is MSB */
        uint16_t top    = (uint16_t)((fb[0] << 8) | fb[1]);
        uint16_t left   = (uint16_t)((fb[2] << 8) | fb[3]);
        uint16_t bottom = (uint16_t)((fb[4] << 8) | fb[5]);
        uint16_t right  = (uint16_t)((fb[6] << 8) | fb[7]);
        CHECK(top==20 && left==10 && bottom==420 && right==310, "fwi0 bounds (10,20,300,400)");
    }

    /* Per-file */
    NSPoint ap = [re iconLocationForFilename:@"a.txt"];
    CHECK(ap.x == 40 && ap.y == 40, "a.txt Iloc == (40,40)");
    CHECK([re labelColorForFilename:@"a.txt"] == DSStoreLabelColorRed, "a.txt lclr == red");
    CHECK([[re commentsForFilename:@"a.txt"] isEqualToString:@"hello world"], "a.txt cmmt round-trip");
    CHECK([re logicalSizeForFilename:@"a.txt"] == 12345, "a.txt lg1S == 12345");
    CHECK([re physicalSizeForFilename:@"a.txt"] == 67890, "a.txt ph1S == 67890");
    NSDate *rmod = [re modificationDateForFilename:@"a.txt"];
    CHECK(rmod != nil && fabs([rmod timeIntervalSinceDate:mod]) < 2.0, "a.txt modD round-trip");

    /* Background image and background color are mutually exclusive (both use
     * the BKGD code), so the image path is verified in its own store. */
    {
        NSString *p2 = @"/tmp/rttest_img.DS_Store";
        [[NSFileManager defaultManager] removeFileAtPath:p2 handler:nil];
        DSStore *s2 = [DSStore createStoreAtPath:p2 withEntries:nil];
        [s2 setBackgroundImagePathForDirectory:@"/tmp/background.png"];
        CHECK([s2 save], "img store save");
        DSStore *r2 = [[DSStore alloc] initWithPath:p2];
        CHECK([r2 load], "img store load");
        CHECK([[r2 backgroundImagePathForDirectory] isEqualToString:@"/tmp/background.png"], "BKGD image path round-trip");
        [r2 release];
        [[NSFileManager defaultManager] removeFileAtPath:p2 handler:nil];
    }

    [re release];
    [[NSFileManager defaultManager] removeFileAtPath:outPath handler:nil];

    if (failures == 0) printf("RECORDTYPES TEST PASSED\n");
    else printf("RECORDTYPES TEST FAILED (%d)\n", failures);
    [pool release];
    return failures ? 1 : 0;
}
