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
#import "GWViewer.h"

@class GWViewersManager;
@class GWViewerPathsPopUp;
@class GWX11SpatialPath;
@class FSNode;
@class FSNodeRep;
@class GWViewerWindow;
@class Workspace;
@class NSView;
@class NSTextField;
@class GWViewerScrollView;
@class DSStoreInfo;
@class GWViewSettingsManager;

@interface GWSpatialViewer : NSObject
{
  GWViewerWindow *vwrwin;
  NSView *mainView;
  NSView *topBox;
  NSTextField *elementsLabel;
  NSTextField *spaceLabel;
  GWViewerPathsPopUp *pathsPopUp;
  GWViewerScrollView *scroll;
  id nodeView;

  NSDictionary *viewerPrefs;
  NSString *viewType;
  BOOL rootviewer;
  NSNumber *rootViewerKey;

  int visibleCols;
  int resizeIncrement;

  FSNode *baseNode;
  NSArray *baseNodeArray;
  NSArray *lastSelection;
  NSMutableArray *watchedNodes;
  
  // History support (required by GWViewersManager)
  NSMutableArray *history;
  int historyPosition;

  FSNodeRep *fsnodeRep;

  // .DS_Store view-settings persistence (full spec hierarchy)
  GWViewSettingsManager *_settingsManager;  // Orchestrates read/write (§2-3)
  DSStoreInfo *dsStoreInfo;                 // Current working copy of view settings
  NSString *dsStorePath;                    // Path to .DS_Store file being watched

  BOOL invalidated;
  BOOL closing;

  GWViewersManager *manager;
  Workspace *gworkspace;

  NSNotificationCenter *nc;

  // X11 atom-based spatial path for WM titlebar popup
  GWX11SpatialPath *_x11Path;
}

- (id)initForNode:(FSNode *)node
         inWindow:(GWViewerWindow *)win
         showType:(NSString *)stype
    showSelection:(BOOL)showsel;
- (void)createSubviews;
- (FSNode *)baseNode;
- (BOOL)isShowingNode:(FSNode *)anode;
- (BOOL)isShowingPath:(NSString *)apath;
- (void)reloadNodeContents;
- (void)reloadFromNode:(FSNode *)anode;
- (void)unloadFromNode:(FSNode *)anode;
- (void)updateWindowTitle;

- (GWViewerWindow *)win;
- (id)nodeView;
- (id)shelf;
- (GWViewType)viewType;
- (BOOL)isRootViewer;
- (NSNumber *)rootViewerKey;
- (BOOL)isSpatial;
- (int)vtype;

- (void)activate;
- (void)deactivate;
- (void)scrollToBeginning;
- (void)invalidate;
- (BOOL)invalidated;
- (BOOL)isClosing;

- (void)setOpened:(BOOL)opened
        repOfNode:(FSNode *)anode;
- (void)unselectAllReps;
- (void)selectionChanged:(NSArray *)newsel;
- (void)multipleNodeViewDidSelectSubNode:(FSNode *)node;
- (void)setSelectableNodesRange:(NSRange)range;
- (void)updeateInfoLabels;
- (void)popUpAction:(id)sender;

- (BOOL)involvedByFileOperation:(NSDictionary *)opinfo;
- (void)nodeContentsWillChange:(NSDictionary *)info;
- (void)nodeContentsDidChange:(NSDictionary *)info;

- (void)watchedPathChanged:(NSDictionary *)info;
- (NSArray *)watchedNodes;

- (void)hideDotsFileChanged:(BOOL)hide;
- (void)hiddenFilesChanged:(NSArray *)paths;

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

// History support (required by GWViewersManager)
- (NSMutableArray *)history;
- (int)historyPosition;
- (void)setHistoryPosition:(int)pos;

@end


//
// GWViewerWindow Delegate Methods
//
@interface GWSpatialViewer (GWViewerWindowDelegateMethods)

- (void)openSelectionInNewViewer:(BOOL)newv;
- (void)openSelectionAsFolder;
- (void)openSelectionWith;
- (void)newFolder;
- (void)newFile;
- (void)duplicateFiles;
- (void)recycleFiles;
- (void)emptyTrash;
- (void)deleteFiles;
- (void)goBackwardInHistory;
- (void)goForwardInHistory;
- (void)setViewerBehaviour:(id)sender;
- (void)setViewerType:(id)sender;
- (void)setShownType:(id)sender;
- (void)setExtendedShownType:(id)sender;
- (void)setIconsSize:(id)sender;
- (void)setIconsPosition:(id)sender;
- (void)setLabelSize:(id)sender;
- (void)chooseLabelColor:(id)sender;
- (void)chooseBackColor:(id)sender;
- (void)selectAllInViewer;
- (void)showTerminal;
- (void)showAttributesInspector:(id)sender;
- (NSArray *)lastSelection;
- (BOOL)validateItem:(id)menuItem;

@end