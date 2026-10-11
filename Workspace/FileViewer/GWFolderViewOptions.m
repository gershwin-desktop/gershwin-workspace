/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 */

#import "GWFolderViewOptions.h"
#import "DSStoreInfo.h"
#import "FSNListView.h"
#import "FSNAlias.h"
#import "GWVolumeID.h"

/* icvp arrangeBy values.  "none" and "grid" are what 10.6 wrote [F:E8];
 * the others are the names of Finder's Arrange By choices [G: OPEN S11]. */
static NSString *const GWArrangeByNone = @"none";
static NSString *const GWArrangeByGrid = @"grid";

static NSDictionary *arrangementsByName(void)
{
  static NSDictionary *map = nil;

  if (map == nil)
    {
      map = [[NSDictionary alloc] initWithObjectsAndKeys:
        [NSNumber numberWithInteger: FSNIconsArrangeName], @"name",
        [NSNumber numberWithInteger: FSNIconsArrangeKind], @"kind",
        [NSNumber numberWithInteger: FSNIconsArrangeDateModified], @"dateModified",
        [NSNumber numberWithInteger: FSNIconsArrangeDateCreated], @"dateCreated",
        [NSNumber numberWithInteger: FSNIconsArrangeSize], @"size",
        [NSNumber numberWithInteger: FSNIconsArrangeLabel], @"label",
        nil];
    }
  return map;
}

@implementation GWFolderViewOptions

+ (FSNIconsArrangement)arrangementForArrangeBy:(NSString *)arrangeBy
                                   snapsToGrid:(BOOL *)snaps
{
  NSNumber *arrangement = [arrangementsByName() objectForKey: arrangeBy];

  *snaps = [arrangeBy isEqualToString: GWArrangeByGrid];
  return arrangement ? (FSNIconsArrangement)[arrangement integerValue] : FSNIconsArrangeNone;
}

+ (NSString *)arrangeByForArrangement:(FSNIconsArrangement)arrangement
                          snapsToGrid:(BOOL)snaps
{
  NSDictionary *map = arrangementsByName();

  for (NSString *name in map)
    {
      if ([[map objectForKey: name] integerValue] == arrangement)
        return name;
    }
  return snaps ? GWArrangeByGrid : GWArrangeByNone;
}

+ (void)applyIconViewOptionsOf:(DSStoreInfo *)info
                   toIconsView:(FSNIconsView *)view
       includingScrollPosition:(BOOL)scroll
{
  if (info == nil || view == nil)
    return;

  if ([info hasIconSize] && [info iconSize] > 0)
    [view setIconSize: [info iconSize]];
  if ([info hasLabelPosition])
    [view setIconPosition: ([info labelPosition] == DSStoreLabelPositionBottom)
                            ? NSImageAbove : NSImageLeft];
  if ([info hasIconTextSize])
    [view setLabelTextSize: [FSNIconsView clampedLabelTextSize: (int)[info iconTextSize]]];
  if ([info hasShowItemInfo])
    [view setShowsItemInfo: [info showItemInfo]];
  if ([info hasShowIconPreview])
    [view setShowsIconPreview: [info showIconPreview]];
  if ([info arrangeBy])
    {
      BOOL snaps;
      FSNIconsArrangement arrangement =
        [self arrangementForArrangeBy: [info arrangeBy] snapsToGrid: &snaps];

      /* Snap first: arranging lays the icons out, snapping only matters
       * for the positions an unarranged view keeps. */
      [view setSnapsToGrid: snaps];
      [view setArrangement: arrangement];
    }
  if (scroll && [info hasScrollPosition])
    [view setScrollPosition: [info scrollPosition]];
}

+ (void)takeIconViewOptionsOf:(FSNIconsView *)view into:(DSStoreInfo *)info
{
  BOOL storedSnaps;
  FSNIconsArrangement stored;

  if (info == nil || view == nil)
    return;

  [info setIconSize: [view iconSize]];
  [info setHasIconSize: YES];
  [info setLabelPosition: ([view iconPosition] == NSImageLeft)
                           ? DSStoreLabelPositionRight : DSStoreLabelPositionBottom];
  [info setHasLabelPosition: YES];
  [info setIconTextSize: [view labelTextSize]];
  [info setHasIconTextSize: YES];
  [info setShowItemInfo: [view showsItemInfo]];
  [info setHasShowItemInfo: YES];
  [info setShowIconPreview: [view showsIconPreview]];
  [info setHasShowIconPreview: YES];
  [info setScrollPosition: [view scrollPosition]];
  [info setHasScrollPosition: YES];

  /* A value the view cannot show (a newer Finder's "dateAdded") came in as
   * no arrangement; writing "none" back would lose it while the user did
   * not touch the arrangement at all. */
  stored = [self arrangementForArrangeBy: [info arrangeBy] snapsToGrid: &storedSnaps];
  if ([info arrangeBy] == nil
      || stored != [view arrangement] || storedSnaps != [view snapsToGrid])
    {
      [info setArrangeBy: [self arrangeByForArrangement: [view arrangement]
                                            snapsToGrid: [view snapsToGrid]]];
    }
}

