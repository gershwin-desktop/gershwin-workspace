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
}

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
