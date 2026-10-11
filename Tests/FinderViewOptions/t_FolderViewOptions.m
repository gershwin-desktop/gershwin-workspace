/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 */

/* Finder's per-folder icon and list options (from the stores the Mac wrote,
 * Tests/GWMetadata/interop/fixtures/finder106) moved onto real FSNIconsView
 * and FSNListView objects and back by GWFolderViewOptions.  Needs a
 * display. */

#import <AppKit/AppKit.h>
#import "Testing.h"
#import "DSStore.h"
#import "DSStoreInfo.h"
#import "GWFolderViewOptions.h"
#import "FSNIconsView.h"
#import "FSNListView.h"
#import "FSNode.h"
#import "FSNAlias.h"
#include <unistd.h>

/* The stores Finder 10.6.8 wrote, kept with the Scout's evidence. */
static NSString *const GWFinderFixtures = @"../GWMetadata/interop/fixtures/finder106";

static NSString *root;
static NSFileManager *fm;
static DSStore *e8;
static DSStore *e1;

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

static DSStore *
fixture(NSString *name)
{
  DSStore *s = [DSStore storeWithPath:
                  [[[fm currentDirectoryPath] stringByAppendingPathComponent: GWFinderFixtures]
                    stringByAppendingPathComponent: name]];

  return [s load] ? s : nil;
}

/* What DSStoreInfo reads for folder @p name out of a Mac parent store. */
static DSStoreInfo *
finderInfo(DSStore *store, NSString *name)
{
  DSStoreInfo *info = [[[DSStoreInfo alloc] initWithDirectoryPath:
                          [root stringByAppendingPathComponent: name]] autorelease];

  [info takeDirectoryRecordsFromStore: store key: name];
  [info markAsLoaded];
  return info;
}

static FSNIconsView *
iconsView(void)
{
  FSNIconsView *view = [[[FSNIconsView alloc] init] autorelease];
  NSScrollView *scroll = [[NSScrollView alloc] initWithFrame: NSMakeRect(0, 0, 300, 200)];

  [scroll setHasVerticalScroller: YES];
  [scroll setDocumentView: view];
  [view showContentsOfNode: [FSNode nodeWithPath: root]];
  return view;
}

static FSNListViewDataSource *
listDataSource(void)
{
  FSNListView *view = [[FSNListView alloc] initWithFrame: NSMakeRect(0, 0, 800, 300)
                                         dataSourceClass: [FSNListViewDataSource class]];

  [view showContentsOfNode: [FSNode nodeWithPath: root]];
  return (FSNListViewDataSource *)[view dataSource];
}

