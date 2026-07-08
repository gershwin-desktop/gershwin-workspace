/* GWViewersManager.m
 *  
 * Copyright (C) 2004-2016 Free Software Foundation, Inc.
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

#import <AppKit/AppKit.h>
#include <GNUstepGUI/GSDisplayServer.h>
#ifdef __linux__
#include <X11/Xlib.h>
#include <X11/Xatom.h>
#include <stdint.h>
#endif
#import "GWViewersManager.h"
#import "GWViewer.h"
#import "GWSpatialViewer.h"
#import "GWViewerWindow.h"
#import "GWViewerPrefs.h"
#import "History.h"
#import "FSNFunctions.h"
#import "Workspace.h"
#import "GWDesktopManager.h"
#import "NetworkVolumeManager.h"


static GWViewersManager *vwrsmanager = nil;

@implementation GWViewersManager
{
  NSRect pendingOpenAnimationRect;
  BOOL hasPendingOpenAnimationRect;
}

+ (GWViewersManager *)viewersManager
{
  if (vwrsmanager == nil)
    {
      vwrsmanager = [[GWViewersManager alloc] init];
    }	
  return vwrsmanager;
}

- (void)dealloc
{
  [[NSDistributedNotificationCenter defaultCenter] removeObserver: self];
  [nc removeObserver: self];
  RELEASE (viewers);
  RELEASE (bviewerHelp);
    
  [super dealloc];
}

- (id)init
{
  self = [super init];
  
  if (self)
    {
      NSNotificationCenter *wsnc;
      
      gworkspace = [Workspace gworkspace];
      helpManager = [NSHelpManager sharedHelpManager];
      wsnc = [[NSWorkspace sharedWorkspace] notificationCenter];
      ASSIGN (bviewerHelp, [gworkspace contextHelpFromName: @"BViewer.rtfd"]);
      
      viewers = [NSMutableArray new];
      orderingViewers = NO;
      
      historyWindow = [gworkspace historyWindow]; 
      nc = [NSNotificationCenter defaultCenter];
      
      [nc addObserver: self 
             selector: @selector(fileSystemWillChange:) 
                 name: @"GWFileSystemWillChangeNotification"
               object: nil];
      
      [nc addObserver: self 
             selector: @selector(fileSystemDidChange:) 
                 name: @"GWFileSystemDidChangeNotification"
               object: nil];
      
      [nc addObserver: self 
             selector: @selector(watcherNotification:) 
                 name: @"GWFileWatcherFileDidChangeNotification"
               object: nil];    
      
      [[NSDistributedNotificationCenter defaultCenter] addObserver: self 
                                                          selector: @selector(sortTypeDidChange:) 
                                                              name: @"GWSortTypeDidChangeNotification"
                                                            object: nil];

      // should perhaps volume notification be distributed?
      [wsnc addObserver: self 
               selector: @selector(newVolumeMounted:) 
                   name: NSWorkspaceDidMountNotification
                 object: nil];
      
      
      [wsnc addObserver: self 
               selector: @selector(mountedVolumeWillUnmount:) 
                   name: NSWorkspaceWillUnmountNotification
                 object: nil];

      [wsnc addObserver: self 
               selector: @selector(mountedVolumeDidUnmount:) 
                   name: NSWorkspaceDidUnmountNotification
                 object: nil];
      
      [[FSNodeRep sharedInstance] setLabelWFactor: 9.0];
    }
  
  return self;
}


- (void)showViewers
{
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];  
  NSArray *viewersInfo = [defaults objectForKey: @"viewersinfo"];

  if (viewersInfo && [viewersInfo count])
    {
      NSUInteger i;
    
      for (i = 0; i < [viewersInfo count]; i++)
        {
          NSDictionary *dict = [viewersInfo objectAtIndex: i];
          NSString *path = [dict objectForKey: @"path"];
          FSNode *node = [FSNode nodeWithPath: path];
	  NSString *key = [dict objectForKey: @"key"];
    
          if (node && [node isValid])
            {
              [self viewerForNode: node
                         showType: 0
                    showSelection: YES
                         forceNew: YES
		          withKey: key];
            }
        }

    }
  else
    {
      [self showRootViewer];
  }
}

- (id)showRootViewer
{
  NSString *path = path_separator();
  FSNode *node = [FSNode nodeWithPath: path];
  id viewer = [self rootViewer];
  
  if (viewer == nil)
    {
  
      viewer = [self viewerForNode: node
		     showType: 0
                     showSelection: YES
		     forceNew: NO
		     withKey: nil];
    }
  else
    {
      if ([[viewer win] isVisible] == NO)
        {
          [viewer activate];
        }
      else
        {
          viewer = [self viewerForNode: node
                              showType: 0
                         showSelection: YES
                              forceNew: YES
			       withKey: nil];
        }
    }
  
  return viewer;
}

- (void)selectRepOfNode:(FSNode *)node
   inViewerWithBaseNode:(FSNode *)base
{
  [self selectRepsOfNodes: [NSArray arrayWithObject: node]
     inViewerWithBaseNode: base];
}

- (void)selectRepsOfNodes:(NSArray *)nodes
   inViewerWithBaseNode:(FSNode *)base
{
  BOOL inRootViewer = [[base path] isEqual: path_separator()];
  id viewer = nil;
  NSMutableArray *selection = [NSMutableArray array];
  NSUInteger i;
  
  for (i = 0; i < [nodes count]; i++) {
    FSNode *node = [nodes objectAtIndex: i];
    if ([base isEqual: node] || ([node isSubnodeOfNode: base] == NO)) {
      continue;
    }
    [selection addObject: node];
  }
  
  if (inRootViewer)
    {  
      viewer = [self rootViewer];
    
      if (viewer == nil)
        {
          viewer = [self showRootViewer];
        }  
    }
  else
    {
      viewer = [self viewerForNode : base
                           showType: 0
                      showSelection: NO
                           forceNew: NO
		            withKey: nil];
    } 
  
  if ([selection count] > 0)
    {
      [[viewer nodeView] selectRepsOfSubnodes: selection];  
    }
}

/* Single creation path for both viewer kinds.  Owns, in one place: window
 * alloc, the class-specific init, replace-in-place frame inheritance (applied
 * BEFORE any display, so a replacement never flashes at the init-chosen
 * position), the pending birth-animation handoff, ownership transfer to
 * `viewers` (the sole owner), help-context registration, and activation.
 * inheritedFrame = NSZeroRect means "no frame to inherit". */
