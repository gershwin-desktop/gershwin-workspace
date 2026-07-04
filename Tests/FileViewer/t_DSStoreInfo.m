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

    DSStoreInfo *w = [[[DSStoreInfo alloc] initWithDirectoryPath: dir] autorelease];
    [w takeValuesFromViewerPrefs: @{ @"viewtype" : @"Icon",
                                     @"geometry" : NSStringFromRect(NSMakeRect(100, 150, 600, 400)) }];
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
    PASS(r.hasViewStyle && r.viewStyle == DSStoreViewStyleIcon,
         "view style survives the on-disk round-trip");
    DSStoreIconInfo *ri = [r iconInfoForFilename: @"doc.txt"];
    PASS(ri != nil && [ri hasPosition]
         && NSEqualPoints([ri position], NSMakePoint(80, 160)),
         "per-icon Iloc position survives the on-disk round-trip");

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

  [arp release];
  return 0;
}
