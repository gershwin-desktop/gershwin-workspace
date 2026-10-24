/* GWViewerBase.m
 *
 * Shared implementation for the browsing (GWViewer) and spatial
 * (GWSpatialViewer) viewer kinds.  See GWViewerBase.h.
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

#import <AppKit/AppKit.h>
#import "GWViewerBase.h"
#import "GWViewerWindow.h"
#import "GWViewersManager.h"
#import "GWViewerBrowserPreview.h"
#import "Workspace.h"
#import "GWDesktopManager.h"
#import "FSNodeRep.h"
#import "FSNFunctions.h"
#import "FSNIconsView.h"
#import "FSNListView.h"
#import "DSStoreInfo.h"
#import "GWFolderViewOptions.h"
#import "GWViewSettingsManager.h"
#import "GWNavigationHistory.h"

@implementation GWViewerBase

- (void)dealloc
{
  RELEASE (pendingScrollPosition);
  RELEASE (appliedViewState);
  RELEASE (navigationHistory);
  [super dealloc];
}

/* Abstract hooks implemented by the concrete viewer classes (GWViewer and
 * GWSpatialViewer).  GWViewerBase is never instantiated directly, so these
 * raise if a subclass forgets to implement one. */
- (void)updateDefaults
{
  [NSException raise: NSInternalInconsistencyException
              format: @"%s not implemented by %@", __PRETTY_FUNCTION__, [self class]];
}

- (void)applyFolderViewOptions:(DSStoreInfo *)info includingScrollPosition:(BOOL)scroll
{
  if ([nodeView isKindOfClass: [FSNIconsView class]])
    {
      [GWFolderViewOptions applyIconViewOptionsOf: info
                                      toIconsView: nodeView
                          includingScrollPosition: scroll];
      if (scroll && [info hasScrollPosition])
        ASSIGN (pendingScrollPosition, [NSValue valueWithPoint: [info scrollPosition]]);
    }
  else if ([nodeView isKindOfClass: [FSNListView class]])
    {
      [GWFolderViewOptions applyListViewOptionsOf: info
                                     toDataSource: [nodeView dataSource]];
      if (scroll && [info hasListScrollPosition])
        {
          [GWFolderViewOptions applyListScrollPositionOf: info toListView: nodeView];
          ASSIGN (pendingScrollPosition, [NSValue valueWithPoint: [info listScrollPosition]]);
        }
    }
  ASSIGN (appliedViewState, [self currentViewState]);
}

- (NSDictionary *)currentViewState
{
  if ([nodeView isKindOfClass: [FSNIconsView class]])
    return [GWFolderViewOptions iconViewStateOf: nodeView];
  if ([nodeView isKindOfClass: [FSNListView class]])
    return [GWFolderViewOptions listViewStateOf: [nodeView dataSource]];
  return nil;
}

- (void)takeWindowChromeInto:(DSStoreInfo *)info
{
}

- (BOOL)isSpatial
{
  [self subclassResponsibility: _cmd];
  return NO;
}

- (void)forgetChosenViewType
{
  viewTypeChosenByUser = NO;
}

/* Finder's windows without a toolbar are its spatial ones [decision A].
 * Only a window of another kind than the folder would open in records it:
 * a folder merely opened in the usual kind of window keeps no bwsp of its
 * own for that, as Finder writes none for an untouched window [O:E8]. */
- (void)takeWindowKindInto:(DSStoreInfo *)info
{
  BOOL spatial = [self isSpatial];
  BOOL wouldOpenSpatially =
    [GWFolderViewOptions opensSpatially: info
                              byDefault: ([gworkspace defaultViewerType] == SPATIAL)];

  if ([info hasShowToolbar] || wouldOpenSpatially != spatial)
    {
      [info setShowToolbar: !spatial];
      [info setHasShowToolbar: YES];
    }
}

