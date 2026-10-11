/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 */

/* The per-folder view options Finder keeps in .DS_Store (icvp, lsvp) moved
 * onto an icon or list view and back.  Both the browsing and the spatial
 * viewer go through here, so a folder looks the same in either. */

#import <AppKit/AppKit.h>
#import "FSNIconsView.h"

@class DSStoreInfo;
@class FSNListViewDataSource;
@class FSNListView;

@interface GWFolderViewOptions : NSObject

/* icvp arrangeBy -> Arrange By and Snap to Grid.  "grid" is snap to grid
 * without an arrangement; an unknown value is no arrangement, no snap. */
+ (FSNIconsArrangement)arrangementForArrangeBy:(NSString *)arrangeBy
                                   snapsToGrid:(BOOL *)snaps;

/* The inverse.  An arrangement wins over snap to grid, as in Finder's one
 * "arrangeBy" key. */
+ (NSString *)arrangeByForArrangement:(FSNIconsArrangement)arrangement
                          snapsToGrid:(BOOL)snaps;

/* Icon size, label position, text size, item info, icon preview and the
 * arrangement, each only when the record has it.  The scroll position only
 * when asked: re-applying it whenever a window comes to the front would
 * undo the user's scrolling. */
+ (void)applyIconViewOptionsOf:(DSStoreInfo *)info
                   toIconsView:(FSNIconsView *)view
       includingScrollPosition:(BOOL)scroll;

/* The view's current icon options into info.  An arrangeBy the view has
 * no arrangement for is kept as long as the view still shows it as such. */
+ (void)takeIconViewOptionsOf:(FSNIconsView *)view into:(DSStoreInfo *)info;

/* lsvp onto the list: visibility, order, sort, widths, text size, icon
 * size, relative dates, calculate all sizes - in that order, so that the
 * order is set on the columns that will be shown and the sort column is one
 * of them.  Nothing when the record has no list options. */
+ (void)applyListViewOptionsOf:(DSStoreInfo *)info
                  toDataSource:(FSNListViewDataSource *)dataSource;

/* All list options of the data source into info. */
+ (void)takeListViewOptionsOf:(FSNListViewDataSource *)dataSource
                         into:(DSStoreInfo *)info;

/* The lsvp scroll position onto the list, and back.  Applied only when a
 * folder is opened, like the icon view's. */
+ (void)applyListScrollPositionOf:(DSStoreInfo *)info toListView:(FSNListView *)list;
+ (void)takeListScrollPositionOf:(FSNListView *)list into:(DSStoreInfo *)info;

/* What the user can change of a view, as the record values it would give,
 * scroll position left out: compared before and after, they tell whether
 * the options were changed while the window was open. */
+ (NSDictionary *)iconViewStateOf:(FSNIconsView *)view;
+ (NSDictionary *)listViewStateOf:(FSNListViewDataSource *)dataSource;

/* Whether the folder opens in a spatial window: a stored bwsp ShowToolbar
 * decides (0 spatial, 1 browsing, as Finder's toolbar-less windows are its
 * spatial ones), else @p spatialDefault. */
+ (BOOL)opensSpatially:(DSStoreInfo *)info byDefault:(BOOL)spatialDefault;

/* A folder background picture as Finder 10.6 reads it: a classic alias
 * record of the image whose HFS path tag says "<volume>:<path in volume>"
 * [O:E12].  The volume name is the mount point's name, "Macintosh HD" for
 * the root file system [G: what the folder's volume is called on the Mac
 * that reads it is not known here]. */
+ (NSData *)backgroundImageAliasForPath:(NSString *)imagePath;

@end
