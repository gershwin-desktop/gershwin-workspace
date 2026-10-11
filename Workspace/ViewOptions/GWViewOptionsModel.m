/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 */

#import "GWViewOptionsModel.h"
#import "DSStoreInfo.h"
#import "GWFolderViewOptions.h"
#import "FSNIconsView.h"
#import "FSNListView.h"
#import "FSNColumnViewOptions.h"

static int
clampInt(int value, int low, int high)
{
  return value < low ? low : (value > high ? high : value);
}

@interface GWViewOptionsModel (Private)
- (void)putIconOptionsIntoInfo:(DSStoreInfo *)info;
- (void)putListOptionsIntoInfo:(DSStoreInfo *)info;
- (void)putViewStyleIntoInfo:(DSStoreInfo *)info;
@end

@implementation GWViewOptionsModel

+ (NSArray *)arrangeByValues
{
  return [NSArray arrayWithObjects: @"none", @"grid", @"name", @"kind",
                  @"dateModified", @"dateCreated", @"size", @"label", nil];
}

+ (NSArray *)optionalListColumnIds
{
  NSMutableArray *ids = [NSMutableArray arrayWithArray:
                           [FSNListViewDataSource finderColumnIds]];

  [ids removeObject: FSNListColumnIdName];
  /* The owner column is this list view's own, not one Finder has. */
  [ids removeObject: FSNListColumnIdOwner];
  return ids;
}

- (id)init
{
  self = [super init];
  if (self)
    {
      iconSize = 64;
      gridSpacing = 54;
      textSize = 12;
      showsIconPreview = YES;
      ASSIGN (arrangeBy, @"none");
      listTextSize = 12;
      columnTextSize = 12;
      columnShowsIcons = YES;
      columnShowsIconPreview = YES;
      columnShowsPreviewColumn = YES;
      columnArrangement = FSNIconsArrangeName;
      ASSIGN (visibleColumns, [NSSet set]);
      alwaysOpenStyle = DSStoreViewStyleIcon;
    }
  return self;
}

- (void)dealloc
{
  RELEASE (arrangeBy);
  RELEASE (backgroundColor);
  RELEASE (backgroundImagePath);
  RELEASE (backgroundImageAlias);
  RELEASE (visibleColumns);
  [super dealloc];
}

- (int)iconSize { return iconSize; }
- (void)setIconSize:(int)size { iconSize = clampInt (size, 16, 512); }
- (CGFloat)gridSpacing { return gridSpacing; }

- (void)setGridSpacing:(CGFloat)spacing
{
  gridSpacing = clampInt ((int)spacing, 54, 100);
}

- (int)textSize { return textSize; }

- (void)setTextSize:(int)size
{
  textSize = [FSNIconsView clampedLabelTextSize: size];
}

- (BOOL)labelOnRight { return labelOnRight; }
- (void)setLabelOnRight:(BOOL)flag { labelOnRight = flag; }
- (BOOL)showsItemInfo { return showsItemInfo; }
- (void)setShowsItemInfo:(BOOL)flag { showsItemInfo = flag; }
- (BOOL)showsIconPreview { return showsIconPreview; }
- (void)setShowsIconPreview:(BOOL)flag { showsIconPreview = flag; }
- (NSString *)arrangeBy { return arrangeBy; }

- (void)setArrangeBy:(NSString *)value
{
  /* Only the arrangements the pop-up has; a stored value this view cannot
   * show is the same as none. */
  ASSIGN (arrangeBy, [[GWViewOptionsModel arrangeByValues] containsObject: value]
                       ? value : @"none");
}

- (DSStoreBackgroundType)backgroundType { return backgroundType; }
- (void)setBackgroundType:(DSStoreBackgroundType)type { backgroundType = type; }
- (NSColor *)backgroundColor { return backgroundColor; }
- (void)setBackgroundColor:(NSColor *)color { ASSIGN (backgroundColor, color); }
- (NSString *)backgroundImagePath { return backgroundImagePath; }
- (void)setBackgroundImagePath:(NSString *)path
{
  if ([path isEqual: backgroundImagePath] == NO)
    DESTROY (backgroundImageAlias);
  ASSIGN (backgroundImagePath, path);
}
- (NSData *)backgroundImageAlias { return backgroundImageAlias; }
- (void)setBackgroundImageAlias:(NSData *)alias { ASSIGN (backgroundImageAlias, alias); }

