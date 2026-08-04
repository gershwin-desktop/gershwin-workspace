/* t_DSStoreInfo.m — ObjectTesting coverage for the DSStoreInfo model.
 *
 * Covers the migration-critical, in-memory conversion the persistence
 * consolidation depends on: mapping a GNUstep viewer-prefs dictionary into
 * DSStoreInfo fields (view style, window geometry, icon size), and the
 * per-icon Iloc position set/get accessors.
 *
 * The unit under test is compiled in-process; its DSStore back-end sources are
 * linked as separate objects (see GNUmakefile.preamble).  Runs headless.
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

#import <Foundation/Foundation.h>
#import "Testing.h"

#include "../../Workspace/FileViewer/DSStoreInfo.m"

int
main(void)
{
  NSAutoreleasePool *arp = [NSAutoreleasePool new];

  /* --- viewer-prefs -> DSStoreInfo mapping (the migration path) --- */
  {
    DSStoreInfo *info =
      [[[DSStoreInfo alloc] initWithDirectoryPath: @"/tmp/does-not-exist"] autorelease];

    NSDictionary *prefs = @{
      @"geometry" : NSStringFromRect(NSMakeRect(120, 240, 640, 480)),
      @"viewtype" : @"Icon",
      @"iconsize" : @48,
      @"iconspos" : @"bottom",
    };
    [info takeValuesFromViewerPrefs: prefs];

    PASS(info.hasWindowFrame
         && NSEqualRects(info.windowFrame, NSMakeRect(120, 240, 640, 480)),
         "takeValuesFromViewerPrefs maps geometry -> windowFrame");
    PASS(info.hasViewStyle && info.viewStyle == DSStoreViewStyleIcon,
         "takeValuesFromViewerPrefs maps viewtype 'Icon' -> DSStoreViewStyleIcon");
    PASS(info.hasIconSize && info.iconSize == 48,
         "takeValuesFromViewerPrefs maps iconsize");
    PASS(info.hasLabelPosition && info.labelPosition == DSStoreLabelPositionBottom,
         "takeValuesFromViewerPrefs maps iconspos 'bottom' -> label position");
  }

  /* --- GNUstep saved-frame geometry parsing (regression) ---
   * [NSWindow stringWithSavedFrame] yields "450 531 516 300 0 0 1920 1058",
   * which NSRectFromString cannot parse; the migration must accept it. */
  {
    DSStoreInfo *info =
      [[[DSStoreInfo alloc] initWithDirectoryPath: @"/tmp/does-not-exist"] autorelease];
    [info takeValuesFromViewerPrefs:
      @{ @"geometry" : @"450 531 516 300 0 0  1920 1058 " }];
    PASS(info.hasWindowFrame
         && NSEqualRects(info.windowFrame, NSMakeRect(450, 531, 516, 300)),
         "takeValuesFromViewerPrefs parses the GNUstep saved-frame string");
  }

  /* --- per-icon Iloc position set/get --- */
  {
    DSStoreInfo *info =
      [[[DSStoreInfo alloc] initWithDirectoryPath: @"/tmp/does-not-exist"] autorelease];

    PASS(info.hasAnyIconPositions == NO,
         "a fresh DSStoreInfo has no icon positions");

    DSStoreIconInfo *icon =
      [[[DSStoreIconInfo alloc] initWithFilename: @"file.txt"] autorelease];
    icon.position = NSMakePoint(64, 128);
    icon.hasPosition = YES;
    [info setIconInfo: icon forFilename: @"file.txt"];

    PASS(info.hasAnyIconPositions,
         "setIconInfo records an icon position");
    PASS([[info filenamesWithPositions] containsObject: @"file.txt"],
         "filenamesWithPositions lists the positioned icon");

    DSStoreIconInfo *back = [info iconInfoForFilename: @"file.txt"];
    PASS(back != nil && [back hasPosition]
         && NSEqualPoints([back position], NSMakePoint(64, 128)),
         "iconInfoForFilename round-trips the stored Iloc position");
  }

  /* --- on-disk .DS_Store binary round-trip (the shared store both viewers
   *     now persist to) --- */
  {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *dir = [NSTemporaryDirectory() stringByAppendingPathComponent:
                      [NSString stringWithFormat: @"t_dsstore_%d", (int)getpid()]];
    [fm removeFileAtPath: dir handler: nil];
    [fm createDirectoryAtPath: dir attributes: nil];
    [fm createFileAtPath: [dir stringByAppendingPathComponent: @"doc.txt"]
                contents: [NSData data] attributes: nil];

    DSStoreInfo *w = [[[DSStoreInfo alloc] initWithDirectoryPath: dir] autorelease];
    [w takeValuesFromViewerPrefs: @{ @"viewtype" : @"List",
                                     @"geometry" : NSStringFromRect(NSMakeRect(100, 150, 600, 400)),
                                     @"hligh_table_col" : @2,   /* dateModified */
                                     @"list_view_columns" : @{
                                         @"0" : @{ @"identifier" : @0, @"width" : @220 },
                                         @"2" : @{ @"identifier" : @2, @"width" : @140 }
                                     } }];
    DSStoreIconInfo *icon =
      [[[DSStoreIconInfo alloc] initWithFilename: @"doc.txt"] autorelease];
    icon.position = NSMakePoint(80, 160);
    icon.hasPosition = YES;
    [w setIconInfo: icon forFilename: @"doc.txt"];

    NSString *dsPath = [dir stringByAppendingPathComponent: @".DS_Store"];
    PASS([w saveToPath: dsPath], "saveToPath writes a .DS_Store binary");
    PASS([fm fileExistsAtPath: dsPath], "the .DS_Store file exists on disk");

    DSStoreInfo *r = [DSStoreInfo infoForDirectoryPath: dir];
    PASS(r != nil && r.loaded, "the .DS_Store loads back from disk");
    PASS(r.hasViewStyle && r.viewStyle == DSStoreViewStyleList,
         "view style survives the on-disk round-trip");
    DSStoreIconInfo *ri = [r iconInfoForFilename: @"doc.txt"];
    PASS(ri != nil && [ri hasPosition]
         && NSEqualPoints([ri position], NSMakePoint(80, 160)),
         "per-icon Iloc position survives the on-disk round-trip");
    PASS(r.hasWindowFrame
         && NSEqualRects([r gnustepWindowFrameForScreen: [DSStoreInfo safeMainScreen]],
                         NSMakeRect(100, 150, 600, 400)),
         "window geometry (bwsp/fwi0) survives the on-disk round-trip");
    PASS(r.hasSortColumn
         && [r.sortColumn isEqualToString: @"dateModified"],
         "list sort column survives the on-disk round-trip (lsvp)");
    PASS(r.columnWidths != nil
         && [[r.columnWidths objectForKey: @"dateModified"] floatValue] == 140.0,
         "list column widths survive the on-disk round-trip (lsvp)");

    [fm removeFileAtPath: dir handler: nil];
  }

  /* --- preservingExisting: migration must merge, not clobber --- */
  {
    DSStoreInfo *info =
      [[[DSStoreInfo alloc] initWithDirectoryPath: @"/tmp/does-not-exist"] autorelease];
    /* Existing (e.g. from the just-read .DS_Store): List + a window frame. */
    [info takeValuesFromViewerPrefs: @{ @"viewtype" : @"List",
                                        @"geometry" : NSStringFromRect(NSMakeRect(10, 20, 500, 300)) }];
    PASS(info.hasViewStyle && info.viewStyle == DSStoreViewStyleList,
         "precondition: existing view style is List");

    /* Legacy source (.gwdir) tries to set Icon + a different frame + a new
     * iconSize.  With preserve, only the gap (iconSize) may be filled. */
    [info takeValuesFromViewerPrefs: @{ @"viewtype" : @"Icon",
                                        @"geometry" : NSStringFromRect(NSMakeRect(0, 0, 999, 999)),
                                        @"iconsize" : @48 }
                 preservingExisting: YES];

    PASS(info.viewStyle == DSStoreViewStyleList,
         "preserve: existing view style is NOT clobbered by the legacy source");
    PASS(NSEqualRects(info.windowFrame, NSMakeRect(10, 20, 500, 300)),
         "preserve: existing window frame is NOT clobbered");
    PASS(info.hasIconSize && info.iconSize == 48,
         "preserve: a field the existing store lacks (iconSize) IS filled");

    /* Without preserve, the same call overwrites. */
    [info takeValuesFromViewerPrefs: @{ @"viewtype" : @"Icon" }
                 preservingExisting: NO];
    PASS(info.viewStyle == DSStoreViewStyleIcon,
         "no-preserve: view style IS overwritten (legacy behavior intact)");
  }

  /* --- mergeMissingFieldsFromInfo: partial writes must not clobber --- */
  {
    DSStoreInfo *existing =
      [[[DSStoreInfo alloc] initWithDirectoryPath: @"/tmp/does-not-exist"] autorelease];
    [existing takeValuesFromViewerPrefs: @{ @"viewtype" : @"Icon",
                                            @"geometry" : NSStringFromRect(NSMakeRect(10, 20, 500, 300)),
                                            @"iconsize" : @48 }];
    DSStoreIconInfo *ei = [DSStoreIconInfo infoForFilename: @"a.txt"];
    ei.position = NSMakePoint(30, 40);
    ei.hasPosition = YES;
    [existing setIconInfo: ei forFilename: @"a.txt"];

    /* Partial write: only a label color for one file, nothing else set. */
    DSStoreInfo *partial =
      [[[DSStoreInfo alloc] initWithDirectoryPath: @"/tmp/does-not-exist"] autorelease];
    DSStoreIconInfo *pi = [DSStoreIconInfo infoForFilename: @"a.txt"];
    pi.labelColor = DSStoreLabelColorRed;
    pi.hasLabelColor = YES;
    [partial setIconInfo: pi forFilename: @"a.txt"];

    [partial mergeMissingFieldsFromInfo: existing];

    PASS(partial.hasViewStyle && partial.viewStyle == DSStoreViewStyleIcon,
         "merge: missing view style is filled from existing");
    PASS(partial.hasWindowFrame
         && NSEqualRects(partial.windowFrame, NSMakeRect(10, 20, 500, 300)),
         "merge: missing window frame is filled from existing");
    PASS(partial.hasIconSize && partial.iconSize == 48,
         "merge: missing icon size is filled from existing");

    DSStoreIconInfo *m = [partial iconInfoForFilename: @"a.txt"];
    PASS(m != nil && [m hasLabelColor] && [m labelColor] == DSStoreLabelColorRed,
         "merge: the partial entry keeps its own label color");
    PASS(m != nil && [m hasPosition] && NSEqualPoints([m position], NSMakePoint(30, 40)),
         "merge: existing position is preserved under the same filename");

    /* Merge into an empty receiver copies everything. */
    DSStoreInfo *empty =
      [[[DSStoreInfo alloc] initWithDirectoryPath: @"/tmp/does-not-exist"] autorelease];
    [empty mergeMissingFieldsFromInfo: existing];
    PASS(empty.hasViewStyle && empty.hasWindowFrame && empty.hasIconSize,
         "merge: an empty receiver adopts all fields from existing");
  }

  /* --- read filters ghost per-file entries ---
   * A foreign Finder (or a removed/renamed file) can leave an Iloc entry for
   * a filename that is no longer an on-disk child of the directory.  Those
   * ghosts collide with live files on reopen, so loading must drop them. */
  {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *dir = [NSTemporaryDirectory() stringByAppendingPathComponent:
                      [NSString stringWithFormat: @"t_dsstore_prune_%d", (int)getpid()]];
    [fm removeFileAtPath: dir handler: nil];
    [fm createDirectoryAtPath: dir attributes: nil];
    [fm createFileAtPath: [dir stringByAppendingPathComponent: @"real.txt"]
                contents: [NSData data] attributes: nil];

    NSString *dsPath = [dir stringByAppendingPathComponent: @".DS_Store"];

    DSStoreInfo *w = [[[DSStoreInfo alloc] initWithDirectoryPath: dir] autorelease];
    DSStoreIconInfo *real = [DSStoreIconInfo infoForFilename: @"real.txt"];
    real.position = NSMakePoint(100, 100);
    real.hasPosition = YES;
    [w setIconInfo: real forFilename: @"real.txt"];
    PASS([w saveToPath: dsPath], "ghost: initial save succeeds");

    /* Inject a ghost entry for a non-existent file. */
    {
      DSStore *store = [DSStore createStoreAtPath: dsPath withEntries: nil];
      [store load];
      [store setEntry: [DSStoreEntry iconLocationEntryForFile: @"ghost.txt"
                                                             x: 50 y: 50]];
      [store save];
    }
    DSStoreInfo *rw = [DSStoreInfo infoForDirectoryPath: dir];
    PASS(rw != nil && rw.loaded, "ghost: reload succeeds");
    DSStoreIconInfo *ghost = [rw iconInfoForFilename: @"ghost.txt"];
    PASS(ghost == nil || ![ghost hasPosition],
         "ghost: non-existent file's Iloc is filtered on load");
    DSStoreIconInfo *rkept = [rw iconInfoForFilename: @"real.txt"];
    PASS(rkept != nil && [rkept hasPosition],
         "ghost: real on-disk child's Iloc is kept");

    /* Re-save: the write path must also prune the ghost from the file. */
    [rw takeValuesFromViewerPrefs: @{ @"viewtype" : @"Icon" }];
    PASS([rw saveToPath: dsPath], "ghost: re-save succeeds");
    {
      DSStore *chk = [DSStore storeWithPath: dsPath];
      [chk load];
      BOOL ghostGone =
        ([chk entryForFilename: @"ghost.txt" code: @"Iloc"] == nil);
      PASS(ghostGone, "ghost: write prunes the ghost entry from disk");
      BOOL realKept =
        ([chk entryForFilename: @"real.txt" code: @"Iloc"] != nil);
      PASS(realKept, "ghost: write keeps the real on-disk child entry");
    }

    [fm removeFileAtPath: dir handler: nil];
  }

  /* liveIconPositions / setLiveIconPositions: a close-write must persist the
   * live on-screen layout and DROP any foreign colliding/stale position. */
  {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *dir = [NSTemporaryDirectory() stringByAppendingPathComponent:
                      [NSString stringWithFormat: @"t_dsstore_live_%d", (int)getpid()]];
    [fm removeFileAtPath: dir handler: nil];
    [fm createDirectoryAtPath: dir attributes: nil];
    [fm createFileAtPath: [dir stringByAppendingPathComponent: @"a.txt"]
                contents: [NSData data] attributes: nil];
    [fm createFileAtPath: [dir stringByAppendingPathComponent: @"b.txt"]
                contents: [NSData data] attributes: nil];

    NSString *dsPath = [dir stringByAppendingPathComponent: @".DS_Store"];

    /* Seed with a stale colliding position for b.txt (a foreign Finder) and
     * an entry for a file that no longer exists (ghost.txt). */
    {
      DSStoreInfo *w = [[[DSStoreInfo alloc] initWithDirectoryPath: dir] autorelease];
      DSStoreIconInfo *b = [DSStoreIconInfo infoForFilename: @"b.txt"];
      b.position = NSMakePoint(80, 202);
      b.hasPosition = YES;
      [w setIconInfo: b forFilename: @"b.txt"];
      DSStoreIconInfo *g = [DSStoreIconInfo infoForFilename: @"ghost.txt"];
      g.position = NSMakePoint(80, 202);
      g.hasPosition = YES;
      [w setIconInfo: g forFilename: @"ghost.txt"];
      PASS([w saveToPath: dsPath], "live: seed save succeeds");
    }

    /* Simulate the live layout: a.txt at (80,202), b.txt at (220,202). */
    DSStoreInfo *info = [DSStoreInfo infoForDirectoryPath: dir];
    PASS(info != nil && info.loaded, "live: reload succeeds");
    [info setLiveIconPositions:
      @{ @"a.txt": [NSValue valueWithPoint: NSMakePoint(80, 202)],
         @"b.txt": [NSValue valueWithPoint: NSMakePoint(220, 202)] }];
    NSArray *names = [info filenamesWithPositions];
    PASS([names count] == 2
         && [names containsObject: @"a.txt"]
         && [names containsObject: @"b.txt"],
         "live: setLiveIconPositions replaces the map (2 live files)");
    DSStoreIconInfo *livA = [info iconInfoForFilename: @"a.txt"];
    PASS(livA != nil && [livA hasPosition]
         && (int)livA.position.x == 80 && (int)livA.position.y == 202,
         "live: a.txt holds its live iloc");
    PASS([info iconInfoForFilename: @"ghost.txt"] == nil,
         "live: foreign ghost entry dropped by setLiveIconPositions");

    /* After writing, on-disk must reflect the live layout only. */
    PASS([info saveToPath: dsPath], "live: write succeeds");
    {
      DSStoreInfo *chk = [DSStoreInfo infoForDirectoryPath: dir];
      NSArray *chkNames = [chk filenamesWithPositions];
      PASS([chkNames count] == 2
           && [chkNames containsObject: @"a.txt"]
           && [chkNames containsObject: @"b.txt"]
           && ![chkNames containsObject: @"ghost.txt"],
           "live: on-disk holds only the live files after write");
      DSStoreIconInfo *chkB = [chk iconInfoForFilename: @"b.txt"];
      PASS(chkB != nil && [chkB hasPosition]
           && (int)chkB.position.x == 220 && (int)chkB.position.y == 202,
           "live: b.txt keeps its live iloc (no foreign collision)");
    }

    [fm removeFileAtPath: dir handler: nil];
  }

  [arp release];
  return 0;
}