- (id)createViewerOfType:(unsigned)vtype
                 forNode:(FSNode *)node
         browserShowType:(GWViewType)btype
         spatialShowType:(NSString *)sstype
           showSelection:(BOOL)showsel
                 withKey:(NSString *)key
          inheritedFrame:(NSRect)inheritedFrame
{
  GWViewerWindow *win = [GWViewerWindow new];
  id viewer;

  [win setReleasedWhenClosed: NO];

  if (vtype == SPATIAL)
    {
      viewer = [[GWSpatialViewer alloc] initForNode: node
                                           inWindow: win
                                           showType: sstype
                                      showSelection: showsel];
    }
  else
    {
      viewer = [[GWViewer alloc] initForNode: node
                                    inWindow: win
                                    showType: btype
                               showSelection: showsel
                                     withKey: key];
    }

  if (viewer == nil)
    {
      /* Consume the pending animation rect even on failure, so it can't leak
       * into the next window creation as a stale birth-animation source. */
      hasPendingOpenAnimationRect = NO;
      [win release];
      return nil;
    }

  if (!NSIsEmptyRect(inheritedFrame))
    [win setFrame: inheritedFrame display: NO];

  if (hasPendingOpenAnimationRect)
    {
      NSRect endFrame = [win frame];
      NSRect startFrame = pendingOpenAnimationRect;

      hasPendingOpenAnimationRect = NO;

      if (startFrame.size.width < 16) startFrame.size.width = 16;
      if (startFrame.size.height < 16) startFrame.size.height = 16;

      [win setFrame: endFrame display: NO];

      /* X property the WindowManager reads to run the birth animation when
       * -activate below maps the window. */
      [self setWindowBirthRect: startFrame
                    targetRect: endFrame
                 animationType: 0   // GSWindowBirthAnimationOpen
                     forWindow: win];
    }

  [viewers addObject: viewer];
  [win release];
  [viewer release];

  /* bviewerHelp is browser-window help; spatial windows have none (yet). */
  if (vtype != SPATIAL)
    [helpManager setContextHelp: bviewerHelp
                      forObject: [[viewer win] contentView]];

  [viewer activate];

  return viewer;
}

- (id)viewerForNode:(FSNode *)node
          showType:(GWViewType)stype
     showSelection:(BOOL)showsel
          forceNew:(BOOL)force
	   withKey:(NSString *)key
{
  id viewer = [self viewerWithBaseNode: node];

  if ((viewer == nil) || force)
    {
      viewer = [self createViewerOfType: BROWSING
                                forNode: node
                        browserShowType: stype
                        spatialShowType: nil
                          showSelection: showsel
                                withKey: key
                         inheritedFrame: NSZeroRect];
    }
  else
    {
      [viewer activate];
    }

  return viewer;
}

- (void)setPendingOpenAnimationRect:(NSRect)rect
{
  NSDebugLLog(@"gwspace", @"[Animation] setPendingOpenAnimationRect called: origin={%.0f,%.0f} size={%.0fx%.0f}",
        rect.origin.x, rect.origin.y, rect.size.width, rect.size.height);
  pendingOpenAnimationRect = rect;
  hasPendingOpenAnimationRect = !NSEqualRects(rect, NSZeroRect);
  NSDebugLLog(@"gwspace", @"[Animation] hasPendingOpenAnimationRect = %d", hasPendingOpenAnimationRect);
}

- (NSArray *)viewersForBaseNode:(FSNode *)node
{
  NSMutableArray *vwrs = [NSMutableArray array];
  NSUInteger i;
  
  for (i = 0; i < [viewers count]; i++) {
    id viewer = [viewers objectAtIndex: i];
    
    if ([[viewer baseNode] isEqual: node]) {
      [vwrs addObject: viewer];
    }
  }
  
  return vwrs;
}

- (id)viewerWithBaseNode:(FSNode *)node
{
  NSUInteger i;

  for (i = 0; i < [viewers count]; i++)
    {
      id viewer = [viewers objectAtIndex: i];

      if ([[viewer baseNode] isEqual: node])
        {
          return viewer;
        }
    }

  return nil;
}

- (id)viewerShowingNode:(FSNode *)node
{
  NSUInteger i;
  
  for (i = 0; i < [viewers count]; i++)
    {
      id viewer = [viewers objectAtIndex: i];

      if ([viewer isShowingNode: node])
        {
          return viewer;
        }
    }
  
  return nil;
}

- (id)rootViewer
{
  NSUInteger i;

  for (i = 0; i < [viewers count]; i++)
    {
      id viewer = [viewers objectAtIndex: i];

      if ([viewer isFirstRootViewer])
	{
	  return viewer;
	}
    }

  return nil;
}


- (void)viewerWillClose:(id)aviewer
{
  FSNode *node = [aviewer baseNode];
  NSArray *watchedNodes = [aviewer watchedNodes];
  NSUInteger i;

  
  if ([node isValid] == NO)
    {
      NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];  
      NSString *prefsname;
      NSDictionary *vwrprefs;

      prefsname = [aviewer defaultsKey];

      vwrprefs = [defaults dictionaryForKey: prefsname];
      if (vwrprefs)
        {
          [defaults removeObjectForKey: prefsname];
        } 
    
      [NSWindow removeFrameUsingName: prefsname]; 
    }
  
  for (i = 0; i < [watchedNodes count]; i++)
    [gworkspace removeWatcherForPath: [[watchedNodes objectAtIndex: i] path]];

  if (aviewer == [historyWindow viewer])
    [self changeHistoryOwner: nil];

  [helpManager removeContextHelpForObject: [[aviewer win] contentView]];
  if ([viewers containsObject: aviewer]) {
    [viewers removeObject: aviewer];
  }
}

- (void)closeInvalidViewers:(NSArray *)vwrs
{
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
  NSUInteger i, j;

  for (i = 0; i < [vwrs count]; i++)
    {
      id viewer = [vwrs objectAtIndex: i];
      NSString *vpath = [[viewer baseNode] path];
      NSArray *watchedNodes = [viewer watchedNodes];
      /* The node is gone: purge the prefs of both window kinds for the path
       * (browser and spatial keys are separate since the key split). */
      NSString *keys[2] = { GWViewerPrefsKey(vpath, NO, nil, NO),
                            GWViewerPrefsKey(vpath, YES, nil, NO) };
      NSUInteger k;

      for (k = 0; k < 2; k++)
        {
          if ([defaults dictionaryForKey: keys[k]])
            [defaults removeObjectForKey: keys[k]];

          [NSWindow removeFrameUsingName: keys[k]];
        }
    
      for (j = 0; j < [watchedNodes count]; j++)
        [gworkspace removeWatcherForPath: [[watchedNodes objectAtIndex: j] path]];
    }
      
  for (i = 0; i < [vwrs count]; i++)
    {
      id viewer = [vwrs objectAtIndex: i];

      if (viewer == [historyWindow viewer])
        [self changeHistoryOwner: nil];

      [viewer deactivate];
      [helpManager removeContextHelpForObject: [[viewer win] contentView]];
    }

  /* Remove all viewers at once after the loop, to avoid re-entrancy
   * issues from run loop events triggered by deactivate. */
  for (i = 0; i < [vwrs count]; i++)
    {
      id viewer = [vwrs objectAtIndex: i];
      [viewers removeObject: viewer];
    }
}

- (void)selectionChanged:(NSArray *)selection
{
  if (orderingViewers == NO) {
    [gworkspace selectionChanged: selection];
  }
}