- (int)listTextSize { return listTextSize; }

- (void)setListTextSize:(int)size
{
  listTextSize = [FSNIconsView clampedLabelTextSize: size];
}

- (BOOL)listLargeIcons { return listLargeIcons; }
- (void)setListLargeIcons:(BOOL)flag { listLargeIcons = flag; }
- (NSSet *)visibleColumns { return visibleColumns; }

- (void)setVisibleColumns:(NSSet *)ids
{
  NSMutableSet *set = [NSMutableSet setWithSet: ids];

  [set intersectSet: [NSSet setWithArray: [GWViewOptionsModel optionalListColumnIds]]];
  ASSIGN (visibleColumns, set);
}

- (BOOL)usesRelativeDates { return usesRelativeDates; }
- (void)setUsesRelativeDates:(BOOL)flag { usesRelativeDates = flag; }
- (BOOL)calculatesAllSizes { return calculatesAllSizes; }
- (void)setCalculatesAllSizes:(BOOL)flag { calculatesAllSizes = flag; }
- (int)columnTextSize { return columnTextSize; }

- (void)setColumnTextSize:(int)size
{
  columnTextSize = [FSNIconsView clampedLabelTextSize: size];
}

- (BOOL)columnShowsIcons { return columnShowsIcons; }
- (void)setColumnShowsIcons:(BOOL)flag { columnShowsIcons = flag; }
- (BOOL)columnShowsIconPreview { return columnShowsIconPreview; }
- (void)setColumnShowsIconPreview:(BOOL)flag { columnShowsIconPreview = flag; }
- (BOOL)columnShowsPreviewColumn { return columnShowsPreviewColumn; }
- (void)setColumnShowsPreviewColumn:(BOOL)flag { columnShowsPreviewColumn = flag; }
- (FSNIconsArrangement)columnArrangement { return columnArrangement; }
- (void)setColumnArrangement:(FSNIconsArrangement)value { columnArrangement = value; }

- (void)takeFromColumnViewOptions:(FSNColumnViewOptions *)options
{
  [self setColumnTextSize: [options textSize]];
  [self setColumnShowsIcons: [options showsIcons]];
  [self setColumnShowsIconPreview: [options showsIconPreview]];
  [self setColumnShowsPreviewColumn: [options showsPreviewColumn]];
  [self setColumnArrangement: [options arrangement]];
}

- (void)applyToColumnViewOptions:(FSNColumnViewOptions *)options
{
  [options setTextSize: columnTextSize];
  [options setShowsIcons: columnShowsIcons];
  [options setShowsIconPreview: columnShowsIconPreview];
  [options setShowsPreviewColumn: columnShowsPreviewColumn];
  [options setArrangement: columnArrangement];
}

- (void)putIntoInfo:(DSStoreInfo *)info forViewKind:(GWViewOptionsKind)kind
{
  if (kind == GWViewOptionsColumnView)
    [self putViewStyleIntoInfo: info];
  else
    [self putIntoInfo: info forListView: kind == GWViewOptionsListView];
}

- (BOOL)alwaysOpen { return alwaysOpen; }
- (void)setAlwaysOpen:(BOOL)flag { alwaysOpen = flag; }
- (DSStoreViewStyle)alwaysOpenStyle { return alwaysOpenStyle; }
- (void)setAlwaysOpenStyle:(DSStoreViewStyle)style { alwaysOpenStyle = style; }

