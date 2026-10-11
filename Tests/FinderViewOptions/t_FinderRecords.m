/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 */

/* The view and window records Finder 10.6 writes for a folder, read and
 * written by DSStoreInfo against the stores the Mac wrote (the Scout's finder106 fixtures, see
 * Documentation/interop/assertions-i-viewers.md for the ids).  Headless. */

#import <AppKit/AppKit.h>
#import "Testing.h"
#include <sys/stat.h>
#import "DSStore.h"
#import "DSStoreEntry.h"
#import "DSStoreInfo.h"
#import "GWViewSettingsManager.h"
#import "GWVolumeCache.h"
#import "GSFileMetadata.h"
#import "GWViewerChrome.h"
#include <unistd.h>

/* The stores Finder 10.6.8 wrote, kept with the Scout's evidence. */
static NSString *const GWFinderFixtures = @"../GWMetadata/interop/fixtures/finder106";

@interface PostCounter : NSObject
{
@public
  int posts;
}
@end

@implementation PostCounter
- (void)changed:(NSNotification *)n
{
  posts++;
}
@end

/* The scale factor the conversions see, set for this process only so the
 * tests neither depend on nor change the user's own GSScaleFactor. */
static void
setTestScaleFactor(float scale)
{
  NSUserDefaults *defs = [NSUserDefaults standardUserDefaults];

  [defs removeVolatileDomainForName: NSArgumentDomain];
  [defs setVolatileDomain: [NSDictionary dictionaryWithObject:
                                           [NSNumber numberWithFloat: scale]
                                                       forKey: @"GSScaleFactor"]
                  forName: NSArgumentDomain];
}

static NSString *root;
static NSFileManager *fm;

/* A folder @p name inside a fresh parent whose .DS_Store is the fixture. */
static NSString *
folderUnderFixture(NSString *fixture, NSString *name)
{
  NSString *parent = [root stringByAppendingPathComponent:
                             [NSString stringWithFormat: @"%@-%@", fixture, name]];
  NSString *dir = [parent stringByAppendingPathComponent: name];

  [fm removeFileAtPath: parent handler: nil];
  [fm createDirectoryAtPath: dir withIntermediateDirectories: YES attributes: nil error: NULL];
  if (fixture)
    {
      [fm copyItemAtPath: [[[fm currentDirectoryPath] stringByAppendingPathComponent: GWFinderFixtures]
                            stringByAppendingPathComponent: fixture]
                  toPath: [parent stringByAppendingPathComponent: @".DS_Store"]
                   error: NULL];
    }
  return dir;
}

static NSDictionary *
plistOf(DSStore *store, NSString *name, NSString *code)
{
  DSStoreEntry *e = [store entryForFilename: name code: code];

  if (e == nil)
    return nil;
  return [NSPropertyListSerialization propertyListWithData: [e value]
                                                   options: 0
                                                    format: NULL
                                                     error: NULL];
}

static DSStore *
loadedStore(NSString *path)
{
  /* DSStore wants an absolute path. */
  DSStore *s = [DSStore storeWithPath: [path isAbsolutePath] ? path
                  : [[[NSFileManager defaultManager] currentDirectoryPath]
                      stringByAppendingPathComponent: path]];

  return [s load] ? s : nil;
}

static BOOL
isReal(id n)
{
  const char *t = [n objCType];

  return t && (strcmp(t, "d") == 0 || strcmp(t, "f") == 0);
}