- (void)openSelectionInViewer:(id)viewer
                  closeSender:(BOOL)close
{
  NSArray *selreps = [[viewer nodeView] selectedReps];
  NSUInteger count = [selreps count];
  NSUInteger i;
    
  if (count > MAX_FILES_TO_OPEN_DIALOG)
    {
      NSString *msg1 = NSLocalizedString(@"Are you sure you want to open", @"");
      NSString *msg2 = NSLocalizedString(@"items?", @"");

      if (NSRunAlertPanel(nil,
                          [NSString stringWithFormat: @"%@ %"PRIuPTR" %@", msg1, count, msg2],
                          NSLocalizedString(@"Cancel", @""),
                          NSLocalizedString(@"Yes", @""),
                          nil))
        {
          return;
        }
    }
    
  for (i = 0; i < count; i++)
    {
      FSNode *node = [[selreps objectAtIndex: i] node];
      
      if ([node hasValidPath])
        {            
          NS_DURING
            {
              /* Network services: mount instead of treating as directory */
              if ([node respondsToSelector: @selector(isNetworkService)]
                  && [node performSelector: @selector(isNetworkService)])
                {
                  NSString *mountPoint = [node performSelector: @selector(openNetworkService)];
                  if (mountPoint) {
                    FSNode *target = [FSNode nodeWithPath: mountPoint];
                    if (target && [target isValid]) {
                      int defaultType = [gworkspace defaultViewerType];
                      if (defaultType == SPATIAL) {
                        [self viewerOfType: SPATIAL
                                  showType: nil
                                   forNode: target
                             showSelection: NO
                            closeOldViewer: nil
                                  forceNew: NO];
                      } else {
                        [self viewerForNode: target
                                   showType: 0
                              showSelection: NO
                                   forceNew: NO
                                    withKey: nil];
                      }
                    }
                  }
                }
              else if ([node isDirectory])
                {
                  if ([node isPackage])
                    {    
                      if ([node isApplication] == NO)
                        [gworkspace openFile: [node path]];
                      else
                        [[NSWorkspace sharedWorkspace] launchApplication: [node path]];
                    }
                  else
                    {
                      // Use the default viewer type preference
                      int defaultType = [gworkspace defaultViewerType];
                      NSDebugLLog(@"gwspace", @"openSelectionInViewer: using default viewer type %d for folder %@", defaultType, [node path]);

                      if (defaultType == SPATIAL) {
                        [self viewerOfType: SPATIAL
                                  showType: nil
                                   forNode: node
                             showSelection: NO
                            closeOldViewer: nil
                                  forceNew: NO];
                      } else {
                        [self viewerForNode: node
                                   showType: 0
                              showSelection: NO
                                   forceNew: NO
                                    withKey: nil];
                      }
                    } 
                }
              else if ([node isPlain])
                {        
                  [gworkspace openFile: [node path]];
                }
            }
          NS_HANDLER
            {
              NSRunAlertPanel(NSLocalizedString(@"error", @""), 
                              [NSString stringWithFormat: @"%@ %@!", 
                                        NSLocalizedString(@"Can't open ", @""), [node name]],
                              NSLocalizedString(@"OK", @""), 
                              nil, 
                              nil);                                     
            }
          NS_ENDHANDLER
            
            }
      else
        {
          NSRunAlertPanel(NSLocalizedString(@"error", @""), 
                          [NSString stringWithFormat: @"%@ %@!", 
                                    NSLocalizedString(@"Can't open ", @""), [node name]],
                          NSLocalizedString(@"OK", @""), 
                          nil, 
                          nil);                                     
        }
    }
  
  if (close)
    {
      [[viewer win] close]; 
    }
}

- (void)openAsFolderSelectionInViewer:(id)viewer
{
  NSArray *selnodes = [[viewer nodeView] selectedNodes];
  BOOL force = NO;
  NSUInteger i;
  
  if ((selnodes == nil) || ([selnodes count] == 0))
    {
      selnodes = [NSArray arrayWithObject: [[viewer nodeView] shownNode]];
      force = YES;
    }
  
  for (i = 0; i < [selnodes count]; i++)
    {
      FSNode *node = [selnodes objectAtIndex: i];
      
      /* Network services: mount instead of treating as directory */
      if ([node respondsToSelector: @selector(isNetworkService)]
          && [node performSelector: @selector(isNetworkService)])
        {
          NSString *mountPoint = [node performSelector: @selector(openNetworkService)];
          if (mountPoint) {
            FSNode *target = [FSNode nodeWithPath: mountPoint];
            if (target && [target isValid]) {
              int defaultType = [gworkspace defaultViewerType];
              if (defaultType == SPATIAL) {
                [self viewerOfType: SPATIAL
                          showType: nil
                           forNode: target
                     showSelection: NO
                    closeOldViewer: nil
                          forceNew: force];
              } else {
                [self viewerForNode: target
                           showType: 0
                      showSelection: NO
                           forceNew: force
                            withKey: nil];
              }
            }
          }
        }
      // Use the default viewer type preference
      else if ([node isDirectory])
        {
          int defaultType = [gworkspace defaultViewerType];
          NSDebugLLog(@"gwspace", @"openAsFolderSelectionInViewer: using default viewer type %d for folder %@", defaultType, [node path]);

          if (defaultType == SPATIAL) {
            [self viewerOfType: SPATIAL
                      showType: nil
                       forNode: node
                 showSelection: NO
                closeOldViewer: nil
                      forceNew: force];
          } else {
            [self viewerForNode: node
                       showType: 0
                  showSelection: NO
                       forceNew: force
                        withKey: nil];
          }
        }
      else if ([node isPlain])
        {        
          [gworkspace openFile: [node path]];
        }
    }
}

- (void)openWithSelectionInViewer:(id)viewer
{
  [gworkspace openSelectedPathsWith];
}

- (void)sortTypeDidChange:(NSNotification *)notif
{
  NSString *notifPath = [notif object];
  NSUInteger i;

  for (i = 0; i < [viewers count]; i++)
    {
      [[[viewers objectAtIndex: i] nodeView] sortTypeChangedAtPath: notifPath];
    }
}

- (void)fileSystemWillChange:(NSNotification *)notif
{
  NSDictionary *opinfo = (NSDictionary *)[notif object];  
  NSMutableArray *viewersToClose = [NSMutableArray array];
  NSString *operation = [opinfo objectForKey: @"operation"];
  int i;

  /* Handle unmount operations: close all viewers on the unmounted volume */
  if ([operation isEqual: @"UnmountOperation"]) {
    NSString *unmountedPath = [opinfo objectForKey: @"unmounted"];
    if (unmountedPath) {
      for (i = 0; i < [viewers count]; i++) {
        id viewer = [viewers objectAtIndex: i];
        if ([viewer invalidated] == NO) {
          NSString *viewerPath = [[viewer baseNode] path];
          if ([viewerPath isEqual: unmountedPath] || isSubpathOfPath(unmountedPath, viewerPath)) {
            [viewer invalidate];
            [viewersToClose addObject: viewer];
          }
        }
      }
      [self closeInvalidViewers: viewersToClose];
      return;
    }
  }

  for (i = 0; i < [viewers count]; i++) {
    id viewer = [viewers objectAtIndex: i];
    
    if ([viewer involvedByFileOperation: opinfo]) {
      if ([[viewer baseNode] willBeValidAfterFileOperation: opinfo] == NO) {
        [viewer invalidate];
        [viewersToClose addObject: viewer];
        
      } else { 
        [viewer nodeContentsWillChange: opinfo];
      }
    }
    
    if ([viewer invalidated] == NO) {
      id shelf = [viewer shelf];
      
      if (shelf) {
        [shelf nodeContentsWillChange: opinfo];
      }
    }
  }
  
  [self closeInvalidViewers: viewersToClose];
}

