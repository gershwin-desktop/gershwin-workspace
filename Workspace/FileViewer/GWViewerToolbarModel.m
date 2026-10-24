/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

#import "GWViewerToolbarModel.h"
#import <AppKit/NSToolbarItem.h>

NSString *const GWViewerToolbarIdentifier = @"GWBrowsingViewerToolbar";

/* Stored in the user's toolbar configuration, so they must never change. */
NSString *const GWToolbarBackForwardItemIdentifier = @"GWToolbarBackForwardItem";
NSString *const GWToolbarViewModeItemIdentifier = @"GWToolbarViewModeItem";
NSString *const GWToolbarLookInsideItemIdentifier = @"GWToolbarLookInsideItem";
NSString *const GWToolbarActionItemIdentifier = @"GWToolbarActionItem";
NSString *const GWToolbarSearchItemIdentifier = @"GWToolbarSearchItem";
NSString *const GWToolbarPathItemIdentifier = @"GWToolbarPathItem";
NSString *const GWToolbarNewFolderItemIdentifier = @"GWToolbarNewFolderItem";
NSString *const GWToolbarDeleteItemIdentifier = @"GWToolbarDeleteItem";
NSString *const GWToolbarGetInfoItemIdentifier = @"GWToolbarGetInfoItem";
NSString *const GWToolbarEjectItemIdentifier = @"GWToolbarEjectItem";
NSString *const GWToolbarConnectItemIdentifier = @"GWToolbarConnectItem";

@implementation GWViewerToolbarModel

+ (NSArray *)defaultItemIdentifiers
{
  /* Navigation at the left edge, search at the right, the view controls
   * held in the middle by a flexible space on either side. */
  return [NSArray
      arrayWithObjects:GWToolbarBackForwardItemIdentifier, NSToolbarFlexibleSpaceItemIdentifier,
                       GWToolbarViewModeItemIdentifier, GWToolbarLookInsideItemIdentifier,
                       GWToolbarActionItemIdentifier, NSToolbarFlexibleSpaceItemIdentifier,
                       GWToolbarSearchItemIdentifier, nil];
}

+ (NSArray *)allowedItemIdentifiers
{
  /* Palette order: the navigation and view controls first, then the
   * single-action buttons, then the spacers. */
  return [NSArray arrayWithObjects:GWToolbarBackForwardItemIdentifier, GWToolbarPathItemIdentifier,
                                   GWToolbarViewModeItemIdentifier, GWToolbarActionItemIdentifier,
                                   GWToolbarEjectItemIdentifier,
                                   NSToolbarCustomizeToolbarItemIdentifier,
                                   GWToolbarNewFolderItemIdentifier, GWToolbarDeleteItemIdentifier,
                                   GWToolbarConnectItemIdentifier, GWToolbarGetInfoItemIdentifier,
                                   GWToolbarSearchItemIdentifier, GWToolbarLookInsideItemIdentifier,
                                   NSToolbarSeparatorItemIdentifier, NSToolbarSpaceItemIdentifier,
                                   NSToolbarFlexibleSpaceItemIdentifier, nil];
}

+ (BOOL)isControl:(GWToolbarControl)control enabledInState:(GWViewerToolbarState)state
{
  switch (control) {
    case GWToolbarControlBack:
      return state.canGoBack;
    case GWToolbarControlForward:
      return state.canGoForward;
    case GWToolbarControlLookInside:
    case GWToolbarControlGetInfo:
      return state.hasSelection;
    case GWToolbarControlDelete:
      /* The same rule as File > Move to Trash. */
      return state.hasSelection && (state.showsTrash == NO);
    case GWToolbarControlNewFolder:
      return state.folderWritable && (state.showsTrash == NO);
    case GWToolbarControlEject:
      return state.selectionHasVolume;
    case GWToolbarControlViewMode:
    case GWToolbarControlAction:
    case GWToolbarControlSearch:
    case GWToolbarControlPath:
    case GWToolbarControlConnect:
      return YES;
  }
  return NO;
}

@end
