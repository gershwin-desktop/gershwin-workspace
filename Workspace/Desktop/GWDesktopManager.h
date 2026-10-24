/* GWDesktopManager.h
 *  
 * Copyright (C) 2005-2021 Free Software Foundation, Inc.
 *
 * Authors: Enrico Sersale <enrico@imago.ro>
 *          Riccardo Mottola <rm@gnu.org>
 * Date: January 2005
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
#import "DockPosition.h"

/* Posted after the Dock settings in the defaults were applied to the Dock,
 * so a panel showing them can follow a change made from outside. */
extern NSString * const GWDockSettingsDidChangeNotification;

@class Workspace;
@class GWDesktopView;
@class Dock;
@class GWDockWindow;
@class MPointWatcher;

@interface GWDesktopManager : NSObject
{
  FSNode *dskNode;
  id win;
  BOOL usexbundle;

  GWDesktopView *desktopView;

  BOOL singleClickLaunch;
  Dock *dock;
  GWDockWindow *dockWindow;
  BOOL hidedock;
  /* The Dock is built but not on the screen yet: it waits for the sources
   * of items in dockPending (DockStartup.h) or for the timer that ends the
   * wait, so that it appears once, with every item. */
  BOOL dockAwaiting;
  NSUInteger dockPending;
  NSTimeInterval dockBuiltAt;
  NSTimer *dockStartupTimer;
  /* Set while -saveDockDefaults writes its keys one by one. */
  BOOL savingDockDefaults;
  DockPosition dockPosition;
  
  NSRect dockReservedFrame;
  NSRect macmenuReservedFrame;
  NSRect tshelfReservedFrame;
  NSRect tshelfActivateFrame;
  
  Workspace *gworkspace;
  FSNodeRep *fsnodeRep;
  MPointWatcher *mpointWatcher;
  id ws;
  NSFileManager *fm;
  NSNotificationCenter *nc;      
}

+ (GWDesktopManager *)desktopManager;

- (void)activateDesktop;

- (void)deactivateDesktop;

- (BOOL)isActive;

- (void)checkDesktopDirs;

- (void)setUsesXBundle:(BOOL)value;

- (BOOL)usesXBundle;

- (id)loadXWinBundle;

- (BOOL)hasWindow:(id)awindow;

- (id)desktopView;

- (FSNode *)desktopNode;

- (BOOL)singleClickLaunch;

- (void)setSingleClickLaunch:(BOOL)value;

- (Dock *)dock;

- (DockPosition)dockPosition;

- (void)setDockPosition:(DockPosition)pos;

- (void)setDockActive:(BOOL)value;

/* Tells the desktop that a source of the Dock's first items (one of the
 * DockStartupSources bits) has added all it has.  Once every source has
 * reported the Dock appears.  Does nothing when the Dock is not waiting. */
- (void)dockSourceDidFinish:(NSUInteger)source;

- (BOOL)dockActive;

- (void)saveDockDefaults;

/* A Dock setting changed from inside Workspace, by the preferences or by
 * the Dock's own menu: applied, stored and announced with
 * GWDockSettingsDidChangeNotification, so that every place showing it
 * follows. */
- (void)changeDockPosition:(DockPosition)pos;

- (void)changeDockMagnification:(BOOL)value;

- (void)setReservedFrames;

/* The frame of the desktop window in device pixels: desktopFullFrame is in
   points, a window frame is not. */
- (NSRect)desktopWindowFrame;

/* Applies that frame again once a burst of screen changes has settled. */
- (void)scheduleDesktopReframe;

- (NSRect)macmenuReservedFrame;

- (NSRect)dockReservedFrame;

- (void)deselectAllIcons;

- (void)deselectInSpatialViewers;

- (void)addWatcherForPath:(NSString *)path;

- (void)removeWatcherForPath:(NSString *)path;

- (void)showRootViewer;

- (BOOL)selectFile:(NSString *)fullPath
inFileViewerRootedAtPath:(NSString *)rootFullpath;

- (void)performFileOperation:(NSDictionary *)opinfo;
                      
- (NSString *)trashPath;

- (void)moveToTrash;

- (void)checkNewRemovableMedia;

- (void)fileSystemWillChange:(NSNotification *)notif;

- (void)fileSystemDidChange:(NSNotification *)notif;

- (void)watcherNotification:(NSNotification *)notif;

- (void)thumbnailsDidChangeInPaths:(NSArray *)paths;

- (void)removableMediaPathsDidChange;

- (void)hideDotsFileDidChange:(BOOL)hide;

- (void)hiddenFilesDidChange:(NSArray *)paths;

- (void)newVolumeMounted:(NSNotification *)notif;

- (void)mountedVolumeWillUnmount:(NSNotification *)notif;

- (void)mountedVolumeDidUnmount:(NSNotification *)notif;

- (void)mountedVolumesDidChange;

- (void)unlockVolumeAtPath:(NSString *)volpath;

- (void)updateDefaults;

- (void)setContextHelp;

@end


//
// GWDesktopWindow Delegate Methods
//
@interface GWDesktopManager (GWDesktopWindowDelegateMethods)

- (BOOL)validateItem:(id)menuItem;
- (void)openSelectionInNewViewer:(BOOL)newv;
- (void)openSelectionAsFolder;
- (void)openSelectionWith;
- (void)newFolder;
- (void)newFile;
- (void)duplicateFiles;
- (void)makeAliasFiles;
- (void)recycleFiles;
- (void)emptyTrash;
- (void)deleteFiles;
- (void)setShownType:(id)sender;
- (void)setExtendedShownType:(id)sender;
- (void)setIconsSize:(id)sender;
- (void)setIconsPosition:(id)sender;
- (void)setLabelSize:(id)sender;
- (void)selectAllInViewer;
- (void)showTerminal;

@end


@interface MPointWatcher : NSObject
{
  NSArray *mountedRemovableVolumes;
  NSMutableSet *watchedMountRoots;  /* Tracks paths being watched for mount changes */
  BOOL active;
  GWDesktopManager *manager;
  NSFileManager *fm;

#if defined(__OpenBSD__) || defined(_WIN32)
  /* OpenBSD has neither a pollable mount-table fd (no /proc) nor
   * EVFILT_FS, so it is the one platform that still ticks on a plain
   * timer - at a much slower, clearly-marked rate than before this fix. */
  NSTimer *timer;
#else
  /* Linux and the kqueue BSDs react to a real mount-table change instead
   * of ticking: a background NSThread blocks in poll()/kevent() until the
   * kernel reports one, or until -stopWatching writes to watcherStopPipe. */
  int watcherStopPipe[2];
  BOOL watcherThreadRunning;
  NSCondition *watcherDoneCondition;
  BOOL watcherThreadDone;
#endif
}

- (id)initForManager:(GWDesktopManager *)mngr;

- (void)startWatching;

- (void)stopWatching;

- (void)watchMountPoints:(id)sender;

- (NSArray *)effectiveDesktopVolumes;

- (BOOL)isWatchingPath:(NSString *)path;

@end


@interface GWMounter : NSObject
{
}

+ (void)mountRemovableMedia;

@end