- (DSStoreInfo *)saveFolderSettingsWithPrefs:(NSDictionary *)prefs
{
  GWViewSettingsManager *sm =
    [GWViewSettingsManager managerForDirectoryPath: [baseNode path]];
  /* Read first, so the write keeps icon positions persisted since the
   * window opened and every record Finder wrote. */
  DSStoreInfo *info = [sm readSettings];
  NSMutableDictionary *folderPrefs =
    [NSMutableDictionary dictionaryWithDictionary: [GWFolderViewOptions folderPrefsFromViewerPrefs: prefs]];

  if (viewTypeChosenByUser == NO && [info hasViewStyle] == NO)
    {
      /* Without a per-folder view Finder uses its last used one [O:E5];
       * storing ours for every folder opened would pin them all. */
      [folderPrefs removeObjectForKey: @"viewtype"];
    }
  [info takeValuesFromViewerPrefs: folderPrefs];

  /* The node view of a browsing window may show another folder by now;
   * its options are not this folder's. */
  if ([[[nodeView shownNode] path] isEqual: [baseNode path]])
    {
      /* Options the user did not touch stay as stored: taking them all
       * would create an icvp or lsvp for every folder opened, and turn
       * values from records Finder ignores into ones it reads. */
      BOOL changed = ![[self currentViewState] isEqual: appliedViewState];

      if (changed && [nodeView isKindOfClass: [FSNIconsView class]])
        {
          [GWFolderViewOptions takeIconViewOptionsOf: nodeView into: info];
        }
      else if (changed && [nodeView isKindOfClass: [FSNListView class]])
        {
          [GWFolderViewOptions takeListViewOptionsOf: [nodeView dataSource] into: info];
          [GWFolderViewOptions takeListScrollPositionOf: nodeView into: info];
        }

      /* The live layout, not whatever a stale .DS_Store (possibly with
       * foreign colliding positions) had. */
      if ([nodeView respondsToSelector: @selector(liveIconPositions)])
        {
          NSDictionary *live = [nodeView liveIconPositions];

          if ([live count] > 0)
            [info setLiveIconPositions: live];
        }
    }
  [self takeWindowChromeInto: info];
  [self takeWindowKindInto: info];

  [sm writeSettings: info];
  return info;
}

- (void)listViewOptionsDidChange:(NSNotification *)notification
{
  GWViewSettingsManager *sm;
  DSStoreInfo *info;

  if ([notification object] != nodeView || [nodeView shownNode] == nil)
    return;

  sm = [GWViewSettingsManager managerForDirectoryPath: [[nodeView shownNode] path]];
  info = [sm readSettings];
  [GWFolderViewOptions takeListViewOptionsOf: [nodeView dataSource] into: info];
  [GWFolderViewOptions takeListScrollPositionOf: nodeView into: info];
  [sm writeSettings: info];
}

- (void)updatePreviewPaneForCurrentType
{
  [NSException raise: NSInternalInconsistencyException
              format: @"%s not implemented by %@", __PRETTY_FUNCTION__, [self class]];
}

- (void)reloadFromNode:(FSNode *)anode
{
  [NSException raise: NSInternalInconsistencyException
              format: @"%s not implemented by %@", __PRETTY_FUNCTION__, [self class]];
}

- (void)deactivate
{
  [vwrwin close];
}

- (void)deleteFiles
{
  NSArray *selection = [nodeView selectedNodes];

  if (selection && [selection count]) {
    if ([nodeView isSingleNode]) {
      [gworkspace deleteFiles];
    } else if ([selection isEqual: baseNodeArray] == NO) {
      [gworkspace deleteFiles];
    }
  }
}

- (void)duplicateFiles
{
  if ([[baseNode path] isEqual: [gworkspace trashPath]] == NO) {
    NSArray *selection = [nodeView selectedNodes];

    if (selection && [selection count]) {
      if ([nodeView isSingleNode]) {
        [gworkspace duplicateFiles];
      } else if ([selection isEqual: baseNodeArray] == NO) {
        [gworkspace duplicateFiles];
      }
    }
  } else {
    NSRunAlertPanel(nil, 
                  NSLocalizedString(@"You can't duplicate files in the Recycler!", @""),
					        NSLocalizedString(@"OK", @""), 
                  nil, 
                  nil);  
  }
}

- (void)makeAliasFiles
{
  if ([[baseNode path] isEqual: [gworkspace trashPath]] == NO) {
    NSArray *selection = [nodeView selectedNodes];

    if (selection && [selection count]) {
      if ([nodeView isSingleNode]) {
        [gworkspace makeAliasFiles:nil];
      } else if ([selection isEqual: baseNodeArray] == NO) {
        [gworkspace makeAliasFiles:nil];
      }
    }
  } else {
    NSRunAlertPanel(nil,
                  NSLocalizedString(@"You can't create aliases in the Recycler!", @""),
					        NSLocalizedString(@"OK", @""), 
                  nil, 
                  nil);  
  }
}