- (void)fileSystemDidChange:(NSNotification *)notif
{
  NSDictionary *opinfo = (NSDictionary *)[notif object];  
  NSMutableArray *viewersToClose = [NSMutableArray array];
  NSString *operation = [opinfo objectForKey: @"operation"];
  int i;

  /* Handle unmount operations: close all viewers on the unmounted volume. */
  if ([operation isEqual: @"UnmountOperation"]) {
    NSString *unmountedPath = [opinfo objectForKey: @"unmounted"];
    if (unmountedPath) {
      NSDebugLLog(@"gwspace", @"GWViewersManager: fileSystemDidChange received UnmountOperation for %@", unmountedPath);
      [self closeViewersForUnmountedPath: unmountedPath];
      return;
    }
  }
    
  for (i = 0; i < [viewers count]; i++) {
    id viewer = [viewers objectAtIndex: i];
    FSNode *vnode = [viewer baseNode];

    if (([vnode isValid] == NO) && ([viewer invalidated] == NO)) {
      [viewer invalidate];
      [viewersToClose addObject: viewer];
      
    } else {
      if ([viewer involvedByFileOperation: opinfo]) {
        [viewer nodeContentsDidChange: opinfo];
      }
    }
    
    if ([viewer invalidated] == NO) {
      id shelf = [viewer shelf];
      
      if (shelf) {
        [shelf nodeContentsDidChange: opinfo];
      }
    }
  }

  [self closeInvalidViewers: viewersToClose]; 
}

- (void)watcherNotification:(NSNotification *)notif
{
  NSDictionary *info = (NSDictionary *)[notif object];
  NSString *event = [info objectForKey: @"event"];
  NSString *path = [info objectForKey: @"path"];
  NSMutableArray *viewersToClose = [NSMutableArray array];
  int i, j;

  for (i = 0; i < [viewers count]; i++) {
    id viewer = [viewers objectAtIndex: i];
    FSNode *node = [viewer baseNode];
    NSArray *watchedNodes = [viewer watchedNodes];
    
    if ([event isEqual: @"GWWatchedPathDeleted"]) {  
      if (([[node path] isEqual: path]) || [node isSubnodeOfPath: path]) { 
        if ([viewer invalidated] == NO) {
          [viewer invalidate];
          [viewersToClose addObject: viewer];
        }
      }
    }
    
    for (j = 0; j < [watchedNodes count]; j++) {
      if ([[[watchedNodes objectAtIndex: j] path] isEqual: path]) {
        [viewer watchedPathChanged: info];
        break;
      }
    }
    
    if ([viewer invalidated] == NO) {
      id shelf = [viewer shelf];
      
      if (shelf) {
        [shelf watchedPathChanged: info];
      }
    }
  }

  [self closeInvalidViewers: viewersToClose]; 
}

- (void)thumbnailsDidChangeInPaths:(NSArray *)paths
{
  NSUInteger i;  

  for (i = 0; i < [viewers count]; i++) {
    id viewer = [viewers objectAtIndex: i];
    
    if ([viewer invalidated] == NO) {
      if (paths == nil) {
        [viewer reloadFromNode: [viewer baseNode]];
      } else {
        NSUInteger j;
      
        for (j = 0; j < [paths count]; j++) {
          NSString *path = [paths objectAtIndex: j];

          if ([viewer isShowingPath: path]) {
            FSNode *node = [FSNode nodeWithPath: path];
            
            [viewer reloadFromNode: node];
            
            if ([viewer respondsToSelector: @selector(updateShownSelection)]) {
              [viewer updateShownSelection];
            }
          }
        }
      }
    }
  }
}

- (void)hideDotsFileDidChange:(BOOL)hide
{
  NSMutableArray *viewersToClose = [NSMutableArray array];
  NSUInteger i;  

  for (i = 0; i < [viewers count]; i++) {
    id viewer = [viewers objectAtIndex: i];
        
    if ([viewer invalidated] == NO) {
      if (hide) {
        if ([[[viewer baseNode] path] rangeOfString: @"."].location != NSNotFound) {
          [viewer invalidate];
          [viewersToClose addObject: viewer];
        }
      }
      
      if ([viewersToClose containsObject: viewer] == NO) {
        [viewer hideDotsFileChanged: hide];
      }
    }
  }

  [self closeInvalidViewers: viewersToClose]; 
}

- (void)hiddenFilesDidChange:(NSArray *)paths
{
  NSMutableArray *viewersToClose = [NSMutableArray array];
  NSUInteger i, j;  

  for (i = 0; i < [viewers count]; i++) {
    id viewer = [viewers objectAtIndex: i];
    NSString *vwrpath = [[viewer baseNode] path];

    for (j = 0; j < [paths count]; j++) {
      NSString *path = [paths objectAtIndex: j];
      
      if (isSubpathOfPath(path, vwrpath) || [path isEqual: vwrpath]) {
        [viewer invalidate];
        [viewersToClose addObject: viewer];
      }
    }
    
    if ([viewersToClose containsObject: viewer] == NO) {
      [viewer hiddenFilesChanged: paths];
    }
  }

  [self closeInvalidViewers: viewersToClose]; 
}


- (BOOL)hasViewerWithWindow:(id)awindow
{
  NSUInteger i;  

  for (i = 0; i < [viewers count]; i++) {
    id viewer = [viewers objectAtIndex: i];
    
    if ([viewer win] == awindow) {
      return YES;
    }
  }
  
  return NO;
}

- (id)viewerWithWindow:(id)awindow
{
  NSUInteger i;  

  for (i = 0; i < [viewers count]; i++) {
    id viewer = [viewers objectAtIndex: i];
    
    if ([viewer win] == awindow) {
      return viewer;
    }
  }
  
  return nil;
}

- (NSArray *)viewerWindows
{
  NSMutableArray *wins = [NSMutableArray array];
  NSUInteger i;  

  for (i = 0; i < [viewers count]; i++) {
    id viewer = [viewers objectAtIndex: i];
    
    if ([viewer invalidated] == NO) {
      [wins addObject: [viewer win]];
    }
  }

  return wins;
}

- (BOOL)orderingViewers
{
  return orderingViewers;
}

- (void)updateDesktop
{
  id desktopManager = [gworkspace desktopManager];  

  if ([desktopManager isActive]) {
    [desktopManager deselectAllIcons];
  }
}

- (void)updateDefaults
{
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];  
  NSMutableArray *viewersInfo = [NSMutableArray array];
  NSUInteger i;  

  for (i = 0; i < [viewers count]; i++)
    {
      id viewer = [viewers objectAtIndex: i];

      if ([viewer invalidated] == NO)
        {
          NSMutableDictionary *dict = [NSMutableDictionary dictionary];
      
          [dict setObject: [[viewer baseNode] path] forKey: @"path"];

          if ([viewer defaultsKey])
            [dict setObject: [viewer defaultsKey] forKey: @"key"];
               
          [viewersInfo addObject: dict];
        }
    }
  
  [defaults setObject: viewersInfo forKey: @"viewersinfo"];
}