+ (void)applyListViewOptionsOf:(DSStoreInfo *)info
                  toDataSource:(FSNListViewDataSource *)dataSource
{
  NSDictionary *columns;

  if (info == nil || dataSource == nil || [info hasListViewOptions] == NO)
    return;

  columns = [info listColumns];
  for (NSString *columnId in columns)
    {
      id visible = [[columns objectForKey: columnId] objectForKey: @"visible"];

      if (visible && [FSNListViewDataSource tableIdentifierForColumnId: columnId])
        [dataSource setColumn: columnId visible: [visible boolValue]];
    }
  if ([columns count] > 0)
    [dataSource setColumnOrder: [info listColumnOrder]];

  if ([info hasSortColumn] && [info sortColumn])
    [dataSource setSortColumnId: [info sortColumn] ascending: [info sortAscending]];

  for (NSString *columnId in columns)
    {
      id width = [[columns objectForKey: columnId] objectForKey: @"width"];

      if ([width floatValue] > 0
          && [FSNListViewDataSource tableIdentifierForColumnId: columnId])
        [dataSource setColumnWidth: [width floatValue] forColumnId: columnId];
    }

  if ([info hasListTextSize])
    [dataSource setTextSize: [info listTextSize]];
  if ([info hasListIconSize])
    [dataSource setListIconSize: [info listIconSize]];
  if ([info hasUseRelativeDates])
    [dataSource setUsesRelativeDates: [info useRelativeDates]];
  if ([info hasCalculateAllSizes])
    [dataSource setCalculatesAllSizes: [info calculateAllSizes]];
}

/* Finder's column dictionaries with the view's widths (and, when asked,
 * visibility and order) laid over them. */
+ (NSDictionary *)columnsOf:(FSNListViewDataSource *)dataSource
                 overColumns:(NSDictionary *)stored
                 widthsOnly:(BOOL)widthsOnly
{
  NSMutableDictionary *columns = [NSMutableDictionary dictionary];
  NSArray *order = [dataSource columnOrder];

  for (NSString *columnId in [FSNListViewDataSource finderColumnIds])
    {
      NSMutableDictionary *col =
        [NSMutableDictionary dictionaryWithDictionary: [stored objectForKey: columnId]];
      CGFloat width = [dataSource columnWidthForColumnId: columnId];
      NSUInteger index = [order indexOfObject: columnId];

      if (width > 0)
        [col setObject: [NSNumber numberWithInt: (int)width] forKey: @"width"];
      if (widthsOnly == NO)
        {
          [col setObject: [NSNumber numberWithBool: [dataSource isColumnVisible: columnId]]
                  forKey: @"visible"];
          /* A hidden column keeps the place it had, as Finder's do [F:E8]. */
          if (index != NSNotFound)
            [col setObject: [NSNumber numberWithInt: (int)index] forKey: @"index"];
        }
      if ([col count] > 0)
        [columns setObject: col forKey: columnId];
    }
  return columns;
}

+ (void)takeListViewOptionsOf:(FSNListViewDataSource *)dataSource
                         into:(DSStoreInfo *)info
{
  if (info == nil || dataSource == nil)
    return;

  [info setListColumns: [self columnsOf: dataSource
                            overColumns: [info listColumns]
                             widthsOnly: NO]];
  if ([dataSource sortColumnId])
    {
      [info setSortColumn: [dataSource sortColumnId]];
      [info setHasSortColumn: YES];
      [info setSortAscending: [dataSource sortAscending]];
    }
  if ([dataSource textSize] > 0)
    {
      [info setListTextSize: (int)[dataSource textSize]];
      [info setHasListTextSize: YES];
    }
  [info setListIconSize: (int)[dataSource listIconSize]];
  [info setHasListIconSize: YES];
  [info setUseRelativeDates: [dataSource usesRelativeDates]];
  [info setHasUseRelativeDates: YES];
  [info setCalculateAllSizes: [dataSource calculatesAllSizes]];
  [info setHasCalculateAllSizes: YES];
}

+ (void)takeListColumnWidthsOf:(FSNListViewDataSource *)dataSource
                          into:(DSStoreInfo *)info
{
  if (info == nil || dataSource == nil || [[info listColumns] count] == 0)
    return;

  [info setListColumns: [self columnsOf: dataSource
                            overColumns: [info listColumns]
                             widthsOnly: YES]];
}

+ (NSData *)backgroundImageAliasForPath:(NSString *)imagePath
{
  NSString *mountPoint = [GWVolumeID mountPointForPath: imagePath];
  NSString *volumeName;
  NSString *inVolume;

  if (mountPoint == nil)
    return nil;

  if ([mountPoint isEqualToString: @"/"])
    {
      volumeName = @"Macintosh HD";
      inVolume = imagePath;
    }
  else if ([imagePath hasPrefix: [mountPoint stringByAppendingString: @"/"]])
    {
      volumeName = [mountPoint lastPathComponent];
      inVolume = [@"/" stringByAppendingString:
                         [imagePath substringFromIndex: [mountPoint length] + 1]];
    }
  else
    {
      return nil;
    }
  return [[FSNAlias aliasWithTargetPath: inVolume volumeName: volumeName] aliasData];
}

@end