- (void)emptyTrash
{
  [gworkspace emptyTrash: nil];
}

- (void)goBackwardInHistory
{
  [manager goBackwardInHistoryOfViewer: self];
}

- (void)goForwardInHistory
{
  [manager goForwardInHistoryOfViewer: self];
}

- (void)hiddenFilesChanged:(NSArray *)paths
{
  [self reloadFromNode: baseNode];
}

- (void)hideDotsFileChanged:(BOOL)hide
{
  [self reloadFromNode: baseNode];
}

- (GWNavigationHistory *)navigationHistory
{
  if (navigationHistory == nil) {
    navigationHistory = [GWNavigationHistory new];
  }
  return navigationHistory;
}

- (NSMutableArray *)history
{
  return [[self navigationHistory] items];
}

- (int)historyPosition
{
  return (int)[[self navigationHistory] position];
}

- (int)inspectorPaneIndex
{
  return inspectorPane;
}

- (BOOL)invalidated
{
  return invalidated;
}

- (BOOL)isClosing
{
  return closing;
}

- (BOOL)isInspectorShown
{
  return showInspector;
}

- (NSArray *)lastSelection
{
  return lastSelection;
}

- (void)newFile
{
  if ([[baseNode path] isEqual: [gworkspace trashPath]] == NO) {
    [gworkspace newObjectAtPath: [[nodeView shownNode] path] 
                    isDirectory: NO];
  } else {
    NSRunAlertPanel(nil, 
                  NSLocalizedString(@"You can't create a new file in the Recycler!", @""),
					        NSLocalizedString(@"OK", @""), 
                  nil, 
                  nil);  
  }
}

- (void)newFolder
{
  if ([[baseNode path] isEqual: [gworkspace trashPath]] == NO) {
    [gworkspace newObjectAtPath: [[nodeView shownNode] path] 
                    isDirectory: YES];
  } else {
    NSRunAlertPanel(nil, 
                  NSLocalizedString(@"You can't create a new folder in the Recycler!", @""),
					        NSLocalizedString(@"OK", @""), 
                  nil, 
                  nil);  
  }
}

- (void)nodeContentsWillChange:(NSDictionary *)info
{
  [nodeView nodeContentsWillChange: info];
}

- (id)nodeView
{
  return nodeView;
}

/* A view that shows one folder at a time (icons, list) moves away from
 * baseNode when the user opens a subfolder in place, so baseNode is only
 * where the window started.  Everything the user reads as "this window's
 * folder" - title, Enclosing Folder - has to follow what is shown instead. */
- (FSNode *)shownFolderNode
{
  if ([nodeView isSingleNode])
    {
      return [nodeView shownNode];
    }

  return baseNode;
}

/* Computed from the path: -[FSNode parent] is only set for nodes that were
 * created from their parent, which a folder opened by path is not. */
- (FSNode *)enclosingFolderNode
{
  NSString *path = [[self shownFolderNode] path];
  NSString *parentPath = [path stringByDeletingLastPathComponent];

  if (path == nil || [parentPath isEqual: path])
    {
      return nil;
    }

  return [FSNode nodeWithPath: parentPath];
}

/* What a spatial window does: each folder has a window of its own. */
- (void)openEnclosingFolderClosingViewer:(BOOL)close
{
  FSNode *parentNode = [self enclosingFolderNode];
  FSNode *dskNode = [[[Workspace gworkspace] desktopManager] desktopNode];

  if (parentNode == nil
      || (dskNode && [[parentNode path] isEqual: [dskNode path]]))
    {
      return;
    }

  [manager viewerOfType: SPATIAL
               showType: nil
                forNode: parentNode
          showSelection: NO
         closeOldViewer: close ? self : nil
               forceNew: NO];
}

- (void)setWindowTitleForNode:(FSNode *)node
{
  if ([[node path] isEqual: path_separator()])
    {
      [vwrwin setTitle: NSLocalizedString(@"System Disk", @"")];
    }
  else
    {
      [vwrwin setTitle: [node name]];
    }
}

- (void)openSelectionAsFolder
{
  if ([[baseNode path] isEqual: [gworkspace trashPath]] == NO) {
    [manager openAsFolderSelectionInViewer: self];
  } else {
    NSRunAlertPanel(nil, 
                  NSLocalizedString(@"You can't do this in the Recycler!", @""),
					        NSLocalizedString(@"OK", @""), 
                  nil, 
                  nil);  
  }
}