- (void)takeFromInfo:(DSStoreInfo *)info
{
  if (info == nil)
    return;

  if ([info hasIconSize] && [info iconSize] > 0)
    [self setIconSize: [info iconSize]];
  if ([info hasGridSpacing] && [info gridSpacing] > 0)
    [self setGridSpacing: [info gridSpacing]];
  if ([info hasIconTextSize])
    [self setTextSize: (int)[info iconTextSize]];
  if ([info hasLabelPosition])
    [self setLabelOnRight: [info labelPosition] == DSStoreLabelPositionRight];
  if ([info hasShowItemInfo])
    [self setShowsItemInfo: [info showItemInfo]];
  if ([info hasShowIconPreview])
    [self setShowsIconPreview: [info showIconPreview]];
  if ([info arrangeBy])
    [self setArrangeBy: [info arrangeBy]];
  [self setBackgroundType: [info backgroundType]];
  [self setBackgroundColor: [info backgroundColor]];
  /* A Mac writes the alias record only; its path tags say where the image is. */
  [self setBackgroundImagePath: [info backgroundImagePath]
    ? [info backgroundImagePath]
    : [GWFolderViewOptions backgroundImagePathForAlias: [info backgroundImageAlias]]];
  [self setBackgroundImageAlias: [info backgroundImageAlias]];

  if ([info hasListTextSize])
    [self setListTextSize: [info listTextSize]];
  if ([info hasListIconSize])
    [self setListLargeIcons: [info listIconSize] > 16];
  if ([info hasUseRelativeDates])
    [self setUsesRelativeDates: [info useRelativeDates]];
  if ([info hasCalculateAllSizes])
    [self setCalculatesAllSizes: [info calculateAllSizes]];
  if ([info listColumns])
    {
      NSMutableSet *shown = [NSMutableSet set];
      NSDictionary *visible = [info columnVisible];
      NSString *columnId;

      for (columnId in visible)
        {
          if ([[visible objectForKey: columnId] boolValue])
            [shown addObject: columnId];
        }
      [self setVisibleColumns: shown];
    }

  if ([info hasViewStyle])
    {
      [self setAlwaysOpen: YES];
      [self setAlwaysOpenStyle: [info viewStyle]];
    }
}

- (void)takeFromIconsView:(FSNIconsView *)view
{
  [self setIconSize: [view iconSize]];
  [self setTextSize: [view labelTextSize]];
  [self setLabelOnRight: [view iconPosition] == NSImageLeft];
  [self setShowsItemInfo: [view showsItemInfo]];
  [self setShowsIconPreview: [view showsIconPreview]];
  [self setArrangeBy: [GWFolderViewOptions arrangeByForArrangement: [view arrangement]
                                                        snapsToGrid: [view snapsToGrid]]];
}

- (void)takeFromListDataSource:(FSNListViewDataSource *)dataSource
{
  NSMutableSet *shown = [NSMutableSet set];
  NSString *columnId;

  /* 0 is the default text size of the cells, which Finder calls 12. */
  [self setListTextSize: [dataSource textSize] > 0 ? (int)[dataSource textSize] : 12];
  [self setListLargeIcons: [dataSource listIconSize] > 16];
  [self setUsesRelativeDates: [dataSource usesRelativeDates]];
  [self setCalculatesAllSizes: [dataSource calculatesAllSizes]];
  for (columnId in [GWViewOptionsModel optionalListColumnIds])
    {
      if ([dataSource isColumnVisible: columnId])
        [shown addObject: columnId];
    }
  [self setVisibleColumns: shown];
}

- (void)applyToIconsView:(FSNIconsView *)view
{
  BOOL snaps;
  FSNIconsArrangement arrangement =
    [GWFolderViewOptions arrangementForArrangeBy: arrangeBy snapsToGrid: &snaps];

  [view setIconSize: iconSize];
  [view setIconPosition: labelOnRight ? NSImageLeft : NSImageAbove];
  [view setLabelTextSize: textSize];
  [view setShowsItemInfo: showsItemInfo];
  [view setShowsIconPreview: showsIconPreview];
  /* Snap first: arranging lays the icons out, snapping only matters for
   * the positions an unarranged view keeps. */
  [view setSnapsToGrid: snaps];
  [view setArrangement: arrangement];

  switch (backgroundType)
    {
    case DSStoreBackgroundColor:
      [view setBackgroundImage: nil];
      if (backgroundColor)
        [view setBackgroundColor: backgroundColor];
      break;
    case DSStoreBackgroundPicture:
      {
        NSImage *image = backgroundImagePath
          ? [[[NSImage alloc] initWithContentsOfFile: backgroundImagePath] autorelease] : nil;

        /* Around the picture and without one the view is white, as Finder's. */
        [view setBackgroundColor: [NSColor controlBackgroundColor]];
        [view setBackgroundImage: image];
      }
      break;
    default:
      [view setBackgroundImage: nil];
      [view setBackgroundColor: [NSColor controlBackgroundColor]];
      break;
    }
}