int
main(void)
{
  NSAutoreleasePool *arp = [NSAutoreleasePool new];
  Class O = [GWFolderViewOptions class];
  BOOL snaps;
  int i;

  START_SET("arrangeBy and Arrange By [F:E8, G: S11]")
    PASS([O arrangementForArrangeBy: @"grid" snapsToGrid: &snaps] == FSNIconsArrangeNone && snaps,
         "MI-IV-47 grid is snap to grid without an arrangement");
    PASS([O arrangementForArrangeBy: @"none" snapsToGrid: &snaps] == FSNIconsArrangeNone && !snaps,
         "MI-IV-48 none is neither");
    PASS([O arrangementForArrangeBy: @"kind" snapsToGrid: &snaps] == FSNIconsArrangeKind && !snaps
         && [O arrangementForArrangeBy: @"dateModified" snapsToGrid: &snaps]
            == FSNIconsArrangeDateModified
         && [O arrangementForArrangeBy: @"label" snapsToGrid: &snaps] == FSNIconsArrangeLabel,
         "MI-IV-49 the other values are arrangements");
    PASS([[O arrangeByForArrangement: FSNIconsArrangeNone snapsToGrid: YES] isEqual: @"grid"]
         && [[O arrangeByForArrangement: FSNIconsArrangeSize snapsToGrid: YES] isEqual: @"size"]
         && [[O arrangeByForArrangement: FSNIconsArrangeNone snapsToGrid: NO] isEqual: @"none"],
         "MI-IV-50 and back; an arrangement wins over snap");
  END_SET("arrangeBy and Arrange By [F:E8, G: S11]")

  START_SET("a background picture as Finder resolves it [O:E12]")
    NSData *alias = [O backgroundImageAliasForPath: @"/srv/pics/bg.png"];
    NSString *bytes = [[[NSString alloc] initWithData: alias
                                             encoding: NSISOLatin1StringEncoding] autorelease];

    PASS(alias != nil && [bytes rangeOfString: @"Macintosh HD:srv:pics:bg.png"].location
                         != NSNotFound,
         "MI-IV-85 the alias carries the HFS path on the root volume [G: volume name]");
    PASS([[[[FSNAlias alloc] initWithData: alias] autorelease] version] == 2,
         "MI-IV-86 and is a version 2 alias record");
  END_SET("a background picture as Finder resolves it [O:E12]")

  if (getenv("DISPLAY") == NULL)
    {
      printf("no DISPLAY, skipping the view tests\n");
      [arp release];
      return 0;
    }
  [NSApplication sharedApplication];

  fm = [NSFileManager defaultManager];
  root = [[NSTemporaryDirectory() stringByAppendingPathComponent:
             [NSString stringWithFormat: @"t_FolderViewOptions-%d", (int)getpid()]] retain];
  [fm createDirectoryAtPath: root withIntermediateDirectories: YES attributes: nil error: NULL];
  for (i = 0; i < 60; i++)
    {
      [[NSData dataWithBytes: "x" length: 1]
        writeToFile: [root stringByAppendingPathComponent:
                             [NSString stringWithFormat: @"f%02d.txt", i]]
         atomically: NO];
    }
  [fm createDirectoryAtPath: [root stringByAppendingPathComponent: @"sub"] attributes: nil];
  e8 = [fixture(@"E8-option-matrix.parent.DS_Store") retain];
  e1 = [fixture(@"E1-parent-icvp-bwsp.DS_Store") retain];

  START_SET("icvp onto an icon view")
    FSNIconsView *v;

    v = iconsView();
    [O applyIconViewOptionsOf: finderInfo(e1, @"eA") toIconsView: v includingScrollPosition: NO];
    PASS([v iconSize] == 96, "MI-IV-51 icon size");
    v = iconsView();
    [O applyIconViewOptionsOf: finderInfo(e8, @"m_ts") toIconsView: v includingScrollPosition: NO];
    PASS([v labelTextSize] == 11, "MI-IV-52 text size");
    v = iconsView();
    [O applyIconViewOptionsOf: finderInfo(e8, @"m_lp") toIconsView: v includingScrollPosition: NO];
    PASS([v iconPosition] == NSImageLeft, "MI-IV-53 label on the right");
    v = iconsView();
    [O applyIconViewOptionsOf: finderInfo(e8, @"m_arr") toIconsView: v includingScrollPosition: NO];
    PASS([v snapsToGrid] && [v arrangement] == FSNIconsArrangeNone, "MI-IV-54 snap to grid");
    v = iconsView();
    [O applyIconViewOptionsOf: finderInfo(e8, @"m_info") toIconsView: v includingScrollPosition: NO];
    PASS([v showsItemInfo], "MI-IV-55 item info");
    v = iconsView();
    [O applyIconViewOptionsOf: finderInfo(e8, @"m_prev") toIconsView: v includingScrollPosition: NO];
    PASS([v showsIconPreview] == NO, "MI-IV-56 icon preview off");
  END_SET("icvp onto an icon view")

  START_SET("text sizes outside Finder's range")
    FSNIconsView *v = iconsView();
    DSStoreInfo *info = finderInfo(e8, @"m_ts");

    info.iconTextSize = 40;
    [O applyIconViewOptionsOf: info toIconsView: v includingScrollPosition: NO];
    PASS([v labelTextSize] == 16, "MI-IV-57 are clamped to 16 points");
  END_SET("text sizes outside Finder's range")

  START_SET("the scroll position only when asked")
    FSNIconsView *v = iconsView();
    DSStoreInfo *info = finderInfo(e8, @"m_ts");

    info.scrollPosition = NSMakePoint(0, 40);
    info.hasScrollPosition = YES;
    [O applyIconViewOptionsOf: info toIconsView: v includingScrollPosition: NO];
    PASS([v scrollPosition].y == 0, "MI-IV-58 not when a window only comes to the front");
    [O applyIconViewOptionsOf: info toIconsView: v includingScrollPosition: YES];
    PASS([v scrollPosition].y == 40, "MI-IV-59 when the folder is opened");
  END_SET("the scroll position only when asked")

  START_SET("an icon view back into icvp")
    FSNIconsView *v = iconsView();
    DSStoreInfo *info = [[[DSStoreInfo alloc] initWithDirectoryPath: root] autorelease];

    [v setIconSize: 64];
    [v setLabelTextSize: 14];
    [v setShowsItemInfo: YES];
    [v setArrangement: FSNIconsArrangeKind];
    [O takeIconViewOptionsOf: v into: info];
    PASS(info.iconSize == 64 && info.iconTextSize == 14 && info.showItemInfo
         && info.hasShowIconPreview && info.showIconPreview,
         "MI-IV-60 every option the view has");
    PASS([info.arrangeBy isEqual: @"kind"], "MI-IV-61 the arrangement as arrangeBy");

    info.arrangeBy = @"dateAdded";
    [v setArrangement: FSNIconsArrangeNone];
    [O takeIconViewOptionsOf: v into: info];
    PASS([info.arrangeBy isEqual: @"dateAdded"],
         "MI-IV-62 a value the view has no arrangement for is kept while untouched");
    [v setSnapsToGrid: YES];
    [O takeIconViewOptionsOf: v into: info];
    PASS([info.arrangeBy isEqual: @"grid"], "MI-IV-63 and replaced once the user changes it");
  END_SET("an icon view back into icvp")

  START_SET("lsvp onto a list [F:E8]")
    FSNListViewDataSource *ds;
    PostCounter *counter = [[PostCounter new] autorelease];
    NSArray *order = @[ @"name", @"dateModified", @"size", @"kind" ];

    [[NSNotificationCenter defaultCenter] addObserver: counter
                                             selector: @selector(changed:)
                                                 name: FSNListViewOptionsDidChangeNotification
                                               object: nil];
    ds = listDataSource();
    [O applyListViewOptionsOf: finderInfo(e8, @"m_lsort") toDataSource: ds];
    PASS([[ds columnOrder] isEqual: order], "MI-IV-64 the visible columns in Finder's order");
    PASS([[ds sortColumnId] isEqual: @"size"] && [ds sortAscending] == NO,
         "MI-IV-65 sort column and direction");
    PASS((int)[ds columnWidthForColumnId: @"kind"] == 115, "MI-IV-66 widths");
    PASS([ds usesRelativeDates], "MI-IV-67 relative dates");
    PASS(counter->posts == 0, "MI-IV-68 applying posts no user change");

    ds = listDataSource();
    [O applyListViewOptionsOf: finderInfo(e8, @"m_lts") toDataSource: ds];
    PASS((int)[ds textSize] == 10, "MI-IV-69 text size");
    ds = listDataSource();
    [O applyListViewOptionsOf: finderInfo(e8, @"m_lis") toDataSource: ds];
    PASS([ds listIconSize] == 32, "MI-IV-70 icon size");
    ds = listDataSource();
    [O applyListViewOptionsOf: finderInfo(e8, @"m_lrd") toDataSource: ds];
    PASS([ds usesRelativeDates] == NO, "MI-IV-71 relative dates off");
    ds = listDataSource();
    [O applyListViewOptionsOf: finderInfo(e8, @"m_lcs") toDataSource: ds];
    PASS([ds calculatesAllSizes], "MI-IV-72 calculate all sizes");
    [ds setCalculatesAllSizes: NO];
    ds = listDataSource();
    [O applyListViewOptionsOf: finderInfo(e8, @"m_lcv") toDataSource: ds];
    PASS([ds isColumnVisible: @"comments"], "MI-IV-73 the legacy lsvo too [F:E8 m_lcv]");
    [[NSNotificationCenter defaultCenter] removeObserver: counter];
  END_SET("lsvp onto a list [F:E8]")

  START_SET("a list back into lsvp")
    FSNListViewDataSource *ds = listDataSource();
    DSStoreInfo *info = finderInfo(e8, @"m_lsort");
    DSStoreInfo *back;
    NSArray *order = @[ @"name", @"kind", @"size" ];

    [O applyListViewOptionsOf: info toDataSource: ds];
    [ds setColumn: @"dateModified" visible: NO];
    [ds setColumnOrder: @[ @"name", @"kind", @"size" ]];
    [ds setSortColumnId: @"kind" ascending: NO];
    [O takeListViewOptionsOf: ds into: info];
    PASS([[info listColumnOrder] isEqual: order], "MI-IV-74 visibility and order");
    PASS([info.sortColumn isEqual: @"kind"] && info.sortAscending == NO,
         "MI-IV-75 sort column and its direction");
    PASS([[[info.listColumns objectForKey: @"comments"] objectForKey: @"index"] intValue] == 7,
         "MI-IV-76 a hidden column keeps its place");
    PASS([[[info.listColumns objectForKey: @"size"] objectForKey: @"ascending"] boolValue] == NO,
         "MI-IV-77 the other columns keep their own direction");

    back = [[[DSStoreInfo alloc] initWithDirectoryPath: root] autorelease];
    [O takeListColumnWidthsOf: ds into: back];
    PASS([back hasListViewOptions] == NO,
         "MI-IV-78 a width alone does not create list options");
  END_SET("a list back into lsvp")

  [fm removeFileAtPath: root handler: nil];
  [arp release];
  return 0;
}
