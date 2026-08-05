/* GWSpatialViewer.h
 *
 * Copyright (C) 2004-2012 Free Software Foundation, Inc.
 *
 * Author: Enrico Sersale <enrico@imago.ro>
 * Date: June 2004
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
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02111 USA.
 */

#import <Foundation/Foundation.h>
#import "GWViewerBase.h"

@class GWViewersManager;
@class GWViewerPathsPopUp;
@class GWX11SpatialPath;
@class FSNode;
@class FSNodeRep;
@class GWViewerWindow;
@class GWViewerBrowserPreview;
@class Workspace;
@class NSView;
@class NSTextField;
@class GWViewerScrollView;
@class DSStoreInfo;
@class GWViewSettingsManager;

@interface GWSpatialViewer : GWViewerBase
{
  NSView *mainView;
  NSView *topBox;
  NSTextField *elementsLabel;
  NSTextField *spaceLabel;
  GWViewerPathsPopUp *pathsPopUp;
  GWViewerScrollView *scroll;

  NSString *viewType;
  BOOL rootviewer;
  NSNumber *rootViewerKey;

  // .DS_Store view-settings persistence (full spec hierarchy)
  GWViewSettingsManager *_settingsManager;  // Orchestrates read/write (§2-3)
  DSStoreInfo *dsStoreInfo;                 // Current working copy of view settings
  NSString *dsStorePath;                    // Path to .DS_Store file being watched

  // X11 atom-based spatial path for WM titlebar popup
  GWX11SpatialPath *_x11Path;

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
         showType:(NSString *)stype
    showSelection:(BOOL)showsel;
- (FSNode *)baseNode;
- (NSString *)defaultsKey;
- (BOOL)isShowingNode:(FSNode *)anode;
- (BOOL)isShowingPath:(NSString *)apath;
- (void)createSubviews;
- (void)unloadFromNode:(FSNode *)anode;
- (GWViewerWindow *)win;
- (id)shelf;
- (GWViewType)viewType;
- (BOOL)isRootViewer;
- (NSNumber *)rootViewerKey;
- (BOOL)isSpatial;
- (int)vtype;

- (void)activate;
- (void)invalidate;
- (void)unselectAllReps;
- (void)selectionChanged:(NSArray *)newsel;
- (void)multipleNodeViewDidSelectSubNode:(FSNode *)node;
- (void)setSelectableNodesRange:(NSRange)range;
- (void)updeateInfoLabels;
- (void)popUpAction:(id)sender;
- (BOOL)involvedByFileOperation:(NSDictionary *)opinfo;
- (void)nodeContentsDidChange:(NSDictionary *)info;
- (void)watchedPathChanged:(NSDictionary *)info;
- (void)columnsWidthChanged:(NSNotification *)notification;

- (void)updateDefaults;
- (void)applyContentBackgroundColor;

// DS_Store file watching for interoperability
- (void)setupDSStoreWatcher;
- (void)teardownDSStoreWatcher;
- (void)reapplyDSStoreSettings;
- (void)applyDSStoreSettingsToIconView:(id)iconView;
- (void)applyDSStoreSettingsToListView:(id)listView;
- (void)applyDSStoreSettingsToBrowserView:(id)browserView;
- (DSStoreInfo *)dsStoreInfo;
- (GWViewSettingsManager *)settingsManager;

@end


//
// GWViewerWindow Delegate Methods
//
@interface GWSpatialViewer (GWViewerWindowDelegateMethods)

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

@end