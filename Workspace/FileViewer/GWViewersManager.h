/* GWViewersManager.h
 *  
 * Copyright (C) 2004-2013 Free Software Foundation, Inc.
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
 * Foundation, Inc., 31 Milk Street #960789 Boston, MA 02196 USA.
 */


#import <Foundation/Foundation.h>
#import "FSNodeRep.h"
#import "GWViewer.h"

#define BROWSING 0
#define SPATIAL  1

@class Workspace;
@class History;

@interface GWViewersManager : NSObject
{
  NSMutableArray *viewers;
  NSMutableArray *rootViewersKeys;
  BOOL orderingViewers;
  Workspace *gworkspace;
  History *historyWindow;
  NSMutableArray *spatialViewersHistory;
  int spvHistoryPos;
  BOOL settingHistoryPath;
  NSHelpManager *helpManager;
  NSAttributedString *bviewerHelp;
  NSAttributedString *sviewerHelp;
  NSNotificationCenter *nc;
}

+ (GWViewersManager *)viewersManager;


- (void)showViewers;

- (id)showRootViewer;

- (void)selectRepOfNode:(FSNode *)node
          inViewerWithBaseNode:(FSNode *)base;

- (void)selectRepsOfNodes:(NSArray *)nodes
          inViewerWithBaseNode:(FSNode *)base;
            

- (id)viewerOfType:(unsigned)vtype
          showType:(NSString *)stype
           forNode:(FSNode *)node
     showSelection:(BOOL)showsel
    closeOldViewer:(id)oldvwr
          forceNew:(BOOL)force;

/* First-class mode switch: replace a viewer window with one of the other
 * kind (BROWSING/SPATIAL) for the same folder — the new window inherits the
 * old one's frame and identity, and the old one is closed only after the
 * replacement is shown. */
- (id)replaceViewer:(id)oldvwr withViewerType:(unsigned)vtype;

- (id)viewerForNode:(FSNode *)node
          showType:(GWViewType)stype
     showSelection:(BOOL)showsel
          forceNew:(BOOL)force
	   withKey:(NSString *)key;

- (void)setBehaviour:(NSString *)behaviour
           forViewer:(id)aviewer;
           
- (NSArray *)viewersForBaseNode:(FSNode *)node;

- (id)viewerOfType:(unsigned)type
      withBaseNode:(FSNode *)node;

- (id)viewerWithBaseNode:(FSNode *)node;

- (id)viewerOfType:(unsigned)type
       showingNode:(FSNode *)node;

- (id)viewerShowingNode:(FSNode *)node;

- (id)rootViewer;

- (NSNumber *)nextRootViewerKey;

- (int)typeOfViewerForNode:(FSNode *)node;

- (id)parentOfSpatialViewer:(id)aviewer;

- (void)closeViewersForUnmountedPath:(NSString *)unmountedPath;

- (void)mountedVolumesDidChange;


- (void)viewerWillClose:(id)aviewer;

- (void)closeInvalidViewers:(NSArray *)vwrs;

- (void)selectedSpatialViewerChanged:(id)aviewer;

- (void)synchronizeSelectionInParentOfViewer:(id)aviewer;

- (void)viewer:(id)aviewer didShowNode:(FSNode *)node;

- (void)selectionChanged:(NSArray *)selection;

- (void)openSelectionInViewer:(id)viewer
                  closeSender:(BOOL)close;

/* Canonical "open one item" entry point.  Every open action (double-click,
 * Cmd-O, Open, Open as Folder, dock, desktop, Finder, DBus) funnels here.
 * The item opens itself: a folder opens a viewer (growing from the source
 * viewer's icon when available), everything else is handed to the system.
 * When asFolder is YES, packages (e.g. .app bundles) are opened as plain
 * folders instead of being launched. */
- (void)openNode:(FSNode *)node fromViewer:(id)viewer asFolder:(BOOL)asFolder;
- (void)openNode:(FSNode *)node fromViewer:(id)viewer;

// Window open animation support (spatial Finder-like window birth)
- (void)setPendingOpenAnimationRect:(NSRect)rect;
- (void)setPendingOpenAnimationRectFromFocusedViewerForNode:(FSNode *)node;
- (void)setWindowBirthRect:(NSRect)sourceRect
               targetRect:(NSRect)targetRect
            animationType:(int32_t)animationType
                 forWindow:(NSWindow *)window;

// Window close animation support (spatial window shrink).
// Resolves the folder's CURRENT on-screen representation by identity (not by
// a stored view) so the close animation shrinks the window into wherever the
// folder icon is right now.  A nil/NSZeroRect target means "no visible
// representation - use a plain fade".
- (NSRect)resolveIconScreenRectForNode:(FSNode *)node;

/* Resolve the folder's current icon rect for @p aviewer's window and ask the
 * WindowManager to play the close animation toward it (shrink+fade), or a
 * plain fade when no visible representation exists.  Called from
 * windowWillClose: while the window is still mapped. */
- (void)prepareCloseAnimationForViewer:(id)aviewer;
                   
- (void)openAsFolderSelectionInViewer:(id)viewer;

- (void)openWithSelectionInViewer:(id)viewer;


- (void)sortTypeDidChange:(NSNotification *)notif;

- (void)fileSystemWillChange:(NSNotification *)notif;

- (void)fileSystemDidChange:(NSNotification *)notif;

- (void)watcherNotification:(NSNotification *)notif;

- (void)thumbnailsDidChangeInPaths:(NSArray *)paths;

- (void)hideDotsFileDidChange:(BOOL)hide;

- (void)hiddenFilesDidChange:(NSArray *)paths;


- (BOOL)hasViewerWithWindow:(id)awindow;

- (id)viewerWithWindow:(id)awindow;

- (NSArray *)viewerWindows;

- (BOOL)orderingViewers;

- (void)updateDesktop;

- (void)updateDefaults;

@end


@interface GWViewersManager (History)

- (void)addNode:(FSNode *)node toHistoryOfViewer:(id)viewer;

- (void)removeDuplicatesInHistory:(NSMutableArray *)history
                         position:(int *)pos;
           
- (void)changeHistoryOwner:(id)viewer;

- (void)goToHistoryPosition:(int)pos 
                   ofViewer:(id)viewer;

- (void)goBackwardInHistoryOfViewer:(id)viewer;

- (void)goForwardInHistoryOfViewer:(id)viewer;

- (void)setPosition:(int)position
          inHistory:(NSMutableArray *)history
           ofViewer:(id)viewer;

@end
