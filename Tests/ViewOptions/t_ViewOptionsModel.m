/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 */

/* What the View Options panel holds (GWViewOptionsModel) moved onto real
 * icon and list views and into the records a folder keeps.  Needs a
 * display for the views. */

#import <AppKit/AppKit.h>
#import "Testing.h"
#import "DSStoreInfo.h"
#import "GWViewOptionsModel.h"
#import "FSNIconsView.h"
#import "FSNListView.h"
#import "FSNColumnViewOptions.h"
#import "FSNode.h"
#import "FSNAlias.h"
#import "GWFolderViewOptions.h"
#include <unistd.h>

/* What GWSpatialIconsView is to the picture: a flipped icon view. */
@interface FlippedIconsView : FSNIconsView
@end
@implementation FlippedIconsView
- (BOOL)isFlipped { return YES; }
@end

static NSString *root;

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
  NSFileManager *fm;
  GWViewOptionsModel *m;
  DSStoreInfo *info;

  if (getenv("DISPLAY") == NULL)
    {
      printf("no DISPLAY, skipping the view tests\n");
      [arp release];
      return 0;
    }
  [NSApplication sharedApplication];
  fm = [NSFileManager defaultManager];
  root = [[NSTemporaryDirectory() stringByAppendingPathComponent:
             [NSString stringWithFormat: @"t_ViewOptionsModel-%d", (int)getpid()]] retain];
  [fm createDirectoryAtPath: root withIntermediateDirectories: YES attributes: nil error: NULL];
  [[NSData dataWithBytes: "x" length: 1] writeToFile:
    [root stringByAppendingPathComponent: @"a.txt"] atomically: NO];

  START_SET("limits Finder offers")
    m = [[[GWViewOptionsModel alloc] init] autorelease];
    [m setIconSize: 4];
    PASS([m iconSize] == 16, "MI-VO-1 icon size has a floor of 16");
    [m setIconSize: 900];
    PASS([m iconSize] == 512, "MI-VO-2 icon size has a ceiling of 512");
    [m setTextSize: 3];
    PASS([m textSize] == 10, "MI-VO-3 text size has a floor of 10");
    [m setTextSize: 40];
    PASS([m textSize] == 16, "MI-VO-4 text size has a ceiling of 16");
    [m setListTextSize: 99];
    PASS([m listTextSize] == 16, "MI-VO-5 list text size has a ceiling of 16");
    [m setGridSpacing: 1];
    PASS([m gridSpacing] == 54, "MI-VO-6 grid spacing has a floor of 54");
    [m setGridSpacing: 500];
    PASS([m gridSpacing] == 100, "MI-VO-7 grid spacing has a ceiling of 100");
    PASS([[GWViewOptionsModel arrangeByValues] count] == 8
         && [[[GWViewOptionsModel arrangeByValues] objectAtIndex: 0] isEqual: @"none"],
         "MI-VO-8 eight arrangements, none first");
    PASS([[GWViewOptionsModel optionalListColumnIds] containsObject: @"name"] == NO
         && [[GWViewOptionsModel optionalListColumnIds] containsObject: @"size"],
         "MI-VO-9 the name column is not optional");
  END_SET("limits Finder offers")

  START_SET("panel state <-> records")
    m = [[[GWViewOptionsModel alloc] init] autorelease];
    [m setIconSize: 96];
    [m setGridSpacing: 80];
    [m setTextSize: 13];
    [m setLabelOnRight: YES];
    [m setShowsItemInfo: YES];
    [m setShowsIconPreview: NO];
    [m setArrangeBy: @"dateModified"];
    [m setBackgroundType: DSStoreBackgroundColor];
    [m setBackgroundColor: [NSColor colorWithCalibratedRed: 0.5 green: 0.25 blue: 0.75 alpha: 1]];
    [m setListTextSize: 11];
    [m setListLargeIcons: YES];
    [m setUsesRelativeDates: YES];
    [m setCalculatesAllSizes: YES];
    [m setAlwaysOpen: YES];
    [m setAlwaysOpenStyle: DSStoreViewStyleList];

    info = [[[DSStoreInfo alloc] initWithDirectoryPath: root] autorelease];
    [m putIntoInfo: info];
    PASS([info iconSize] == 96 && [info hasIconSize], "MI-VO-10 icon size into icvp");
    PASS([info gridSpacing] == 80 && [info hasGridSpacing], "MI-VO-11 grid spacing into icvp");
    PASS([info iconTextSize] == 13, "MI-VO-12 text size into icvp");
    PASS([info labelPosition] == DSStoreLabelPositionRight, "MI-VO-13 label right");
    PASS([info showItemInfo] && [info hasShowItemInfo] && [info showIconPreview] == NO
         && [info hasShowIconPreview], "MI-VO-14 item info and icon preview into icvp");
    PASS([[info arrangeBy] isEqual: @"dateModified"], "MI-VO-15 arrange by into icvp");
    PASS([info backgroundType] == DSStoreBackgroundColor, "MI-VO-16 background colour into icvp");
    PASS([info listTextSize] == 11 && [info listIconSize] == 32
         && [info useRelativeDates] && [info calculateAllSizes],
         "MI-VO-17 list scalars into lsvp [F:E5: small/large -> 16/32]");
    PASS([info hasViewStyle] && [info viewStyle] == DSStoreViewStyleList,
         "MI-VO-18 always open in list view is vstl [O:E5]");

    {
      GWViewOptionsModel *m2 = [[[GWViewOptionsModel alloc] init] autorelease];

      [m2 takeFromInfo: info];
      PASS([m2 iconSize] == 96 && [m2 gridSpacing] == 80 && [m2 textSize] == 13
           && [m2 labelOnRight] && [m2 showsItemInfo] && [m2 showsIconPreview] == NO
           && [[m2 arrangeBy] isEqual: @"dateModified"]
           && [m2 backgroundType] == DSStoreBackgroundColor,
           "MI-VO-19 icvp back into the panel state");
      PASS([m2 listTextSize] == 11 && [m2 listLargeIcons] && [m2 usesRelativeDates]
           && [m2 calculatesAllSizes] && [m2 alwaysOpen]
           && [m2 alwaysOpenStyle] == DSStoreViewStyleList,
           "MI-VO-20 lsvp and vstl back into the panel state");
    }

    info = [[[DSStoreInfo alloc] initWithDirectoryPath: root] autorelease];
    [m putIntoInfo: info forListView: NO];
    PASS([info hasIconSize] && [info hasListTextSize] == NO && [info hasUseRelativeDates] == NO,
         "MI-VO-29 an icon view's panel writes no list options");
    info = [[[DSStoreInfo alloc] initWithDirectoryPath: root] autorelease];
    [m putIntoInfo: info forListView: YES];
    PASS([info hasIconSize] == NO && [info hasListTextSize] && [info hasViewStyle],
         "MI-VO-30 a list view's panel writes no icon options");

    [m setAlwaysOpen: NO];
    info = [[[DSStoreInfo alloc] initWithDirectoryPath: root] autorelease];
    [m putIntoInfo: info];
    PASS([info hasViewStyle] == NO,
         "MI-VO-21 without always open no view style is stored [O:E5]");
  END_SET("panel state <-> records")

  START_SET("panel state <-> views")
    FSNIconsView *v = iconsView();
    FSNListViewDataSource *ds = listDataSource();
    GWViewOptionsModel *seen = [[[GWViewOptionsModel alloc] init] autorelease];
    NSSet *sizeKind;

    m = [[[GWViewOptionsModel alloc] init] autorelease];
    [m setIconSize: 128];
    [m setTextSize: 14];
    [m setLabelOnRight: YES];
    [m setShowsItemInfo: YES];
    [m setShowsIconPreview: NO];
    [m setArrangeBy: @"name"];
    [m applyToIconsView: v];
    PASS([v iconSize] == 128 && [v labelTextSize] == 14 && [v iconPosition] == NSImageLeft
         && [v showsItemInfo] && [v showsIconPreview] == NO
         && [v arrangement] == FSNIconsArrangeName,
         "MI-VO-22 the panel state onto an icon view");

    [m setArrangeBy: @"grid"];
    [m applyToIconsView: v];
    PASS([v snapsToGrid] && [v arrangement] == FSNIconsArrangeNone,
         "MI-VO-23 grid is snap to grid without arrangement");

    [seen takeFromIconsView: v];
    PASS([seen iconSize] == 128 && [seen textSize] == 14 && [seen labelOnRight]
         && [seen showsItemInfo] && [[seen arrangeBy] isEqual: @"grid"],
         "MI-VO-24 an icon view back into the panel state");

    [m setBackgroundType: DSStoreBackgroundColor];
    [m setBackgroundColor: [NSColor redColor]];
    [m applyToIconsView: v];
    PASS([[v backgroundColor] isEqual: [NSColor redColor]] && [v backgroundImage] == nil,
         "MI-VO-25 a background colour onto the icon view");

    [m setListTextSize: 14];
    [m setListLargeIcons: YES];
    [m setUsesRelativeDates: YES];
    [m setCalculatesAllSizes: NO];
    [m setVisibleColumns: [NSSet setWithObjects: @"size", @"kind", nil]];
    [m applyToListDataSource: ds];
    PASS([ds textSize] == 14 && [ds listIconSize] == 32 && [ds usesRelativeDates]
         && [ds calculatesAllSizes] == NO,
         "MI-VO-26 the list scalars onto a list view");
    PASS([ds isColumnVisible: @"size"] && [ds isColumnVisible: @"kind"]
         && [ds isColumnVisible: @"comments"] == NO && [ds isColumnVisible: @"name"],
         "MI-VO-27 exactly the ticked columns are shown, name always");

    seen = [[[GWViewOptionsModel alloc] init] autorelease];
    [seen takeFromListDataSource: ds];
    sizeKind = [NSSet setWithObjects: @"size", @"kind", nil];
    PASS([seen listTextSize] == 14 && [seen listLargeIcons] && [seen usesRelativeDates]
         && [[seen visibleColumns] isEqual: sizeKind],
         "MI-VO-28 a list view back into the panel state");
  END_SET("panel state <-> views")

  START_SET("column view options are global")
    FSNColumnViewOptions *o = [FSNColumnViewOptions sharedOptions];
    GWViewOptionsModel *seen = [[[GWViewOptionsModel alloc] init] autorelease];

    m = [[[GWViewOptionsModel alloc] init] autorelease];
    [m setColumnTextSize: 40];
    PASS([m columnTextSize] == 16, "MI-VO-31 column text size has a ceiling of 16");
    [m setColumnTextSize: 14];
    [m setColumnShowsIcons: NO];
    [m setColumnShowsIconPreview: NO];
    [m setColumnShowsPreviewColumn: NO];
    [m setColumnArrangement: FSNIconsArrangeKind];
    [m applyToColumnViewOptions: o];
    PASS([o textSize] == 14 && [o showsIcons] == NO && [o showsIconPreview] == NO
         && [o showsPreviewColumn] == NO && [o arrangement] == FSNIconsArrangeKind,
         "MI-VO-32 the panel state onto the shared column options [O:E30]");

    [seen takeFromColumnViewOptions: o];
    PASS([seen columnTextSize] == 14 && [seen columnShowsIcons] == NO
         && [seen columnShowsPreviewColumn] == NO
         && [seen columnArrangement] == FSNIconsArrangeKind,
         "MI-VO-33 the shared column options back into the panel state");

    [m setColumnShowsIcons: YES];
    [m setColumnShowsIconPreview: YES];
    [m setColumnShowsPreviewColumn: YES];
    [m setColumnArrangement: FSNIconsArrangeName];
    [m applyToColumnViewOptions: o];

    [m setAlwaysOpen: YES];
    [m setAlwaysOpenStyle: DSStoreViewStyleColumn];
    info = [[[DSStoreInfo alloc] initWithDirectoryPath: root] autorelease];
    [m putIntoInfo: info forViewKind: GWViewOptionsColumnView];
    PASS([info hasViewStyle] && [info viewStyle] == DSStoreViewStyleColumn
         && [info hasIconSize] == NO && [info hasListTextSize] == NO,
         "MI-VO-34 a column view panel stores only vstl clmv, and only with Always open in [O:E30]");
    [m setAlwaysOpen: NO];
    info = [[[DSStoreInfo alloc] initWithDirectoryPath: root] autorelease];
    [m putIntoInfo: info forViewKind: GWViewOptionsColumnView];
    PASS([info hasViewStyle] == NO, "MI-VO-35 no vstl without Always open in");
  END_SET("column view options are global")

  START_SET("a background picture [O:E12]")
    NSString *pic = [root stringByAppendingPathComponent: @"bg.png"];
    NSBitmapImageRep *rep = [[[NSBitmapImageRep alloc]
      initWithBitmapDataPlanes: NULL pixelsWide: 50 pixelsHigh: 40 bitsPerSample: 8
               samplesPerPixel: 4 hasAlpha: YES isPlanar: NO
                colorSpaceName: NSCalibratedRGBColorSpace bytesPerRow: 0 bitsPerPixel: 0] autorelease];
    GWViewOptionsModel *seen = [[[GWViewOptionsModel alloc] init] autorelease];
    FSNIconsView *v = iconsView();
    NSData *alias;
    FSNAlias *parsed;
    NSRect r;

    memset ([rep bitmapData], 0x80, [rep bytesPerRow] * 40);
    [[rep representationUsingType: NSPNGFileType properties: nil] writeToFile: pic atomically: NO];

    m = [[[GWViewOptionsModel alloc] init] autorelease];
    [m setBackgroundType: DSStoreBackgroundPicture];
    [m setBackgroundImagePath: pic];
    info = [[[DSStoreInfo alloc] initWithDirectoryPath: root] autorelease];
    [m putIntoInfo: info forListView: NO];
    alias = [info backgroundImageAlias];
    parsed = alias ? [[[FSNAlias alloc] initWithData: alias] autorelease] : nil;
    PASS([info backgroundType] == DSStoreBackgroundPicture && parsed != nil
         && [[parsed targetName] isEqual: @"bg.png"] && [[parsed volumeName] length] > 0,
         "MI-VO-36 a picture is icvp type 2 with the alias record of the image");

    [seen takeFromInfo: info];
    PASS([[seen backgroundImagePath] isEqual: pic],
         "MI-VO-37 a folder that has only the alias record gets the image path from it");

    [seen applyToIconsView: v];
    PASS([v backgroundImage] != nil && [[v backgroundImage] size].width == 50,
         "MI-VO-38 the picture onto the icon view");
    r = [v backgroundImageRect];
    PASS (r.size.width == 50 && r.size.height == 40 && r.origin.x == [v bounds].origin.x
          && NSMaxY (r) == NSMaxY ([v bounds]),
          "MI-VO-39 the picture is drawn at its natural size from the top left [G: Finder 10.6]");

    {
      FlippedIconsView *flipped = [[[FlippedIconsView alloc] initWithFrame: NSMakeRect (0, 0, 300, 200)] autorelease];

      [flipped setBackgroundImage: [v backgroundImage]];
      r = [flipped backgroundImageRect];
      PASS (r.size.width == 50 && r.origin.x == 0 && r.origin.y == 0,
            "MI-VO-42 a flipped (spatial) icon view draws the same picture from its top, by the same code");
    }

    seen = [[[GWViewOptionsModel alloc] init] autorelease];
    info = [[[DSStoreInfo alloc] initWithDirectoryPath: root] autorelease];
    [info setBackgroundType: DSStoreBackgroundPicture];
    [info setBackgroundImageAlias: [GWFolderViewOptions backgroundImageAliasForPath: @"/nowhere/at/all.png"]];
    [seen takeFromInfo: info];
    info = [[[DSStoreInfo alloc] initWithDirectoryPath: root] autorelease];
    [seen putIntoInfo: info forListView: NO];
    PASS([seen backgroundImagePath] == nil && [info backgroundType] == DSStoreBackgroundPicture
         && [info backgroundImageAlias] != nil,
         "MI-VO-40 a picture that is not here is kept as the Mac wrote it, not dropped");

    [seen setBackgroundImagePath: pic];
    info = [[[DSStoreInfo alloc] initWithDirectoryPath: root] autorelease];
    [seen putIntoInfo: info forListView: NO];
    PASS([[[[FSNAlias alloc] initWithData: [info backgroundImageAlias]] autorelease] targetName]
         && [[[[[FSNAlias alloc] initWithData: [info backgroundImageAlias]] autorelease]
               targetName] isEqual: @"bg.png"],
         "MI-VO-41 choosing another picture replaces the kept alias");
  END_SET("a background picture [O:E12]")

  [fm removeFileAtPath: root handler: nil];
  [arp release];
  return 0;
}