- (void)closeViewersForUnmountedPath:(NSString *)unmountedPath
{
  if (unmountedPath == nil)
    return;

  NSMutableArray *viewersToClose = [NSMutableArray array];

  NSDebugLLog(@"gwspace", @"GWViewersManager: closeViewersForUnmountedPath: %@", unmountedPath);

  NSArray *vwCopy = [viewers copy];
  for (id viewer in vwCopy)
    {
      if ([viewer invalidated] == NO)
        {
          NSString *viewerPath = [[viewer baseNode] path];
          BOOL shouldClose = NO;

          NSDebugLLog(@"gwspace", @"GWViewersManager:   viewer baseNode=%@", viewerPath);

          /* Check 1: baseNode is the unmounted path or a subdirectory of it.
           * This catches viewers opened directly at the volume path (spatial
           * mode) or viewers for subdirectories on the volume. */
          if ([viewerPath isEqual: unmountedPath] || isSubpathOfPath(unmountedPath, viewerPath))
            {
              shouldClose = YES;
              NSDebugLLog(@"gwspace", @"GWViewersManager:   -> match via baseNode");
            }

          /* Check 2: the viewer is currently showing the unmounted path or a
           * subdirectory inside it.  In the default browsing mode, all viewers
           * are created with baseNode = @"/" and then navigated to the target
           * path, so baseNode alone is never the volume path.  We must also
           * check the shownNode via isShowingPath:. */
          if (!shouldClose && [viewer isShowingPath: unmountedPath])
            {
              shouldClose = YES;
              NSDebugLLog(@"gwspace", @"GWViewersManager:   -> match via isShowingPath");
            }

          if (shouldClose)
            {
              NSDebugLLog(@"gwspace", @"GWViewersManager:   -> CLOSING");
              [viewer invalidate];
              [viewersToClose addObject: viewer];
            }
        }
    }

  if ([viewersToClose count] > 0)
    {
      NSDebugLLog(@"gwspace", @"GWViewersManager: closing %ld viewers", (long)[viewersToClose count]);
      [self closeInvalidViewers: viewersToClose];
    }

  [vwCopy release];
}

- (void)mountedVolumesDidChange
{
  /* Called by GWDesktopManager when the MPointWatcher detects a volume
     change.  This is the most reliable notification path — it polls
     mount roots every 1.5s and fires after the mount is complete,
     unlike GWFileWatcherFileDidChangeNotification which may arrive
     before the filesystem is fully mounted. */
  NSWorkspace *ws = [NSWorkspace sharedWorkspace];
  NSArray *mountRoots = [Workspace volumeMountRoots];
  NSMutableArray *viewersToClose = [NSMutableArray array];
  NSMutableSet *currentVolumeSet = [NSMutableSet set];

  /* Build a set of all currently mounted removable/media volume paths. */
  [currentVolumeSet addObjectsFromArray: [ws mountedRemovableMedia]];
  {
    NSArray *allLocal = [ws mountedLocalVolumePaths];
    for (NSString *vol in allLocal)
      {
        for (NSString *root in mountRoots)
          {
            if ([vol hasPrefix: [root stringByAppendingString: @"/"]]
                && ![vol isEqualToString: @"/"])
              {
                [currentVolumeSet addObject: vol];
                break;
              }
          }
      }
  }

  NSDebugLLog(@"gwspace", @"GWViewersManager: mountedVolumesDidChange - currentVolumeSet has %ld entries, %ld viewers", 
              (long)[currentVolumeSet count], (long)[viewers count]);
  for (NSString *vol in currentVolumeSet)
    {
      NSDebugLLog(@"gwspace", @"GWViewersManager:   mounted: %@", vol);
    }

  /* Iterate a copy of the viewers array to avoid crashes if
   * closeInvalidViewers: removes entries from the original array
   * during iteration (e.g. via closeViewersForUnmountedPath: called
   * from within showMountedVolumes). */
  NSArray *viewersCopy = [viewers copy];
  for (id viewer in viewersCopy)
    {
      if ([viewer invalidated] == NO)
        {
          FSNode *node = [viewer baseNode];
          if (node == nil) continue;
          NSString *vpath = [node path];
          if (vpath == nil) continue;

          NSDebugLLog(@"gwspace", @"GWViewersManager:   viewer path=%@ isValid=%d", vpath, [node isValid]);

          if ([node isValid] == NO)
            {
              /* Path no longer exists at all (subdirectories on an unmounted
               * volume, or the volume itself on platforms where the mountpoint
               * directory disappears). */
              NSDebugLLog(@"gwspace", @"GWViewersManager:   -> CLOSING (isValid=NO)");
              [viewer invalidate];
              [viewersToClose addObject: viewer];
            }
          else
            {
              /* On Linux, mountpoint directories persist as empty dirs after
               * unmount, so isValid returns YES even though the volume is gone.
               * Check if this path is under a known mount root but NOT under
               * any currently mounted volume — if so, the volume was unmounted. */
              BOOL underMountRoot = NO;
              for (NSString *root in mountRoots)
                {
                  if ([vpath isEqual: root] || [vpath hasPrefix: [root stringByAppendingString: @"/"]])
                    {
                      NSDebugLLog(@"gwspace", @"GWViewersManager:     under mount root %@", root);
                      underMountRoot = YES;
                      break;
                    }
                }

              if (underMountRoot)
                {
                  BOOL onMountedVolume = NO;
                  for (NSString *vol in currentVolumeSet)
                    {
                      if ([vpath isEqual: vol] || [vpath hasPrefix: [vol stringByAppendingString: @"/"]])
                        {
                          NSDebugLLog(@"gwspace", @"GWViewersManager:     on mounted volume %@", vol);
                          onMountedVolume = YES;
                          break;
                        }
                    }

                  /* Also check NetworkVolumeManager for FUSE mounts (sshfs etc.)
                     that NSWorkspace may not report.  Check not only for an
                     exact match (viewer showing the root of the network volume)
                     but also for subdirectories (viewer showing a path under
                     the network volume). */
                  if (onMountedVolume == NO)
                    {
                      NSSet *netPaths = [[NetworkVolumeManager sharedManager] allMountedPaths];
                      if ([netPaths containsObject: vpath])
                        {
                          NSDebugLLog(@"gwspace", @"GWViewersManager:     on mounted network volume %@", vpath);
                          onMountedVolume = YES;
                        }
                      else
                        {
                          /* Check if vpath is a subdirectory of any network mount */
                          for (NSString *np in netPaths)
                            {
                              NSString *npSlash = [np stringByAppendingString: @"/"];
                              if ([vpath hasPrefix: npSlash])
                                {
                                  NSDebugLLog(@"gwspace",
                                    @"GWViewersManager:     under mounted network volume %@", np);
                                  onMountedVolume = YES;
                                  break;
                                }
                            }
                        }
                    }

                  if (onMountedVolume == NO)
                    {
                      /* Before closing, check if this path is a PARENT of any
                       * currently mounted volume (e.g. viewer shows /media/devuan/
                       * while /media/devuan/Asterisk is mounted).  Such paths are
                       * still valid and should NOT be closed — only the volume
                       * path itself or its subdirectories should trigger a close.
                       *
                       * Normalize: strip trailing slash if present (some viewer
                       * base nodes include it), then append a single slash. */
                      NSString *vpn = vpath;
                      if ([vpn hasSuffix: @"/"]) {
                        vpn = [vpn substringToIndex: [vpn length] - 1];
                      }
                      vpn = [vpn stringByAppendingString: @"/"];
                      BOOL isParentOfMounted = NO;
                      for (NSString *vol in currentVolumeSet)
                        {
                          if ([vol hasPrefix: vpn])
                            {
                              NSDebugLLog(@"gwspace",
                                @"GWViewersManager:     is parent of mounted volume %@", vol);
                              isParentOfMounted = YES;
                              break;
                            }
                        }
                      /* Same check for network volumes */
                      if (isParentOfMounted == NO)
                        {
                          NSSet *netPaths = [[NetworkVolumeManager sharedManager] allMountedPaths];
                          for (NSString *np in netPaths)
                            {
                              if ([np hasPrefix: vpn])
                                {
                                  NSDebugLLog(@"gwspace",
                                    @"GWViewersManager:     is parent of mounted network volume %@", np);
                                  isParentOfMounted = YES;
                                  break;
                                }
                            }
                        }

                      if (isParentOfMounted == NO)
                        {
                          NSDebugLLog(@"gwspace", @"GWViewersManager:   -> CLOSING (not on any mounted volume)");
                          [viewer invalidate];
                          [viewersToClose addObject: viewer];
                        }
                      else
                        {
                          /* Keep the viewer open — it is showing a parent of a
                           * mounted volume, which is still a valid location. */
                          NSDebugLLog(@"gwspace", @"GWViewersManager:   -> KEEPING (parent of mounted volume)");
                        }
                    }
                  else
                    {
                      NSDebugLLog(@"gwspace", @"GWViewersManager:   -> KEEPING (on mounted volume)");
                    }
                }
              else
                {
                  NSDebugLLog(@"gwspace", @"GWViewersManager:   -> KEEPING (not under any mount root)");
                }
            }
        }
    }

  [self closeInvalidViewers: viewersToClose];

  /* Then reload sidebars for remaining viewers (use the same copy) */
  for (id viewer in viewersCopy)
    {
      if ([viewer invalidated] == NO)
        {
          [viewer reloadSidebar];
        }
    }

  [viewersCopy release];
}