- (void)applyToListDataSource:(FSNListViewDataSource *)dataSource
{
  NSString *columnId;

  /* Columns first: the size column has to be shown for sizes to matter. */
  for (columnId in [GWViewOptionsModel optionalListColumnIds])
    [dataSource setColumn: columnId visible: [visibleColumns containsObject: columnId]];
  [dataSource setTextSize: listTextSize];
  [dataSource setListIconSize: listLargeIcons ? 32 : 16];
  [dataSource setUsesRelativeDates: usesRelativeDates];
  [dataSource setCalculatesAllSizes: calculatesAllSizes];
}

- (void)putIntoInfo:(DSStoreInfo *)info
{
  [self putIconOptionsIntoInfo: info];
  [self putListOptionsIntoInfo: info];
  [self putViewStyleIntoInfo: info];
}

- (void)putIntoInfo:(DSStoreInfo *)info forListView:(BOOL)list
{
  if (list)
    [self putListOptionsIntoInfo: info];
  else
    [self putIconOptionsIntoInfo: info];
  [self putViewStyleIntoInfo: info];
}

- (void)putIconOptionsIntoInfo:(DSStoreInfo *)info
{
  [info setIconSize: iconSize];
  [info setHasIconSize: YES];
  [info setGridSpacing: gridSpacing];
  [info setHasGridSpacing: YES];
  [info setIconTextSize: textSize];
  [info setHasIconTextSize: YES];
  [info setLabelPosition: labelOnRight ? DSStoreLabelPositionRight : DSStoreLabelPositionBottom];
  [info setHasLabelPosition: YES];
  [info setShowItemInfo: showsItemInfo];
  [info setHasShowItemInfo: YES];
  [info setShowIconPreview: showsIconPreview];
  [info setHasShowIconPreview: YES];
  [info setArrangeBy: arrangeBy];

  [info setBackgroundType: backgroundType];
  [info setBackgroundColor: backgroundType == DSStoreBackgroundColor ? backgroundColor : nil];
  [info setBackgroundImagePath: backgroundType == DSStoreBackgroundPicture
                                  ? backgroundImagePath : nil];
  /* Finder finds a picture through its alias record. */
  if (backgroundType != DSStoreBackgroundPicture)
    [info setBackgroundImageAlias: nil];
  else if (backgroundImageAlias)
    [info setBackgroundImageAlias: backgroundImageAlias];
  else
    [info setBackgroundImageAlias: backgroundImagePath
       ? [GWFolderViewOptions backgroundImageAliasForPath: backgroundImagePath] : nil];
}

- (void)putListOptionsIntoInfo:(DSStoreInfo *)info
{
  NSMutableDictionary *columns;
  NSString *columnId;

  [info setListTextSize: listTextSize];
  [info setHasListTextSize: YES];
  [info setListIconSize: listLargeIcons ? 32 : 16];
  [info setHasListIconSize: YES];
  [info setUseRelativeDates: usesRelativeDates];
  [info setHasUseRelativeDates: YES];
  [info setCalculateAllSizes: calculatesAllSizes];
  [info setHasCalculateAllSizes: YES];

  /* Visibility in the columns the record already describes; a view that
   * shows them gives the complete description (see
   * +[GWFolderViewOptions takeListViewOptionsOf:into:]). */
  columns = [NSMutableDictionary dictionary];
  for (columnId in [info listColumns])
    {
      NSMutableDictionary *column =
        [NSMutableDictionary dictionaryWithDictionary: [[info listColumns] objectForKey: columnId]];

      if ([columnId isEqual: FSNListColumnIdName] == NO)
        {
          [column setObject: [NSNumber numberWithBool: [visibleColumns containsObject: columnId]]
                     forKey: @"visible"];
        }
      [columns setObject: column forKey: columnId];
    }
  if ([columns count] > 0)
    [info setListColumns: columns];
}

- (void)putViewStyleIntoInfo:(DSStoreInfo *)info
{
  if (alwaysOpen)
    {
      [info setViewStyle: alwaysOpenStyle];
      [info setHasViewStyle: YES];
    }
  else
    {
      [info setHasViewStyle: NO];
    }
}

@end
