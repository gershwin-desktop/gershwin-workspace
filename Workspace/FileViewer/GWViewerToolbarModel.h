/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

/* What the toolbar of a browsing viewer window offers and when each of its
 * controls can be used.  The decisions live here, apart from the views, so
 * they can be tested without a display; GWViewerToolbar builds the items and
 * feeds this model the state of its window. */

#import <Foundation/Foundation.h>

/* One toolbar configuration for all browsing windows: customizing one
 * window's toolbar changes them all, and NSToolbar stores the set under
 * "NSToolbar Config <identifier>" in the user's defaults. */
extern NSString *const GWViewerToolbarIdentifier;

extern NSString *const GWToolbarBackForwardItemIdentifier;
extern NSString *const GWToolbarViewModeItemIdentifier;
extern NSString *const GWToolbarLookInsideItemIdentifier;
extern NSString *const GWToolbarActionItemIdentifier;
extern NSString *const GWToolbarSearchItemIdentifier;
extern NSString *const GWToolbarPathItemIdentifier;
extern NSString *const GWToolbarNewFolderItemIdentifier;
extern NSString *const GWToolbarDeleteItemIdentifier;
extern NSString *const GWToolbarGetInfoItemIdentifier;
extern NSString *const GWToolbarEjectItemIdentifier;
extern NSString *const GWToolbarConnectItemIdentifier;

/* The single controls a toolbar item can carry; Back and Forward are two
 * segments of one item but are enabled separately. */
typedef enum {
  GWToolbarControlBack,
  GWToolbarControlForward,
  GWToolbarControlViewMode,
  GWToolbarControlLookInside,
  GWToolbarControlAction,
  GWToolbarControlSearch,
  GWToolbarControlPath,
  GWToolbarControlNewFolder,
  GWToolbarControlDelete,
  GWToolbarControlGetInfo,
  GWToolbarControlEject,
  GWToolbarControlConnect
} GWToolbarControl;

/* The window state the decisions depend on. */
typedef struct {
  BOOL canGoBack;
  BOOL canGoForward;
  BOOL hasSelection;       /* items selected, not just the shown folder */
  BOOL showsTrash;         /* the window shows the trash */
  BOOL folderWritable;     /* the shown folder can take a new folder */
  BOOL selectionHasVolume; /* a selected item is an ejectable volume */
} GWViewerToolbarState;

@interface GWViewerToolbarModel : NSObject

/* The set a new user starts with, left to right. */
+ (NSArray *)defaultItemIdentifiers;

/* Everything the customization palette offers, the default set included. */
+ (NSArray *)allowedItemIdentifiers;

+ (BOOL)isControl:(GWToolbarControl)control enabledInState:(GWViewerToolbarState)state;

@end