int
main(void)
{
  NSAutoreleasePool *arp = [NSAutoreleasePool new];
  NSString *e1 = @"E1-parent-icvp-bwsp.DS_Store";
  NSString *e8 = @"E8-option-matrix.parent.DS_Store";

  fm = [NSFileManager defaultManager];
  root = [[NSTemporaryDirectory() stringByAppendingPathComponent:
             [NSString stringWithFormat: @"t_FinderRecords-%d", (int)getpid()]] retain];
  [fm createDirectoryAtPath: root withIntermediateDirectories: YES attributes: nil error: NULL];
  setTestScaleFactor(1.0);

  START_SET("store parsing")
    DSStore *s = loadedStore([GWFinderFixtures stringByAppendingPathComponent: e8]);

    NEED(PASS(s != nil, "the Mac store loads"));
    /* lsvt is a 'shor' (four bytes on disk); reading two used to lose the
     * records after it in the node. */
    PASS([[s entryForFilename: @"m_lcv" code: @"lsvt"] value] != nil,
         "MI-IV-1 the shor record lsvt is read");
    PASS([s entryForFilename: @"m_lcw" code: @"lsvp"] != nil,
         "MI-IV-2 the record after a shor record is not lost");
  END_SET("store parsing")

  START_SET("a record longer than 64 KiB survives a round trip")
    NSString *path = [root stringByAppendingPathComponent: @"big.DS_Store"];
    NSMutableData *big = [NSMutableData dataWithLength: 70000];
    DSStore *s = [DSStore createStoreAtPath: path withEntries: nil];
    DSStore *back;

    ((unsigned char *)[big mutableBytes])[69999] = 0x5a;
    [s load];
    [s setEntry: [[[DSStoreEntry alloc] initWithFilename: @"a" code: @"zzzz"
                                                    type: @"blob" value: big] autorelease]];
    [s setEntry: [DSStoreEntry viewStyleEntryForFile: @"b" style: @"Nlsv"]];
    [s save];
    back = loadedStore(path);
    PASS([[[back entryForFilename: @"a" code: @"zzzz"] value] isEqual: big],
         "MI-IV-3 a 70000 byte blob comes back whole");
    PASS([[[back entryForFilename: @"b" code: @"vstl"] value] isEqual: @"Nlsv"],
         "MI-IV-4 and the record after it too");
  END_SET("a record longer than 64 KiB survives a round trip")

  START_SET("a folder's records in its parent's store [O:E1]")
    DSStoreInfo *a = [DSStoreInfo infoForDirectoryPath: folderUnderFixture(e1, @"eA")];
    DSStoreInfo *b = [DSStoreInfo infoForDirectoryPath: folderUnderFixture(e1, @"eB")];

    PASS(a.hasIconSize && a.iconSize == 96, "MI-IV-5 icvp iconSize under the folder's name is read");
    PASS(a.hasWindowFrame && NSEqualRects(a.windowFrame, NSMakeRect(200, 168, 500, 400)),
         "MI-IV-6 WindowBounds is the window with a 22 point title, origin bottom left [O:E7]");
    PASS(a.hasShowToolbar && a.showToolbar && a.hasShowStatusBar && a.showStatusBar
         && a.hasShowPathbar && !a.showPathbar && a.hasShowSidebar && a.showSidebar,
         "MI-IV-7 the bwsp chrome flags are read");
    PASS(b.hasShowToolbar && !b.showToolbar && !b.showSidebar && b.sidebarWidth == 193,
         "MI-IV-8 a window without toolbar and sidebar [F:E1 eB]");
  END_SET("a folder's records in its parent's store [O:E1]")

  START_SET("the parent's record wins over the folder's own")
    NSString *dir = folderUnderFixture(e1, @"eA");
    DSStore *own = [DSStore createStoreAtPath: [dir stringByAppendingPathComponent: @".DS_Store"]
                                  withEntries: nil];
    DSStoreInfo *info;

    [own load];
    [own setEntry: [DSStoreEntry plistEntryForFile: @"." code: @"icvp"
                                        dictionary: @{ @"iconSize" : @32, @"textSize" : @14 }]];
    [own save];
    info = [DSStoreInfo infoForDirectoryPath: dir];
    PASS(info.iconSize == 96, "MI-IV-9 the parent's icvp is what Finder reads [O:E2]");
  END_SET("the parent's record wins over the folder's own")

  START_SET("icvp options [F:E8]")
    DSStoreInfo *ts = [DSStoreInfo infoForDirectoryPath: folderUnderFixture(e8, @"m_ts")];
    DSStoreInfo *lp = [DSStoreInfo infoForDirectoryPath: folderUnderFixture(e8, @"m_lp")];
    DSStoreInfo *arr = [DSStoreInfo infoForDirectoryPath: folderUnderFixture(e8, @"m_arr")];
    DSStoreInfo *inf = [DSStoreInfo infoForDirectoryPath: folderUnderFixture(e8, @"m_info")];
    DSStoreInfo *prv = [DSStoreInfo infoForDirectoryPath: folderUnderFixture(e8, @"m_prev")];
    DSStoreInfo *bg = [DSStoreInfo infoForDirectoryPath: folderUnderFixture(e8, @"m_bg")];

    PASS(ts.hasIconTextSize && ts.iconTextSize == 11, "MI-IV-10 textSize");
    PASS(lp.hasLabelPosition && lp.labelPosition == DSStoreLabelPositionRight,
         "MI-IV-11 labelOnBottom 0 is a label on the right");
    PASS([arr.arrangeBy isEqual: @"grid"] && arr.iconArrangement == DSStoreIconArrangementGrid,
         "MI-IV-12 arrangeBy grid is snap to grid");
    PASS(inf.hasShowItemInfo && inf.showItemInfo, "MI-IV-13 showItemInfo");
    PASS(prv.hasShowIconPreview && !prv.showIconPreview, "MI-IV-14 showIconPreview off");
    PASS(ts.hasShowIconPreview && ts.showIconPreview && ts.hasShowItemInfo && !ts.showItemInfo,
         "MI-IV-15 the defaults Finder stores with every icvp");
    PASS(bg.backgroundType == DSStoreBackgroundColor
         && fabs([[bg.backgroundColor colorUsingColorSpaceName: NSCalibratedRGBColorSpace]
                   redComponent] - 0.985948) < 0.0001,
         "MI-IV-16 backgroundType 1 with the colour as reals");
  END_SET("icvp options [F:E8]")

  START_SET("lsvp options [F:E8]")
    DSStoreInfo *sort = [DSStoreInfo infoForDirectoryPath: folderUnderFixture(e8, @"m_lsort")];
    DSStoreInfo *lts = [DSStoreInfo infoForDirectoryPath: folderUnderFixture(e8, @"m_lts")];
    DSStoreInfo *lis = [DSStoreInfo infoForDirectoryPath: folderUnderFixture(e8, @"m_lis")];
    DSStoreInfo *lcs = [DSStoreInfo infoForDirectoryPath: folderUnderFixture(e8, @"m_lcs")];
    DSStoreInfo *lrd = [DSStoreInfo infoForDirectoryPath: folderUnderFixture(e8, @"m_lrd")];
    DSStoreInfo *lci = [DSStoreInfo infoForDirectoryPath: folderUnderFixture(e8, @"m_lci")];
    DSStoreInfo *lcw = [DSStoreInfo infoForDirectoryPath: folderUnderFixture(e8, @"m_lcw")];
    NSArray *order = @[ @"name", @"dateModified", @"size", @"kind" ];
    NSArray *tie = @[ @"name", @"dateModified", @"kind", @"size" ];

    PASS(sort.hasSortColumn && [sort.sortColumn isEqual: @"size"], "MI-IV-17 sortColumn");
    PASS(sort.sortAscending == NO, "MI-IV-18 the direction is the sort column's own ascending");
    PASS([[sort listColumnOrder] isEqual: order], "MI-IV-19 visible columns in index order");
    PASS([[sort.columnWidths objectForKey: @"kind"] intValue] == 115
         && [[sort.columnVisible objectForKey: @"label"] boolValue] == NO,
         "MI-IV-20 width and visibility per column");
    PASS(lts.listTextSize == 10, "MI-IV-21 textSize");
    PASS(lis.listIconSize == 32, "MI-IV-22 iconSize");
    PASS(lcs.hasCalculateAllSizes && lcs.calculateAllSizes, "MI-IV-23 calculateAllSizes");
    PASS(lrd.hasUseRelativeDates && !lrd.useRelativeDates, "MI-IV-24 useRelativeDates off");
    PASS([[lci listColumnOrder] isEqual: tie],
         "MI-IV-25 two columns with one index keep Finder's column order [G: OPEN]");
    PASS([[lcw.columnWidths objectForKey: @"name"] intValue] == 250,
         "MI-IV-26 a column width set by script is an lsvp too");
  END_SET("lsvp options [F:E8]")

  START_SET("the legacy lsvo [F:E8 m_lcv]")
    DSStoreInfo *lcv = [DSStoreInfo infoForDirectoryPath: folderUnderFixture(e8, @"m_lcv")];
    NSArray *order = @[ @"name", @"dateModified", @"size", @"kind", @"comments" ];

    PASS([[lcv listColumnOrder] isEqual: order], "MI-IV-27 lsvo column visibility and order");
    PASS([lcv.sortColumn isEqual: @"name"] && lcv.sortAscending,
         "MI-IV-28 lsvo sort column and direction");
    PASS([[lcv.columnWidths objectForKey: @"size"] intValue] == 97, "MI-IV-29 lsvo widths");
  END_SET("the legacy lsvo [F:E8 m_lcv]")

  START_SET("writing the parent's record")
    NSString *dir = folderUnderFixture(nil, @"w1");
    NSString *parentStore = [[dir stringByDeletingLastPathComponent]
                              stringByAppendingPathComponent: @".DS_Store"];
    DSStoreInfo *w = [[[DSStoreInfo alloc] initWithDirectoryPath: dir] autorelease];
    DSStore *s;
    NSDictionary *icvp, *bwsp;
    NSArray *required = @[ @"textSize", @"gridSpacing", @"labelOnBottom", @"showItemInfo",
                           @"showIconPreview", @"arrangeBy", @"backgroundColorRed",
                           @"backgroundColorGreen", @"backgroundColorBlue" ];
    BOOL complete = YES;

    w.iconSize = 80;
    w.hasIconSize = YES;
    w.windowFrame = NSMakeRect(200, 168, 500, 400);
    w.hasWindowFrame = YES;
    PASS([w saveToParentStore], "MI-IV-30 the parent's store is written");
    s = loadedStore(parentStore);
    icvp = plistOf(s, @"w1", @"icvp");
    bwsp = plistOf(s, @"w1", @"bwsp");
    for (NSString *k in required)
      complete = complete && ([icvp objectForKey: k] != nil);
    PASS(complete, "MI-IV-31 an icvp carries every key Finder needs to honour it [O:E6]");
    PASS([[icvp objectForKey: @"viewOptionsVersion"] intValue] == 0,
         "MI-IV-32 with viewOptionsVersion 0 [O:E6]");
    PASS([[icvp objectForKey: @"iconSize"] intValue] == 80 && isReal([icvp objectForKey: @"iconSize"]),
         "MI-IV-33 sizes are reals, as Finder writes them [F:E8]");
    PASS([[bwsp objectForKey: @"WindowBounds"] isEqual: @"{{200, 168}, {500, 422}}"],
         "MI-IV-34 WindowBounds back in Finder's convention [O:E7]");
    PASS([bwsp objectForKey: @"ShowToolbar"] && [bwsp objectForKey: @"ShowStatusBar"]
         && [bwsp objectForKey: @"ShowPathbar"] && [bwsp objectForKey: @"ShowSidebar"],
         "MI-IV-35 bwsp carries every key Finder writes [F:E1]");
    PASS([s entryForFilename: @"w1" code: @"vstl"] == nil,
         "MI-IV-36 no vstl unless a view was chosen for the folder [O:E5]");
    PASS([s entryForFilename: @"w1" code: @"lsvp"] == nil,
         "MI-IV-37 no lsvp without list options");
  END_SET("writing the parent's record")

  START_SET("Finder's keys survive our write")
    NSString *dir = folderUnderFixture(e8, @"m_lsort");
    NSString *parentStore = [[dir stringByDeletingLastPathComponent]
                              stringByAppendingPathComponent: @".DS_Store"];
    DSStoreInfo *info = [DSStoreInfo infoForDirectoryPath: dir];
    NSDictionary *lsvp, *columns;
    DSStore *s;

    info.sortAscending = YES;
    info.listTextSize = 14;
    PASS([info saveToParentStore], "MI-IV-38 written back");
    s = loadedStore(parentStore);
    lsvp = plistOf(s, @"m_lsort", @"lsvp");
    columns = [lsvp objectForKey: @"columns"];
    PASS([columns isKindOfClass: [NSDictionary class]] && [columns count] == 9,
         "MI-IV-39 columns stay Finder's dictionary of nine [F:E8]");
    PASS([[[columns objectForKey: @"size"] objectForKey: @"ascending"] boolValue]
         && [lsvp objectForKey: @"ascending"] == nil,
         "MI-IV-40 the direction goes into the sort column, not a key of our own");
    PASS([[lsvp objectForKey: @"showIconPreview"] boolValue]
         && [[lsvp objectForKey: @"textSize"] intValue] == 14,
         "MI-IV-41 a key Workspace does not own is kept");
    PASS(plistOf(s, @"m_tb", @"bwsp") != nil && [s entryForFilename: @"m_lcv" code: @"lsvo"] != nil,
         "MI-IV-42 other folders' records and the legacy lsvo stay as they were");
  END_SET("Finder's keys survive our write")

  START_SET("the settings manager writes the parent's store")
    NSString *dir = folderUnderFixture(nil, @"w2");
    GWVolumeCache *cache = [[[GWVolumeCache alloc] initWithCacheFilePath:
                               [root stringByAppendingPathComponent: @"cache.DS_Store"]]
                             autorelease];
    GWViewSettingsManager *sm = [[[GWViewSettingsManager alloc] initWithDirectoryPath: dir
                                                                          volumeCache: cache]
                                  autorelease];
    DSStoreInfo *info = [sm readSettings];
    DSStore *own, *parent;

    info.iconTextSize = 15;
    info.hasIconTextSize = YES;
    {
      DSStoreIconInfo *icon = [DSStoreIconInfo infoForFilename: @"a.txt"];

      [[NSData data] writeToFile: [dir stringByAppendingPathComponent: @"a.txt"] atomically: NO];
      icon.position = NSMakePoint(40, 40);
      icon.hasPosition = YES;
      [info setIconInfo: icon forFilename: @"a.txt"];
    }
    PASS([sm writeSettings: info], "MI-IV-43 settings written");
    own = loadedStore([dir stringByAppendingPathComponent: @".DS_Store"]);
    parent = loadedStore([[dir stringByDeletingLastPathComponent]
                           stringByAppendingPathComponent: @".DS_Store"]);
    PASS([[plistOf(parent, @"w2", @"icvp") objectForKey: @"textSize"] intValue] == 15,
         "MI-IV-44 under the folder's name in the parent [O:E1]");
    PASS([[own allCodesForFilename: @"."] count] == 0
         && [own entryForFilename: @"a.txt" code: @"Iloc"] != nil,
         "MI-IV-45 its own store gets the icon positions but no \".\" records [O:E2, M6]");
    PASS([[[sm readSettings] valueForKey: @"iconTextSize"] intValue] == 15,
         "MI-IV-46 and read back");
  END_SET("the settings manager writes the parent's store")

  START_SET("window geometry is kept in points [O:E7]")
    NSString *dir = folderUnderFixture(nil, @"w4");
    NSString *parentStore = [[dir stringByDeletingLastPathComponent]
                              stringByAppendingPathComponent: @".DS_Store"];
    DSStoreInfo *w = [[[DSStoreInfo alloc] initWithDirectoryPath: dir] autorelease];
    DSStoreInfo *back;
    NSRect finder = NSMakeRect(100, 50, 400, 300);
    NSRect pixels;

    /* The window is measured in device pixels; Finder means points. */
    setTestScaleFactor(1.25);
    w.windowFrame = NSMakeRect(250, 210, 625, 500);
    w.hasWindowFrame = YES;
    [w saveToParentStore];
    PASS([[plistOf(loadedStore(parentStore), @"w4", @"bwsp") objectForKey: @"WindowBounds"]
           isEqual: @"{{200, 168}, {500, 422}}"],
         "MI-IV-90 at 1.25 WindowBounds is the window in points");
    back = [DSStoreInfo infoForDirectoryPath: dir];
    PASS(NSEqualRects(back.windowFrame, NSMakeRect(250, 210, 625, 500)),
         "MI-IV-91 and comes back in pixels");

    pixels = [DSStoreInfo gnustepRectFromDSStoreRect: finder];
    PASS(pixels.size.width == 500 && pixels.size.height == 375 && pixels.origin.x == 125,
         "MI-IV-92 a top-left record (fwi0, FinderInfo) is scaled to pixels as well");
    back.windowFrame = pixels;
    PASS(NSEqualRects([back dsStoreWindowFrameForScreen: nil], finder),
         "MI-IV-93 and written back in points");

    setTestScaleFactor(1.0);
    pixels = [DSStoreInfo gnustepRectFromDSStoreRect: finder];
    PASS(pixels.size.width == 400 && pixels.size.height == 300 && pixels.origin.x == 100,
         "MI-IV-94 at 1.0 points and pixels are the same");
  END_SET("window geometry is kept in points [O:E7]")

  START_SET("path bar and status bar are global settings [O:E13]")
    NSUserDefaults *defs = [NSUserDefaults standardUserDefaults];
    PostCounter *counter = [[PostCounter new] autorelease];

    [defs removeObjectForKey: @"ShowPathbar"];
    [defs removeObjectForKey: @"ShowStatusBar"];
    PASS([GWViewerChrome showsPathBar] && [GWViewerChrome showsStatusBar],
         "MI-IV-98 both are shown by default");
    [[NSNotificationCenter defaultCenter] addObserver: counter
                                             selector: @selector(changed:)
                                                 name: GWViewerChromeDidChangeNotification
                                               object: nil];
    [GWViewerChrome setShowsPathBar: NO];
    [GWViewerChrome setShowsStatusBar: NO];
    PASS(![GWViewerChrome showsPathBar] && ![defs boolForKey: @"ShowPathbar"]
         && [defs objectForKey: @"ShowPathbar"] != nil
         && ![GWViewerChrome showsStatusBar] && [defs objectForKey: @"ShowStatusBar"] != nil,
         "MI-IV-99 under Finder's own names ShowPathbar and ShowStatusBar");
    PASS(counter->posts == 2, "MI-IV-100 every change is announced to the open windows");
    [[NSNotificationCenter defaultCenter] removeObserver: counter];
    [defs removeObjectForKey: @"ShowPathbar"];
    [defs removeObjectForKey: @"ShowStatusBar"];
  END_SET("path bar and status bar are global settings [O:E13]")

  START_SET("records are created only for what was changed [M6]")
    NSString *lcv = folderUnderFixture(e8, @"m_lcv");
    NSString *parentStore = [[lcv stringByDeletingLastPathComponent]
                              stringByAppendingPathComponent: @".DS_Store"];
    NSString *red = folderUnderFixture(nil, @"red");
    NSString *redParent = [[red stringByDeletingLastPathComponent]
                            stringByAppendingPathComponent: @".DS_Store"];
    DSStoreInfo *info;
    DSStore *s;

    info = [DSStoreInfo infoForDirectoryPath: lcv];
    info.windowFrame = NSMakeRect(10, 10, 400, 300);
    info.hasWindowFrame = YES;
    [info saveToParentStore];
    PASS([loadedStore(parentStore) entryForFilename: @"m_lcv" code: @"lsvp"] == nil,
         "MI-IV-108 legacy list records alone do not become an lsvp");
    info.listTextSize = 14;
    info.hasListTextSize = YES;
    [info saveToParentStore];
    PASS([[plistOf(loadedStore(parentStore), @"m_lcv", @"lsvp") objectForKey: @"textSize"] intValue] == 14,
         "MI-IV-109 one that was changed in Workspace does");

    s = [DSStore createStoreAtPath: redParent withEntries: nil];
    [s load];
    [s setEntry: [DSStoreEntry backgroundColorEntryForFile: @"red" red: 65535 green: 0 blue: 0]];
    [s save];
    info = [DSStoreInfo infoForDirectoryPath: red];
    info.windowFrame = NSMakeRect(10, 10, 400, 300);
    info.hasWindowFrame = YES;
    [info saveToParentStore];
    PASS([loadedStore(redParent) entryForFilename: @"red" code: @"icvp"] == nil,
         "MI-IV-110 a BKGD colour Finder ignores does not become an icvp it honours [O:E12]");
  END_SET("records are created only for what was changed [M6]")

  START_SET("stored value types are kept [M6]")
    NSString *dir = folderUnderFixture(nil, @"hand");
    NSString *parentStore = [[dir stringByDeletingLastPathComponent]
                              stringByAppendingPathComponent: @".DS_Store"];
    DSStore *s = [DSStore createStoreAtPath: parentStore withEntries: nil];
    DSStoreInfo *info;
    NSDictionary *lsvp, *icvp;

    [s load];
    [s setEntry: [DSStoreEntry plistEntryForFile: @"hand" code: @"lsvp"
                                      dictionary: @{ @"textSize" : @12, @"iconSize" : @16,
                                                     @"sortColumn" : @"name",
                                                     @"viewOptionsVersion" : @1 }]];
    [s setEntry: [DSStoreEntry plistEntryForFile: @"hand" code: @"icvp"
                                      dictionary: @{ @"iconSize" : @64, @"textSize" : @12,
                                                     @"viewOptionsVersion" : @1 }]];
    [s save];
    info = [DSStoreInfo infoForDirectoryPath: dir];
    info.sortColumn = @"size";
    info.iconSize = 80;
    [info saveToParentStore];
    s = loadedStore(parentStore);
    lsvp = plistOf(s, @"hand", @"lsvp");
    icvp = plistOf(s, @"hand", @"icvp");
    PASS(!isReal([lsvp objectForKey: @"textSize"]) && !isReal([lsvp objectForKey: @"iconSize"])
         && [[lsvp objectForKey: @"sortColumn"] isEqual: @"size"],
         "MI-IV-111 integers not changed by Workspace stay integers");
    PASS([[lsvp objectForKey: @"viewOptionsVersion"] intValue] == 1
         && [[icvp objectForKey: @"viewOptionsVersion"] intValue] == 1,
         "MI-IV-112 viewOptionsVersion stays as stored [O:E6]");
    PASS(isReal([icvp objectForKey: @"iconSize"]) && [[icvp objectForKey: @"iconSize"] intValue] == 80,
         "MI-IV-113 a value Workspace changed is written as Finder writes it");
  END_SET("stored value types are kept [M6]")

  START_SET("vstl only for a chosen view [O:E5]")
    NSString *dir = folderUnderFixture(nil, @"fi");
    GSFileMetadata *md = [[[GSFileMetadata alloc] init] autorelease];
    GWVolumeCache *cache = [[[GWVolumeCache alloc] initWithCacheFilePath:
                               [root stringByAppendingPathComponent: @"cache2.DS_Store"]]
                             autorelease];
    GWViewSettingsManager *sm = [[[GWViewSettingsManager alloc] initWithDirectoryPath: dir
                                                                          volumeCache: cache]
                                  autorelease];
    NSString *parentStore = [[dir stringByDeletingLastPathComponent]
                              stringByAppendingPathComponent: @".DS_Store"];
    DSStore *own;
    DSStoreInfo *info;

    [md setWindowBoundsForDirectory: NSMakeRect(10, 10, 300, 200)];
    [md writeToFileAtPath: dir error: NULL];
    PASS([[DSStoreInfo infoForDirectoryPath: dir] hasViewStyle] == NO,
         "MI-IV-114 a folder's Finder Info does not make up a view style");

    info = [sm readSettings];
    info.viewStyle = DSStoreViewStyleList;
    info.hasViewStyle = YES;
    [sm writeSettings: info];
    own = [DSStore createStoreAtPath: [dir stringByAppendingPathComponent: @".DS_Store"]
                         withEntries: nil];
    [own load];
    [own setEntry: [DSStoreEntry viewStyleEntryForFile: @"." style: @"Nlsv"]];
    [own save];
    [cache writeInfo: info forDirectoryPath: dir];
    [sm removeViewStyle];
    PASS([loadedStore(parentStore) entryForFilename: @"fi" code: @"vstl"] == nil
         && [loadedStore([dir stringByAppendingPathComponent: @".DS_Store"])
              entryForFilename: @"." code: @"vstl"] == nil
         && [[sm readSettings] hasViewStyle] == NO,
         "MI-IV-115 unticking Always open in removes it from the parent, own store and cache");
  END_SET("vstl only for a chosen view [O:E5]")

  START_SET("where a folder's records live [O:E14]")
    PASS([DSStoreInfo parentStorePathForDirectory: @"/"] == nil
         && [DSStoreInfo parentStorePathForDirectory: NSHomeDirectory()] == nil,
         "MI-IV-79 the root and the home folder keep \".\" in their own store");
    {
      /* A mount point on every system: /proc is not mounted on the BSDs,
       * /dev is part of / on OpenBSD. */
      NSArray *candidates = [NSArray arrayWithObjects: @"/proc", @"/dev", @"/sys",
                                     @"/tmp", @"/run", @"/dev/shm", nil];
      NSString *mount = nil;
      NSString *c;
      NSEnumerator *e = [candidates objectEnumerator];
      struct stat own, up;

      while (mount == nil && (c = [e nextObject]) != nil)
        if (stat([c fileSystemRepresentation], &own) == 0
            && stat([[c stringByDeletingLastPathComponent] fileSystemRepresentation], &up) == 0
            && own.st_dev != up.st_dev)
          mount = c;
      if (mount == nil)
        NSLog(@"none of %@ is a mount point here; MI-IV-80 has no volume root to check",
              candidates);
      else
        PASS([DSStoreInfo parentStorePathForDirectory: mount] == nil,
             "MI-IV-80 so does the root of any other volume (%s)", [mount UTF8String]);
    }
    PASS([[DSStoreInfo parentStorePathForDirectory: [root stringByAppendingPathComponent: @"x"]]
           isEqual: [root stringByAppendingPathComponent: @".DS_Store"]],
         "MI-IV-81 any other folder in its parent's");
  END_SET("where a folder's records live [O:E14]")

  START_SET("scroll position and background picture in icvp [O:E11, O:E12]")
    NSString *dir = folderUnderFixture(nil, @"w3");
    DSStoreInfo *w = [[[DSStoreInfo alloc] initWithDirectoryPath: dir] autorelease];
    NSData *alias = [NSData dataWithBytes: "alias-bytes" length: 11];
    DSStoreInfo *back;
    NSDictionary *icvp;

    w.scrollPosition = NSMakePoint(10, 240);
    w.hasScrollPosition = YES;
    w.backgroundType = DSStoreBackgroundPicture;
    w.backgroundImagePath = @"/x/bg.png";
    w.backgroundImageAlias = alias;
    [w saveToParentStore];
    icvp = plistOf(loadedStore([[dir stringByDeletingLastPathComponent]
                                 stringByAppendingPathComponent: @".DS_Store"]), @"w3", @"icvp");
    PASS(isReal([icvp objectForKey: @"scrollPositionY"])
         && [[icvp objectForKey: @"scrollPositionY"] intValue] == 240,
         "MI-IV-82 scrollPositionX/Y are reals");
    PASS([[icvp objectForKey: @"backgroundType"] intValue] == 2
         && [[icvp objectForKey: @"backgroundImageAlias"] isEqual: alias],
         "MI-IV-83 a picture is backgroundType 2 with its alias record");
    back = [DSStoreInfo infoForDirectoryPath: dir];
    PASS(back.hasScrollPosition && back.scrollPosition.y == 240
         && [back.backgroundImageAlias isEqual: alias],
         "MI-IV-84 and both are read back");
  END_SET("scroll position and background picture in icvp [O:E11, O:E12]")

  [fm removeFileAtPath: root handler: nil];
  [arp release];
  return 0;
}