- (void)newVolumeMounted:(NSNotification *)notif
{
  NSDictionary *dict = [notif userInfo];  
  NSString *volpath = [dict objectForKey: @"NSDevicePath"];
  FSNodeRep *fnr = [FSNodeRep sharedInstance];

  if (volpath)
    [fnr addVolumeAt:volpath];
  else
    NSDebugLLog(@"gwspace", @"newVolumeMounted notification received with empty NSDevicePath");
}
- (void)mountedVolumeWillUnmount:(NSNotification *)notif
{
  NSDictionary *dict = [notif userInfo];
  NSString *volpath = [dict objectForKey:@"NSDevicePath"];

  if (!volpath) {
    NSDebugLLog(@"gwspace", @"mountedVolumeWillUnmount notification received with empty NSDevicePath");
    return;
  }

  /* Notify viewers that an unmount is about to occur so they can prepare */
  NSString *parent = [volpath stringByDeletingLastPathComponent];
  NSString *name = [volpath lastPathComponent];
  NSDictionary *willInfo = @{ @"operation": @"UnmountOperation",
                              @"source": parent,
                              @"destination": parent,
                              @"files": @[name],
                              @"unmounted": volpath };

  /* Post a GWFileSystemWillChangeNotification which viewers already listen to */
  [[NSNotificationCenter defaultCenter] postNotificationName:@"GWFileSystemWillChangeNotification" object:willInfo];
}
- (void)mountedVolumeDidUnmount:(NSNotification *)notif
{
  NSDictionary *dict = [notif userInfo];  
  NSString *volpath = [dict objectForKey: @"NSDevicePath"];
  FSNodeRep *fnr = [FSNodeRep sharedInstance];

  if (volpath) {
    [fnr removeVolumeAt:volpath];
    
    /* Send final unmount notification to complete the operation */
    NSString *parent = [volpath stringByDeletingLastPathComponent];
    NSString *name = [volpath lastPathComponent];
    NSDictionary *didInfo = @{ @"operation": @"UnmountOperation",
                               @"source": parent,
                               @"destination": parent,
                               @"files": @[name],
                               @"unmounted": volpath };
    
    [[NSNotificationCenter defaultCenter] postNotificationName:@"GWFileSystemDidChangeNotification" object:didInfo];
    
    /* Update the Volumes section in all open viewer windows' sidebars. */
    NSArray *viewersCopy2 = [viewers copy];
    for (id viewer in viewersCopy2)
      {
        if ([viewer invalidated] == NO)
          {
            [viewer reloadSidebar];
          }
      }
    [viewersCopy2 release];
  } else {
    NSDebugLLog(@"gwspace", @"mountedVolumeDidUnmount notification received with empty NSDevicePath");
  }
}

// Stub implementations for missing methods to prevent build warnings and crashes

- (id)viewerOfType:(unsigned)vtype
          showType:(NSString *)stype
           forNode:(FSNode *)node
     showSelection:(BOOL)showsel
    closeOldViewer:(id)oldvwr
          forceNew:(BOOL)force
{
  NSDebugLLog(@"gwspace", @"viewerOfType:showType:forNode:showSelection:closeOldViewer:forceNew: called");
  NSDebugLLog(@"gwspace", @"vtype=%u, node=%@, showsel=%d, force=%d", vtype, [node path], showsel, force);

  id viewer = nil;
  NSRect inheritedFrame = NSZeroRect;

  /* Replace semantics: hand the predecessor's identity over BEFORE the
   * successor is created.  Removing it from `viewers` up front (kept alive by
   * the retain) makes root-viewer detection, dedup and window placement see
   * the array exactly as under a close-first ordering, while the actual close
   * happens LAST so the object is never deallocated mid-close (`viewers` is
   * its sole owner).  viewerWillClose: guards its own removal with
   * containsObject:. */
  if (oldvwr) {
    NSWindow *ow;

    RETAIN (oldvwr);
    [viewers removeObject: oldvwr];

    ow = [oldvwr win];
    if (ow)
      inheritedFrame = [ow frame];
  }

  if (vtype == SPATIAL) {
    if (!force)
      viewer = [self viewerOfType: SPATIAL withBaseNode: node];

    if (viewer) {
      NSDebugLLog(@"gwspace", @"Found existing spatial viewer, activating it");
      [viewer activate];
    } else {
      viewer = [self createViewerOfType: SPATIAL
                                forNode: node
                        browserShowType: 0
                        spatialShowType: stype
                          showSelection: showsel
                                withKey: nil
                         inheritedFrame: inheritedFrame];
    }
  } else {
    /* showType:0 = "no explicit inner view"; choosing Browsing selects window
     * chrome, so let the folder's remembered .DS_Store style win.  Callers
     * that want a specific inner view still pass a concrete GWViewType. */
    if (!force)
      viewer = [self viewerOfType: BROWSING withBaseNode: node];

    if (viewer) {
      NSDebugLLog(@"gwspace", @"Found existing browsing viewer, activating it");
      [viewer activate];
    } else {
      viewer = [self createViewerOfType: BROWSING
                                forNode: node
                        browserShowType: 0
                        spatialShowType: nil
                          showSelection: showsel
                                withKey: nil
                         inheritedFrame: inheritedFrame];
    }
  }

  /* Close the predecessor only now that its replacement exists and is
   * shown, so focus hands over cleanly. */
  if (oldvwr) {
    NSDebugLLog(@"gwspace", @"Closing old viewer");
    [oldvwr deactivate];
    RELEASE (oldvwr);
  }

  return viewer;
}

