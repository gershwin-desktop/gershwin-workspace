/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 */

/* What the View Options panel shows and edits: the options Finder keeps per
 * folder in .DS_Store (icvp, lsvp, vstl), as one value that moves onto an
 * icon or list view, back from them, and into a folder's records.  No user
 * interface in here, so it can be tested without one. */

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import "DSStore.h"

@class DSStoreInfo;
@class FSNIconsView;
@class FSNListViewDataSource;

@interface GWViewOptionsModel : NSObject
{
  int iconSize;
  CGFloat gridSpacing;
  int textSize;
  BOOL labelOnRight;
  BOOL showsItemInfo;
  BOOL showsIconPreview;
  NSString *arrangeBy;
  DSStoreBackgroundType backgroundType;
  NSColor *backgroundColor;
  NSString *backgroundImagePath;

  int listTextSize;
  BOOL listLargeIcons;
  NSSet *visibleColumns;
  BOOL usesRelativeDates;
  BOOL calculatesAllSizes;

  BOOL alwaysOpen;
  DSStoreViewStyle alwaysOpenStyle;
}

/* Icon size 16 to 512 points; a value outside is brought to the nearest. */
- (int)iconSize;
- (void)setIconSize:(int)size;
/* Space between icons, 54 to 100 as Finder's slider [G: Finder 10.6 range]. */
- (CGFloat)gridSpacing;
- (void)setGridSpacing:(CGFloat)spacing;
/* Name text size, 10 to 16. */
- (int)textSize;
- (void)setTextSize:(int)size;
- (BOOL)labelOnRight;
- (void)setLabelOnRight:(BOOL)flag;
- (BOOL)showsItemInfo;
- (void)setShowsItemInfo:(BOOL)flag;
- (BOOL)showsIconPreview;
- (void)setShowsIconPreview:(BOOL)flag;
/* One of +arrangeByValues. */
- (NSString *)arrangeBy;
- (void)setArrangeBy:(NSString *)value;
- (DSStoreBackgroundType)backgroundType;
- (void)setBackgroundType:(DSStoreBackgroundType)type;
- (NSColor *)backgroundColor;
- (void)setBackgroundColor:(NSColor *)color;
- (NSString *)backgroundImagePath;
- (void)setBackgroundImagePath:(NSString *)path;

/* List text size, 10 to 16. */
- (int)listTextSize;
- (void)setListTextSize:(int)size;
/* Large icons are 32 points, small ones 16 [O:E5]. */
- (BOOL)listLargeIcons;
- (void)setListLargeIcons:(BOOL)flag;
/* Finder ids of the shown columns apart from the name, which is always
 * shown. */
- (NSSet *)visibleColumns;
- (void)setVisibleColumns:(NSSet *)ids;
- (BOOL)usesRelativeDates;
- (void)setUsesRelativeDates:(BOOL)flag;
- (BOOL)calculatesAllSizes;
- (void)setCalculatesAllSizes:(BOOL)flag;

/* "Always open in <view>": the folder keeps its view style (vstl), which
 * Finder stores only for this [O:E5]. */
- (BOOL)alwaysOpen;
- (void)setAlwaysOpen:(BOOL)flag;
- (DSStoreViewStyle)alwaysOpenStyle;
- (void)setAlwaysOpenStyle:(DSStoreViewStyle)style;

/* The arrangements in the order the pop-up lists them: none, grid, name,
 * kind, dateModified, dateCreated, size, label. */
+ (NSArray *)arrangeByValues;
/* The list columns that can be ticked, in Finder's order. */
+ (NSArray *)optionalListColumnIds;

/* Every option the record has; the others keep their value. */
- (void)takeFromInfo:(DSStoreInfo *)info;
- (void)takeFromIconsView:(FSNIconsView *)view;
- (void)takeFromListDataSource:(FSNListViewDataSource *)dataSource;

- (void)applyToIconsView:(FSNIconsView *)view;
- (void)applyToListDataSource:(FSNListViewDataSource *)dataSource;

/* The options of the kind of view shown into the record: the icon view
 * options or the list view options, never the ones of a view the user has
 * not set up.  The view style is stored only with "Always open in", and
 * dropped without. */
- (void)putIntoInfo:(DSStoreInfo *)info forListView:(BOOL)list;

/* Both kinds. */
- (void)putIntoInfo:(DSStoreInfo *)info;

@end
