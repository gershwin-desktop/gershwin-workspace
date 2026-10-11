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
#import "FSNode.h"
#include <unistd.h>

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

  [fm removeFileAtPath: root handler: nil];
  [arp release];
  return 0;
}