/* First-class mode switch: replace a viewer window with one of the other
 * kind for the same folder.  Owns the whole sequence — identity handoff,
 * frame inheritance, create-then-close ordering — via
 * viewerOfType:…closeOldViewer:forceNew: (that selector is kept as the
 * workhorse because GWX11SpatialPath invokes it by runtime lookup). */
- (id)replaceViewer:(id)oldvwr withViewerType:(unsigned)vtype
{
  if (oldvwr == nil)
    return nil;

  return [self viewerOfType: vtype
                   showType: nil
                    forNode: [oldvwr baseNode]
              showSelection: YES
             closeOldViewer: oldvwr
                   forceNew: YES];
}

- (void)setBehaviour:(NSString *)behaviour forViewer:(id)aviewer
{
  // Set viewer behavior - for now just accept the change
  // In a full implementation, this would update viewer preferences
}

- (id)viewerOfType:(unsigned)type withBaseNode:(FSNode *)node
{
  /* Return an existing viewer for this node *of the requested kind* — a
   * browser window must not satisfy a request for a spatial one (or vice
   * versa), or a mode switch / WM navigation would activate the wrong kind. */
  NSUInteger i;
  BOOL wantSpatial = (type == SPATIAL);

  for (i = 0; i < [viewers count]; i++)
    {
      id viewer = [viewers objectAtIndex: i];

      if ([[viewer baseNode] isEqual: node]
          && ([viewer isSpatial] == wantSpatial))
        return viewer;
    }

  return nil;
}

- (id)viewerOfType:(unsigned)type showingNode:(FSNode *)node
{
  // Return existing viewer if any
  return [self viewerShowingNode:node];
}

- (NSNumber *)nextRootViewerKey
{
  // Return a unique key for root viewers
  return [NSNumber numberWithUnsignedLong:(unsigned long)[[NSDate date] timeIntervalSince1970]];
}

- (int)typeOfViewerForNode:(FSNode *)node
{
  // Default to browsing behavior
  return BROWSING;
}

- (id)parentOfSpatialViewer:(id)aviewer
{
  // Spatial viewers don't have parents in browsing mode
  return nil;
}

- (void)selectedSpatialViewerChanged:(id)aviewer
{
  // Handle spatial viewer selection change
  // In browsing mode, this is typically a no-op
}

- (void)synchronizeSelectionInParentOfViewer:(id)aviewer
{
  // Synchronize selection with parent viewer
  // In browsing mode, this is typically a no-op
}

- (void)viewer:(id)aviewer didShowNode:(FSNode *)node
{
  // Notification that viewer showed a node
  // Can be used for history tracking or other features
}

#pragma mark - Window Animation Support

- (void)setWindowBirthRect:(NSRect)sourceRect
               targetRect:(NSRect)targetRect
            animationType:(int32_t)animationType
                 forWindow:(NSWindow *)window {
  // Set X11 window property _GSWORKSPACE_WINDOW_BIRTH
  // This will be read by WindowManager to perform the spatial birth animation.
  // Format: 9 x 32-bit integers (source x,y,w,h, target x,y,w,h, animationType)
  // Per PRD.md section 8.

  if (!window) {
    NSDebugLLog(@"gwspace", @"[Animation] NULL window passed to setWindowBirthRect");
    return;
  }

  // Check Reduce Motion preference.
  // GSWindowAnimationEnabled only disables animation when explicitly set to NO.
  id animEnabled = [[NSUserDefaults standardUserDefaults] objectForKey:@"GSWindowAnimationEnabled"];
  if (animEnabled && [animEnabled boolValue] == NO) {
    NSDebugLLog(@"gwspace", @"[Animation] Window animation disabled by GSWindowAnimationEnabled preference");
    return;
  }
  // Also respect the macOS-style Reduce Motion key
  if ([[NSUserDefaults standardUserDefaults] boolForKey:@"GSReduceMotion"] == YES) {
    animationType = 1; // NoAnimation
    NSDebugLLog(@"gwspace", @"[Animation] Reduce Motion active, using NoAnimation type");
  }

#ifdef __linux__
  GSDisplayServer *server = GSServerForWindow(window);
  if (!server) {
    server = GSCurrentServer();
  }
  if (!server) {
    NSDebugLLog(@"gwspace", @"[Animation] No display server available for window animation");
    return;
  }

  Display *display = (Display *)[server serverDevice];
  if (!display) {
    NSDebugLLog(@"gwspace", @"[Animation] No X11 display available for animation property");
    return;
  }

  // windowDevice returns a Window ID (cast to void*), not a pointer to Window
  void *winptr = [server windowDevice:[window windowNumber]];
  if (!winptr) {
    NSDebugLLog(@"gwspace", @"[Animation] No X11 window device for animation property");
    return;
  }
  Window xwindow = (Window)(uintptr_t)winptr;  // Cast directly, don't dereference
  if (xwindow == 0) {
    NSDebugLLog(@"gwspace", @"[Animation] Invalid X11 window id for animation property");
    return;
  }

  // Convert NSRect to screen coordinates (X11 has origin at top-left)
  NSScreen *screen = [window screen];
  if (!screen) screen = [NSScreen mainScreen];
  if (!screen) {
    NSDebugLLog(@"gwspace", @"[Animation] No screen available for window animation coordinate conversion");
    return;
  }
  NSRect screenFrame = [screen frame];

  // Compute absolute X11 screen coordinates for source rect
  // (account for screen origin and flip Y from Cocoa bottom-left to X11 top-left)
  int32_t srcX = (int32_t)(sourceRect.origin.x + screenFrame.origin.x);
  int32_t srcY = (int32_t)(screenFrame.origin.y + screenFrame.size.height - sourceRect.origin.y - sourceRect.size.height);
  int32_t srcW = (int32_t)sourceRect.size.width;
  int32_t srcH = (int32_t)sourceRect.size.height;

  // Compute absolute X11 screen coordinates for target rect
  int32_t dstX = (int32_t)(targetRect.origin.x + screenFrame.origin.x);
  int32_t dstY = (int32_t)(screenFrame.origin.y + screenFrame.size.height - targetRect.origin.y - targetRect.size.height);
  int32_t dstW = (int32_t)targetRect.size.width;
  int32_t dstH = (int32_t)targetRect.size.height;

  // Build 9-int32 data array: source(x,y,w,h), target(x,y,w,h), animationType
  int32_t data[9] = {srcX, srcY, srcW, srcH, dstX, dstY, dstW, dstH, animationType};

  // Error checking: validate parameters before calling X11
  if (!display || xwindow == 0) {
    NSDebugLLog(@"gwspace", @"[Animation] Invalid display or X window for setting birth rect");
    return;
  }

  // Set error handler to catch X11 errors gracefully
  int (*oldHandler)(Display *, XErrorEvent *) = XSetErrorHandler(NULL);

  Atom birthAtom = XInternAtom(display, "_GSWORKSPACE_WINDOW_BIRTH", False);
  if (birthAtom == None) {
    NSDebugLLog(@"gwspace", @"[Animation] Failed to intern _GSWORKSPACE_WINDOW_BIRTH atom");
    XSetErrorHandler(oldHandler);
    return;
  }

  int status = XChangeProperty(display, xwindow, birthAtom, XA_CARDINAL, 32,
                               PropModeReplace, (unsigned char *)data, 9);
  if (status == BadWindow) {
    NSDebugLLog(@"gwspace", @"[Animation] XChangeProperty failed: window %lu is invalid", (unsigned long)xwindow);
    XSetErrorHandler(oldHandler);
    return;
  }

  XFlush(display);

  // Sync to ensure the property is committed to the X server before
  // makeKeyAndOrderFront: sends the MapRequest (which goes through a
  // separate X connection via GNUstep's display server).  Without this
  // sync the MapRequest can arrive at the X server before the property
  // change is visible, and the WindowManager will not see the birth data.
  XSync(display, False);
  XSetErrorHandler(oldHandler);

  NSDebugLLog(@"gwspace", @"[Animation] Set birth rect on window %lu: src={%d,%d,%d,%d} dst={%d,%d,%d,%d} type=%d",
        (unsigned long)xwindow, srcX, srcY, srcW, srcH, dstX, dstY, dstW, dstH, animationType);
#endif
}

