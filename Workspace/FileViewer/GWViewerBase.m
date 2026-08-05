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
#import "FSNodeRep.h"
#import "FSNFunctions.h"

@implementation GWViewerBase

/* Abstract hooks implemented by the concrete viewer classes (GWViewer and
 * GWSpatialViewer).  GWViewerBase is never instantiated directly, so these
 * raise if a subclass forgets to implement one. */
- (void)updateDefaults
{
  [NSException raise: NSInternalInconsistencyException
              format: @"%s not implemented by %@", __PRETTY_FUNCTION__, [self class]];
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

- (NSMutableArray *)history
{
  if (!history) {
    history = [NSMutableArray new];
  }
  return history;
}

- (int)historyPosition
{
  return historyPosition;
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
}

- (void)setHistoryPosition:(int)pos
{
  historyPosition = pos;
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
  [manager updateDesktop];
	return YES;
}

- (void)windowWillMiniaturize:(NSNotification *)aNotification
{
  NSImage *image = [fsnodeRep iconOfSize: 48 forNode: baseNode];

  [vwrwin setMiniwindowImage: image];
  [vwrwin setMiniwindowTitle: [baseNode name]];
}

@end
