/* GWViewerBase.h
 *
 * Shared implementation for the browsing (GWViewer) and spatial
 * (GWSpatialViewer) viewer kinds.  Both viewers are windows showing a
 * folder; they differ only in their chrome (sidebar/paths bar vs.
 * popup/labels) and a few mode-specific behaviours.  Everything that is
 * identical between them lives here, so the two concrete classes only
 * contain their own layout and mode-specific logic.
 *
 * Copyright (C) 2004-2026 Free Software Foundation, Inc.
 *
 * This file is part of the GNUstep Workspace application
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 */

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import "FSNodeRep.h"

typedef enum
  {
    GWViewTypeBrowser = 1,
    GWViewTypeIcon,
    GWViewTypeList
  } GWViewType;

@class GWViewerWindow;
@class GWViewerBrowserPreview;
@class FSNode;
@class GWViewersManager;
@class Workspace;
@class DSStoreInfo;

@interface GWViewerBase : NSObject
{
  GWViewerWindow *vwrwin;
  id nodeView;

  /* Rightmost "Contents" preview pane, shown when the user enables the
   * "Show Inspector" toggle, in any view type. */
  GWViewerBrowserPreview *previewPane;
  BOOL showInspector;
  int inspectorPane;

  NSDictionary *viewerPrefs;

  int visibleCols;
  int resizeIncrement;

  FSNode *baseNode;
  NSArray *baseNodeArray;
  NSArray *lastSelection;
  NSMutableArray *watchedNodes;

  FSNodeRep *fsnodeRep;

  NSMutableArray *history;
  int historyPosition;

  BOOL invalidated;
  BOOL closing;

  GWViewersManager *manager;
  Workspace *gworkspace;

  NSNotificationCenter *nc;

  /* The user picked the view type in this window; only then is it kept
   * per folder (vstl), as Finder keeps it only for "Always open in". */
  BOOL viewTypeChosenByUser;

  /* A folder's stored scroll position (icon or list view), waiting for the
   * scroll to the top that opening and navigating end with, which would
   * otherwise drop it. */
  NSValue *pendingScrollPosition;

  /* The node view's options right after the folder's were applied; the
   * folder's icvp / lsvp is written on close only when they changed. */
  NSDictionary *appliedViewState;
}

/* Finder's per-folder options (.DS_Store icvp/lsvp) onto the node view. */
- (void)applyFolderViewOptions:(DSStoreInfo *)info includingScrollPosition:(BOOL)scroll;

/* The bars a viewer kind has, into bwsp.  Finder 10.6 keeps them per
 * folder only as a snapshot of its global settings and ignores them on read
 * [O:E13], so they are written, never applied; the base has none. */
- (void)takeWindowChromeInto:(DSStoreInfo *)info;

/* Implemented by the concrete viewers. */
- (BOOL)isSpatial;

/* "Always open in" was unticked: the view type is no longer kept for the
 * folder, until the user picks one again. */
- (void)forgetChosenViewType;

/* Writes the folder's settings: the stored ones, overlaid with the viewer
 * prefs, the live view options, the chrome and the live icon layout.
 * Returns what was written. */
- (DSStoreInfo *)saveFolderSettingsWithPrefs:(NSDictionary *)prefs;

/* FSNListViewOptionsDidChangeNotification: the user sorted or moved a
 * column, so the list options of the folder shown are written. */
- (void)listViewOptionsDidChange:(NSNotification *)notification;

/* Mode-specific hooks called from shared base methods; implemented by the
 * concrete viewer classes. */
- (void)updateDefaults;
- (void)updatePreviewPaneForCurrentType;
- (void)reloadFromNode:(FSNode *)anode;

- (void)deactivate;
- (void)deleteFiles;
- (void)duplicateFiles;
- (void)makeAliasFiles;
- (void)emptyTrash;
- (void)goBackwardInHistory;
- (void)goForwardInHistory;
- (void)hiddenFilesChanged:(NSArray *)paths;
- (void)hideDotsFileChanged:(BOOL)hide;
- (NSMutableArray *)history;
- (int)historyPosition;
- (int)inspectorPaneIndex;
- (BOOL)invalidated;
- (BOOL)isClosing;
- (BOOL)isInspectorShown;
- (NSArray *)lastSelection;
- (void)newFile;
- (void)newFolder;
- (void)nodeContentsWillChange:(NSDictionary *)info;
- (id)nodeView;
- (void)openSelectionAsFolder;
- (void)openSelectionWith;
- (void)previewPane:(GWViewerBrowserPreview *)pane didSelectInspectorAtIndex:(int)index;
- (void)recycleFiles;
- (void)reloadNodeContents;
- (void)scrollToBeginning;
- (void)setHistoryPosition:(int)pos;
- (void)setIconsPosition:(id)sender;
- (void)setIconsSize:(id)sender;
- (void)setInspectorPaneIndex:(int)index;
- (void)setInspectorShown:(BOOL)shown;
- (void)setLabelSize:(id)sender;
- (void)setOpened:(BOOL)opened repOfNode:(FSNode *)anode;
- (void)showAttributesInspector:(id)sender;
- (void)toggleInspector:(id)sender;
- (void)updateWindowTitle;
- (NSArray *)watchedNodes;
- (BOOL)windowShouldClose:(id)sender;
- (void)windowWillMiniaturize:(NSNotification *)aNotification;

@end