- (void)openSelectionWith
{
  if ([[baseNode path] isEqual: [gworkspace trashPath]] == NO) {
    [manager openWithSelectionInViewer: self];
  } else {
    NSRunAlertPanel(nil, 
                  NSLocalizedString(@"You can't do this in the Recycler!", @""),
					        NSLocalizedString(@"OK", @""), 
                  nil, 
                  nil);  
  }
}

- (void)previewPane:(GWViewerBrowserPreview *)pane
  didSelectInspectorAtIndex:(int)index
{
  if (inspectorPane != index)
    {
      inspectorPane = index;
      [self updateDefaults];
    }
}

- (void)recycleFiles
{
  if ([[baseNode path] isEqual: [gworkspace trashPath]] == NO) {
    NSArray *selection = [nodeView selectedNodes];

    if (selection && [selection count]) {
      if ([nodeView isSingleNode]) {
        [gworkspace moveToTrash];
      } else if ([selection isEqual: baseNodeArray] == NO) {
        [gworkspace moveToTrash];
      }
    }
  }
}

- (void)reloadNodeContents
{
  [nodeView reloadContents];
}

- (void)scrollToBeginning
{
  if ([nodeView isSingleNode]) {
    [nodeView scrollSelectionToVisible];
  }
  if (pendingScrollPosition && [nodeView respondsToSelector: @selector(setScrollPosition:)])
    {
      [nodeView setScrollPosition: [pendingScrollPosition pointValue]];
    }
  DESTROY (pendingScrollPosition);
}

- (void)setHistoryPosition:(int)pos
{
  [[self navigationHistory] setPosition: pos];
}

- (void)setIconsPosition:(id)sender
{
  if ([nodeView respondsToSelector: @selector(setIconPosition:)]) {
    NSString *title = [sender title];
    
    if ([title isEqual: NSLocalizedString(@"Left", @"")]) {
      [(id <FSNodeRepContainer>)nodeView setIconPosition: NSImageLeft];
    } else {
      [(id <FSNodeRepContainer>)nodeView setIconPosition: NSImageAbove];
    }
    
    [self scrollToBeginning];
    [nodeView updateNodeInfo: YES];
  }
}

- (void)setIconsSize:(id)sender
{
  if ([nodeView respondsToSelector: @selector(setIconSize:)]) {
    [(id <FSNodeRepContainer>)nodeView setIconSize: [[sender title] intValue]];
    [self scrollToBeginning];
    [nodeView updateNodeInfo: YES];
  }
}

- (void)setInspectorPaneIndex:(int)index
{
  if (inspectorPane != index)
    {
      inspectorPane = index;
      if (previewPane && [previewPane respondsToSelector: @selector(selectInspectorAtIndex:)])
        {
          [previewPane selectInspectorAtIndex: index];
        }
    }
}

- (void)setInspectorShown:(BOOL)shown
{
  if (showInspector != shown)
    {
      showInspector = shown;
      [self updatePreviewPaneForCurrentType];
      [vwrwin display];
      [self updateDefaults];
    }
}

- (void)setLabelSize:(id)sender
{
  if ([nodeView respondsToSelector: @selector(setLabelTextSize:)]) {
    [nodeView setLabelTextSize: [[sender title] intValue]];
    [self scrollToBeginning];
    [nodeView updateNodeInfo: YES];
  }
}

- (void)setOpened:(BOOL)opened 
        repOfNode:(FSNode *)anode
{
  id rep = [nodeView repOfSubnode: anode];

  if (rep) {
    [rep setOpened: opened];
    
    if ([nodeView isSingleNode]) { 
      [rep select];
    }
  }
}

- (void)showAttributesInspector:(id)sender
{
  [gworkspace showAttributesInspector: sender];
}

- (void)toggleInspector:(id)sender
{
  [self setInspectorShown: !showInspector];
}

- (void)updateWindowTitle
{
  /* Intentionally empty - declared in header but not used in this implementation */
}

- (NSArray *)watchedNodes
{
  return watchedNodes;
}

- (BOOL)windowShouldClose:(id)sender
{
	return YES;
}

- (void)windowWillMiniaturize:(NSNotification *)aNotification
{
  NSImage *image = [fsnodeRep iconOfSize: 48 forNode: baseNode];

  [vwrwin setMiniwindowImage: image];
  [vwrwin setMiniwindowTitle: [baseNode name]];
}

@end
