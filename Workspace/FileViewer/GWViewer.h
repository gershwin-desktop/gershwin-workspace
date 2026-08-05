/* GWViewer.h
 *  
 * Copyright (C) 2004-2013 Free Software Foundation, Inc.
 *
 * Author: Enrico Sersale <enrico@imago.ro>
 * Date: July 2004
 *
 * This file is part of the GNUstep Workspace application
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 * 
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 * 
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 31 Milk Street #960789 Boston, MA 02196 USA.
 */



#import "GWViewerBase.h"

@class GWViewersManager;
@class FSNode;
@class FSNodeRep;
@class GWViewerWindow;
@class GWViewerSplit;
@class GWViewerShelf;
#import "GWViewerBase.h"

@class GWViewerSidebar;
@class GWViewerScrollView;
@class GWViewerIconsPath;
@class GWViewerPathsScroll;
@class GWViewerBrowserPreview;
@class NSView;
@class Workspace;

@interface GWViewer : GWViewerBase
{
  GWViewerSplit *split;
  GWViewerSidebar *sidebar;
  float sidebarWidth;
  NSView *lowBox;
  GWViewerPathsScroll *pathsScroll;
  GWViewerIconsPath *pathsView;
  GWViewerScrollView *nviewScroll;

  GWViewType viewType;

  BOOL rootViewer; /* base path = root */
  BOOL firstRootViewer; /* special first viewer */
  NSString *defaultsKeyStr;

  /* Full window frame (GNUstep bottom-left coords) to re-apply after the
   * window is mapped.  GNUstep's setFrame: in init runs before the WM has
   * framed the window, so it uses stale/guessed decoration offsets and the
   * window lands a couple of px off; re-applying the exact frame after
   * makeKeyAndOrderFront: (when the WM has set _NET_FRAME_EXTENTS) places it
   * exactly and keeps it from drifting on every open/close cycle. */
  NSRect pendingRestoreFrame;
  BOOL hasPendingRestoreFrame;
}

- (id)initForNode:(FSNode *)node
         inWindow:(GWViewerWindow *)win
         showType:(GWViewType)stype
    showSelection:(BOOL)showsel
	  withKey:(NSString *)key;

- (FSNode *)baseNode;
- (BOOL)isShowingNode:(FSNode *)anode;
- (BOOL)isShowingPath:(NSString *)apath;
- (void)createSubviews;
- (void)unloadFromNode:(FSNode *)anode;
- (void)updateShownSelection;
- (void)navigateToNode:(FSNode *)node;

/* Re-base the viewer window to a new node (sidebar navigation).
   Recreates the node view, updates the window title and path bar,
   and resets history. */
- (void)openNodeInPlace:(FSNode *)newBase;

- (GWViewerWindow *)win;
- (id)shelf;
- (GWViewType)viewType;
- (BOOL)isSpatial;
- (int)vtype;

/* the first among root viewers, the default Viewer */
- (BOOL)isFirstRootViewer;

/* returns the key used in the defaults (prefsname) */
- (NSString *)defaultsKey;

- (void)activate;
- (void)tileViews;
- (CGFloat)defaultSidebarWidth;
- (void)setSidebarWidth:(CGFloat)w;
- (void)reloadSidebar;
- (void)invalidate;
- (void)unselectAllReps;
- (void)selectionChanged:(NSArray *)newsel;
- (void)multipleNodeViewDidSelectSubNode:(FSNode *)node;
- (void)pathsViewDidSelectIcon:(id)icon;
- (void)shelfDidSelectIcon:(id)icon;
- (void)setSelectableNodesRange:(NSRange)range;
- (void)updeateInfoLabels;
- (BOOL)involvedByFileOperation:(NSDictionary *)opinfo;
- (void)nodeContentsDidChange:(NSDictionary *)info;
- (void)watchedPathChanged:(NSDictionary *)info;
- (void)columnsWidthChanged:(NSNotification *)notification;

- (void)updateDefaults;

@end


//
// GWViewerWindow Delegate Methods
//
@interface GWViewer (GWViewerWindowDelegateMethods)

- (void)openSelectionInNewViewer:(BOOL)newv;
- (void)setViewerBehaviour:(id)sender;
- (void)setViewerType:(id)sender;
- (void)setShownType:(id)sender;
- (void)setExtendedShownType:(id)sender;
- (void)chooseLabelColor:(id)sender;
- (void)chooseBackColor:(id)sender;
- (void)selectAllInViewer;
- (void)showTerminal;
- (BOOL)validateItem:(id)menuItem;
- (void)makeThumbnails:(id)sender;
- (void)removeThumbnails:(id)sender;

@end

/* Shared view-type helpers used by both the browsing GWViewer and the
 * spatial GWSpatialViewer.  The GWViewType enum is the canonical
 * representation; the string names ("Icon"/"List"/"Browser") are only a
 * legacy form used by GWSpatialViewer's defaults and DS_Store, so the
 * conversion lives here once. */
@interface NSObject (GWViewTypeHelpers)

/* Converts a GWViewType enum to its legacy string name, or nil. */
- (NSString *)GWViewTypeName:(GWViewType)type;

/* Converts a legacy string name to a GWViewType, or 0 if unknown. */
- (GWViewType)GWViewTypeFromName:(NSString *)name;

/* Resolves the requested view type from a menu sender, preferring its tag
 * (which carries the GWViewType) and falling back to parsing the localized
 * title for senders that only provide a title.  Returns 0 if it cannot be
 * determined. */
- (GWViewType)GWViewTypeFromSender:(id)sender;

@end