@end


@implementation GWViewersManager (History)

- (void)addNode:(FSNode *)node toHistoryOfViewer:(id)viewer
{
  if ([node isValid] && (settingHistoryPath == NO))
    {
      NSMutableArray *history = [viewer history];
      int position = [viewer historyPosition];
      id hisviewer = [historyWindow viewer];
      int cachemax = [gworkspace maxHistoryCache];
      int count;
      
      while ([history count] > cachemax)
        {
          [history removeObjectAtIndex: 0];
          if (position > 0) {
            position--;
          }
        }
    
      count = [history count];
      
      if (position == (count - 1))
        {
          if ([[history lastObject] isEqual: node] == NO)
            {
              [history insertObject: node atIndex: count];
            }
          position = [history count] - 1;
          
        }
      else if (count > (position + 1))
        {
          BOOL equalpos = [[history objectAtIndex: position] isEqual: node];
          BOOL equalnext = [[history objectAtIndex: position + 1] isEqual: node];
          
          if (((equalpos == NO) && (equalnext == NO)) || equalnext)
            {
              position++;
              
              if (equalnext == NO)
                {
                  [history insertObject: node atIndex: position];
                }
              
              while ((position + 1) < [history count])
                {
                  int last = [history count] - 1;
                  [history removeObjectAtIndex: last];
                }
            }
        }
      
      [self removeDuplicatesInHistory: history position: &position];
      
      [viewer setHistoryPosition: position];
      
      if (viewer == hisviewer) 
        {
          [historyWindow setHistoryNodes: history position: position];
        }
    }
}

- (void)removeDuplicatesInHistory:(NSMutableArray *)history
                         position:(int *)pos
{
  int count = [history count];
  int i;
  
#define CHECK_POSITION(n) \
if (*pos >= i) *pos -= n; \
*pos = (*pos < 0) ? 0 : *pos; \
*pos = (*pos >= count) ? (count - 1) : *pos	
  
	for (i = 0; i < count; i++) {
		FSNode *node = [history objectAtIndex: i];
		
		if ([node isValid] == NO) {
			[history removeObjectAtIndex: i];
			CHECK_POSITION (1);		
			count--;
			i--;
		}
	}

	for (i = 0; i < count; i++) {
		FSNode *node = [history objectAtIndex: i];

		if (i < ([history count] - 1)) {
			FSNode *next = [history objectAtIndex: i + 1];
			
			if ([next isEqual: node]) {
				[history removeObjectAtIndex: i + 1];
				CHECK_POSITION (1);
				count--;
				i--;
			}
		}
	}
  
  count = [history count];
  
	if (count > 4) {
		FSNode *na[2], *nb[2];
		
		for (i = 0; i < count; i++) {
			if (i < (count - 3)) {
				na[0] = [history objectAtIndex: i];
				na[1] = [history objectAtIndex: i + 1];
				nb[0] = [history objectAtIndex: i + 2]; 
				nb[1] = [history objectAtIndex: i + 3];
		
				if (([na[0] isEqual: nb[0]]) && ([na[1] isEqual: nb[1]])) {
					[history removeObjectAtIndex: i + 3];
					[history removeObjectAtIndex: i + 2];
					CHECK_POSITION (2);
					count -= 2;
					i--;
				}
			}
		}
	}
    
  CHECK_POSITION (0);
}

- (void)changeHistoryOwner:(id)viewer
{
  if (viewer && (viewer != [historyWindow viewer]))
    {
      NSMutableArray *history = [viewer history];
      int position = [viewer historyPosition];
  
      [historyWindow setHistoryNodes: history position: position];

    } else if (viewer == nil)
    {
      [historyWindow setHistoryNodes: nil];
    }

  [historyWindow setViewer: viewer];  
}

- (void)goToHistoryPosition:(int)pos 
                   ofViewer:(id)viewer
{
  if (viewer)
    {
      NSMutableArray *history = [viewer history];
      int position = [viewer historyPosition];
 
      [self removeDuplicatesInHistory: history position: &position];

      if ((pos >= 0) && (pos < [history count]))
        {
          [self setPosition: pos inHistory: history ofViewer: viewer];
        }
    }
}

- (void)goBackwardInHistoryOfViewer:(id)viewer
{
  NSMutableArray *history = [viewer history];
  int position = [viewer historyPosition];

  [self removeDuplicatesInHistory: history position: &position];

  if ((position > 0) && (position < [history count]))
    {
      position--;
      [self setPosition: position inHistory: history ofViewer: viewer];
    }
}

- (void)goForwardInHistoryOfViewer:(id)viewer
{
  NSMutableArray *history = [viewer history];
  int position = [viewer historyPosition];

  [self removeDuplicatesInHistory: history position: &position];
  
  if ((position >= 0) && (position < ([history count] - 1)))
    {
      position++;
      [self setPosition: position inHistory: history ofViewer: viewer];
    }
}

- (void)setPosition:(int)position
          inHistory:(NSMutableArray *)history
           ofViewer:(id)viewer
{
  FSNode *node = [history objectAtIndex: position];
  id nodeView = [viewer nodeView];
  
  settingHistoryPath = YES;
  
  if ([viewer viewType] != GWViewTypeBrowser)
    {
      [nodeView showContentsOfNode: node];
    }
  else
    {
      [nodeView showContentsOfNode: [FSNode nodeWithPath: [node parentPath]]];
      [nodeView selectRepsOfSubnodes: [NSArray arrayWithObject: node]];
    }

  if ([nodeView respondsToSelector: @selector(scrollSelectionToVisible)])
    [nodeView scrollSelectionToVisible];

  [viewer setHistoryPosition: position];

  [historyWindow setHistoryPosition: position];

  settingHistoryPath = NO;
}

@end
