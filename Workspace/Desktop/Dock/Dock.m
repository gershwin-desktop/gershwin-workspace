/* Dock.m
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

#include <math.h>
#include "config.h"

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import "Dock.h"
#import "DockIcon.h"
#import "DockService.h"
#import "GWDesktopView.h"
#import "Workspace.h"
#import "GWFunctions.h"
#import "X11AppSupport.h"
#import "GWDockWindow.h"
#import "DockStack.h"

#if HAVE_DBUS
#import "DockServiceDBus.h"
#endif

/* Room for the line between the applications and the folders and Trash. */
#define DIVIDER_SIZE 12
#define MAX_ICN_SIZE 48
#define MIN_ICN_SIZE 16
#define ICN_INCR 4

/* The magnification of the expired patent US7434177: how large the icon
 * under the pointer is drawn by default, how large it may be asked to be,
 * and how far to either side of the pointer the effect reaches, counted in
 * tiles. */
#define LARGE_ICN_SIZE 96.0
#define MAX_LARGE_ICN_SIZE 128.0
#define MAGNIFY_CELLS 3.0

/* How long the effect takes to come up once the pointer is on the Dock,
 * and to go back down once it has left. */
#define MAGNIFY_DURATION 0.2

/* The pointer is looked at every frame while it is anywhere near the Dock.
 * Further away it is looked at just often enough to catch it coming: the
 * time it would need to cross what is left of the distance, at a speed no
 * pointer is pushed past, and never less often than the idle interval. */
#define MAGNIFY_FRAME_INTERVAL (1.0 / 60.0)
#define MAGNIFY_IDLE_INTERVAL 0.25
#define MAGNIFY_POINTER_SPEED 4000.0

/* Returns GSScaleFactor for scaling dock cell frames. Factors below 1.0 are
 * honored (UI is scaled down); an unset or non-positive value means 1.0. */
static inline CGFloat _dockScaleFactor(void)
{
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
  id val = [defaults objectForKey: @"GSScaleFactor"];
  if (val == nil) {
    return 1.0;
  }
  CGFloat sf = [val floatValue];
  return (sf > 0.0) ? sf : 1.0;
}

/* small category to access NSNUmericSearch through a selector */

@interface NSString (NumericSort)
- (NSComparisonResult)numericCompare:(NSString *)s;
@end

@implementation NSString (NumericSort)
- (NSComparisonResult)numericCompare:(NSString *)s
{
  return [self compare:s options:NSNumericSearch];
}
@end

@interface Dock (Magnification)

- (void)layoutIcons;
- (BOOL)magnificationEnabledDefault;
- (CGFloat)largeIconSizeDefault;
- (void)magnificationDefaultsDidChange:(NSNotification *)notif;
- (void)magnifyTick:(NSTimer *)timer;
- (void)setMagnifyInterval:(NSTimeInterval)interval;
- (NSTimeInterval)magnifyIntervalForDistance:(CGFloat)distance
                                        near:(CGFloat)near;

@end


@implementation Dock

- (void)dealloc
{
  [[NSNotificationCenter defaultCenter] removeObserver: self];
  [launchRefreshTimer invalidate];
  launchRefreshTimer = nil;
  [magnifyTimer invalidate];
  magnifyTimer = nil;
  DockServiceStop();
#if HAVE_DBUS
  DockServiceDBusStop();
#endif
  RELEASE (icons);
  RELEASE (backColor);
  
  [super dealloc];
}

- (id)initForManager:(id)mngr
{
  self = [super initWithFrame: NSMakeRect(0, 0, 64, 64)];
  
  if (self)
    {
      NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];	
      NSDictionary *appsdict;
      NSArray *pbTypes;
      int i;
      id defEntry;

      manager = mngr;
      position = [manager dockPosition];

      defEntry = [defaults objectForKey: @"dockstyle"];
      style = DockStyleClassic;
      if ([defEntry intValue] == DockStyleModern)
	style = DockStyleModern;

      singleClickLaunch = [defaults boolForKey: @"singleclicklaunch"];
 
      gw = [Workspace gworkspace];
      fm = [NSFileManager defaultManager];
      ws = [NSWorkspace sharedWorkspace];

      icons = [NSMutableArray new];
      iconSize = MAX_ICN_SIZE;
      baseCell = ceil(iconSize / 3 * 4);

      magnifyEnabled = [self magnificationEnabledDefault];
      largeIconSize = [self largeIconSizeDefault];
      /* Read again whenever the defaults change, so that writing one takes
       * effect on a Dock that is already running. */
      [[NSNotificationCenter defaultCenter]
        addObserver: self
           selector: @selector(magnificationDefaultsDidChange:)
               name: NSUserDefaultsDidChangeNotification
             object: nil];
      magnification = DockMagnificationMake(baseCell, baseCell,
                                            MAGNIFY_CELLS * baseCell);
      magnifyPhase = 0.0;
      magnifyFraction = 0.0;
      magnifyPos = 0.0;
      magnifyArmed = NO;
      magnifyTimer = nil;
      magnifyInterval = 0.0;
      magnifyTime = 0.0;
      barRect = NSZeroRect;
                                
      dndSourceIcon = nil;
      isDragTarget = NO;
      dragdelay = 0;
      targetIndex = -1;
      targetRect = NSZeroRect;
      folderTargetIndex = -1;
    
      pbTypes = [NSArray arrayWithObjects: NSFilenamesPboardType,
			 @"DockIconPboardType",
			 nil];
      [self registerForDraggedTypes: pbTypes];

      if (style == DockStyleModern)
	[self setBackColor: [[NSColor grayColor] colorWithAlphaComponent: 0.33]];
      else
	[self setBackColor: [NSColor grayColor]];
      
      [self createWorkspaceIcon];

      appsdict = [defaults objectForKey: @"applications"];
      
      if (appsdict)
	{
	  NSArray *indexes = [appsdict allKeys];
	  NSMutableDictionary *updatedDict = [NSMutableDictionary dictionary];
    
	  indexes = [indexes sortedArrayUsingSelector: @selector(numericCompare:)];
    
	  for (i = 0; i < [indexes count]; i++)
	    {
	      NSNumber *index = [indexes objectAtIndex: i];
	      id appEntry = [appsdict objectForKey: index];
	      NSString *name = nil;
	      NSString *path = nil;
              
              /* Handle both old format (string) and new format (dictionary) */
              if ([appEntry isKindOfClass: [NSDictionary class]]) {
                name = [appEntry objectForKey: @"name"];
                path = [appEntry objectForKey: @"path"];
              } else if ([appEntry isKindOfClass: [NSString class]]) {
                name = [appEntry stringByDeletingPathExtension];
                path = nil;
              }
              
              /* Validate name exists */
              if (name == nil || [name length] == 0) {
                continue;
              }
              
              /* Try to get path from workspace first, then use saved path as fallback */
              if (path == nil || ![fm fileExistsAtPath: path]) {
                path = [ws fullPathForApplication: name];
              }
        
	      if (path && [fm fileExistsAtPath: path])
		{
		  NS_DURING
		    {
		      DockIcon *icon = [self addIconForApplicationAtPath: path
						        withName: name
						         atIndex: [index intValue]];
		      if (icon) {
		        [icon setDocked: YES];
		        /* Keep this entry in the updated dict */
		        [updatedDict setObject: appEntry forKey: index];
		      } else {
		      }
		    }
		  NS_HANDLER
		    {
		    }
		  NS_ENDHANDLER
		}
	      else
		{
		  /* Application no longer exists - remove it from preferences */
		  if (name) {
		  }
		}
	    }
	  
	  /* Update preferences with only the valid applications */
	  if ([updatedDict count] > 0) {
	    [defaults setObject: updatedDict forKey: @"applications"];
	  } else {
	    [defaults removeObjectForKey: @"applications"];
	  }
	}

      [self loadDockedFolders];
      [self createTrashIcon];

      /* Register for drag notifications */
      [[NSNotificationCenter defaultCenter] addObserver: self
                                               selector: @selector(dragMountpointStarted:)
                                                   name: @"GWDragMountpointStarted"
                                                 object: nil];
      [[NSNotificationCenter defaultCenter] addObserver: self
                                               selector: @selector(dragMountpointEnded:)
                                                   name: @"GWDragMountpointEnded"
                                                  object: nil];
     
      DockServiceStart(self);
#if HAVE_DBUS
      DockServiceDBusStart(self);
#endif

      launchRefreshTimer = [NSTimer scheduledTimerWithTimeInterval: 2.0
                                                            target: self
                                                          selector: @selector(_launchRefreshTimerFired:)
                                                          userInfo: nil
                                                           repeats: YES];
    }

  return self;  
}

- (void)createWorkspaceIcon;
{
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];	  
  NSString *wsname = [defaults stringForKey: @"GSWorkspaceApplication"];
  NSString *path;
  FSNode *node;
  DockIcon *icon;
  
  if (wsname == nil) {
    wsname = [gw gworkspaceProcessName];
  }

  path = [ws fullPathForApplication: wsname];
  if (path == nil) {
    path = [[NSBundle mainBundle] bundlePath];
  }
  node = [FSNode nodeWithPath: path];
  
  icon = [[DockIcon alloc] initForNode: node
                               appName: wsname
                              iconSize: iconSize];
  [icon setHighlightColor: backColor];
  [icon setWsIcon: YES];
  [icon setDocked: YES];
  [icon setSingleClickLaunch: singleClickLaunch];
  [icons insertObject: icon atIndex: 0];
  [self addSubview: icon];
  RELEASE (icon);
}

- (void)createTrashIcon
{
  NSString *path = [manager trashPath];
  FSNode *node = [FSNode nodeWithPath: path];
  DockIcon *icon = [[DockIcon alloc] initForNode: node
                                         appName: nil
                                        iconSize: iconSize];

  [icon setHighlightColor: backColor];
  [icon setTrashIcon: YES];  
  [icon setSingleClickLaunch: singleClickLaunch];
  [icon setDocked: YES];                         
  [icons insertObject: icon atIndex: [icons count]];
  [self addSubview: icon];
  RELEASE (icon);
  
  [manager addWatcherForPath: path];
}

- (DockIcon *)addIconForApplicationAtPath:(NSString *)path
                                 withName:(NSString *)name
                                  atIndex:(NSInteger)index
{
  if (path == nil || [path length] == 0) {
    return nil;
  }
  
  if ([fm fileExistsAtPath: path]) {
    FSNode *node = [FSNode nodeWithPath: path];
    
    if (node == nil) {
      return nil;
    }
    
    if ([node isApplication]) {
      int icnindex;
      DockIcon *icon = [[DockIcon alloc] initForNode: node
                                             appName: name
                                            iconSize: iconSize];
      
      if (icon == nil) {
        return nil;
      }

      /* Creating the icon can wait on Distributed Objects, and while it
       * waits the run loop delivers other launch notifications for the same
       * application, which add its icon.  Inserting this one as well left a
       * second icon that bounced forever, since the launch only ever
       * completed on the other one. */
      DockIcon *existing = [self iconForApplicationPath: path name: name];
      if (existing != nil) {
        RELEASE (icon);
        return existing;
      }

      /* Applications stay before the divider, whatever index they are
       * given: past it are the folders and the Trash. */
      if (index == -1) {
        icnindex = [self firstDocumentIndex];
      } else {
        icnindex = (index < [icons count]) ? (index + 1) : [icons count];
        icnindex = MIN (icnindex, [self firstDocumentIndex]);
      }

      [icon setHighlightColor: backColor];
      [icons insertObject: icon atIndex: icnindex];
      [icon setSingleClickLaunch: singleClickLaunch];
      [self addSubview: icon];
      RELEASE (icon);
      
      [manager addWatcherForPath: [node path]];
      
      return icon;
    }
  }
  
  return nil;
}

/* Where the section of folders and the Trash begins. */
- (NSUInteger)firstDocumentIndex
{
  NSUInteger i;

  for (i = 0; i < [icons count]; i++)
    {
      DockIcon *icon = [icons objectAtIndex: i];

      if ([icon isFolderIcon] || [icon isTrashIcon])
        return i;
    }

  return [icons count];
}

- (NSUInteger)trashIndex
{
  NSUInteger i = [icons indexOfObjectIdenticalTo: [self trashIcon]];

  return (i == NSNotFound) ? [icons count] : i;
}

- (DockIcon *)folderIconForPath:(NSString *)path
{
  NSUInteger i;

  for (i = 0; i < [icons count]; i++)
    {
      DockIcon *icon = [icons objectAtIndex: i];

      if ([icon isFolderIcon] && [[icon path] isEqual: path])
        return icon;
    }

  return nil;
}

- (DockIcon *)addFolderIconAtPath:(NSString *)path
                          atIndex:(NSUInteger)index
{
  FSNode *node = [FSNode nodeWithPath: path];
  NSUInteger first = [self firstDocumentIndex];
  NSUInteger last = [self trashIndex];
  DockIcon *icon;

  if (node == nil || [node isValid] == NO
      || [node isDirectory] == NO || [node isPackage])
    return nil;

  /* The name as it is, extension and all: it is not an application's. */
  icon = [[DockIcon alloc] initForNode: node
                               appName: [node name]
                              iconSize: iconSize];
  if (icon == nil)
    return nil;

  index = MAX (first, MIN (index, last));

  [icon setHighlightColor: backColor];
  [icon setSingleClickLaunch: singleClickLaunch];
  [icon setDocked: YES];
  [icons insertObject: icon atIndex: index];
  [self addSubview: icon];
  RELEASE (icon);

  /* Told when the folder is deleted or moved away, like an application. */
  [manager addWatcherForPath: path];

  return icon;
}

- (void)loadDockedFolders
{
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
  NSArray *paths = [defaults arrayForKey: @"folders"];
  NSDictionary *stacks = [defaults dictionaryForKey: @"folderstacks"];
  NSUInteger i;

  for (i = 0; i < [paths count]; i++)
    {
      NSString *path = [paths objectAtIndex: i];
      NSDictionary *stack;
      DockIcon *icon;

      if ([path isKindOfClass: [NSString class]] == NO
          || [self folderIconForPath: path] != nil)
        continue;

      icon = [self addFolderIconAtPath: path atIndex: [icons count]];
      stack = [stacks objectForKey: path];
      if (icon != nil && [stack isKindOfClass: [NSDictionary class]])
        {
          [icon setStackViewStyle: [[stack objectForKey: @"view"] intValue]];
          [icon setStackSort: [[stack objectForKey: @"sort"] intValue]];
        }
    }
}

- (void)addDraggedIcon:(NSData *)icondata
               atIndex:(NSInteger)index
{
  NSDictionary *dict = [NSUnarchiver unarchiveObjectWithData: icondata];
  NSString *name = [dict objectForKey: @"name"];
  NSString *path = [dict objectForKey: @"path"];
  DockIcon *icon = [self addIconForApplicationAtPath: path 
                                            withName: name 
                                             atIndex: index];

  [icon setDocked: [[dict objectForKey: @"docked"] boolValue]];
  [icon setLaunched: [[dict objectForKey: @"launched"] boolValue]];
  [icon setHidden: [[dict objectForKey: @"hidden"] boolValue]];
}

- (void)removeIcon:(DockIcon *)icon
{
  if (icon == nil) return;
  /* Hold a strong reference for the whole removal.  An app-termination DO
   * notification can otherwise arrive while the icon is being torn down and
   * the object be deallocated under us (use-after-free in objc_msgSend - the
   * Workspace crash that made menu_follows_app/window_placement flaky). */
  [icon retain];
  /* Idempotency: a duplicate app-terminated: (e.g. both the NSTask-exit and
   * the DO-invalidation paths) must not re-remove an icon already gone. */
  if ([icons indexOfObjectIdenticalTo: icon] == NSNotFound) {
    [icon release];
    return;
  }
  [manager removeWatcherForPath: [[icon node] path]];
  [DockStack closeForIcon: icon];
  
  if ([icon superview]) {
    [icon removeFromSuperview];
  }
  if ([icon isLaunched]) {
    [icon setLaunched: NO];
  }
  [icons removeObject: icon];
  [self tile];
  
  /* Persist the removal immediately */
  [self saveDockConfiguration];
  [icon release];
}

- (DockIcon *)iconForApplicationPath:(NSString *)path
{
  NSUInteger i;

  for (i = 0; i < [icons count]; i++) {
    DockIcon *icon = [icons objectAtIndex: i];

    /* A kept folder is never an application, whatever it is called. */
    if ([icon isFolderIcon]) {
      continue;
    }
    if ([[icon path] isEqual: path]) {
      return icon;
    }
    if ([[[icon path] stringByResolvingSymlinksInPath] isEqual: path]) {
      return icon;
    }
  }

  return nil;
}

- (DockIcon *)iconForApplicationName:(NSString *)name
{
  NSUInteger i;

  for (i = 0; i < [icons count]; i++) {
    DockIcon *icon = [icons objectAtIndex: i];

    if ([icon isFolderIcon] == NO && [[icon appName] isEqual: name]) {
      return icon;
    }
  }

  return nil;
}

- (DockIcon *)iconForApplicationPath:(NSString *)path
                                name:(NSString *)name
{
  DockIcon *icon = (path != nil) ? [self iconForApplicationPath: path] : nil;

  if (icon == nil && name != nil) {
    icon = [self iconForApplicationName: name];
  }
  return icon;
}

- (void)setAppIsX11Only:(BOOL)value
                forPath:(NSString *)path
                   name:(NSString *)name
{
  [[self iconForApplicationPath: path name: name] setIsX11OnlyApp: value];
}

- (DockIcon *)workspaceAppIcon
{
  NSUInteger i;
  
  for (i = 0; i < [icons count]; i++) {
    DockIcon *icon = [icons objectAtIndex: i];
    
    if ([icon isWsIcon]) {
      return icon;
    }
  }
  
  return nil;
}

- (DockIcon *)trashIcon
{
  NSUInteger i;
  
  for (i = 0; i < [icons count]; i++) {
    DockIcon *icon = [icons objectAtIndex: i];
    
    if ([icon isTrashIcon]) {
      return icon;
    }
  }
  
  return nil;
}

- (DockIcon *)iconContainingPoint:(NSPoint)p
{
  NSUInteger i;
  
  for (i = 0; i < [icons count]; i++) {
    DockIcon *icon = [icons objectAtIndex: i];
    NSRect r = [icon frame];
    
    if (NSPointInRect(p, NSInsetRect(r, 0.0, 2.0))) {
      return icon;
    }
  }
  
  return nil;
}

- (void)setDndSourceIcon:(DockIcon *)icon
{
  dndSourceIcon = icon;
}

- (void)appWillLaunch:(NSString *)appPath
              appName:(NSString *)appName
{
  [self appWillLaunch: appPath appName: appName pid: 0];
}

- (void)appWillLaunch:(NSString *)appPath
              appName:(NSString *)appName
                  pid:(pid_t)pid
{
  if (appName == nil) return;
  if ([appName isEqual: [gw gworkspaceProcessName]] == NO) {
    /* Honor GSSuppressAppIcon — skip apps that declare they should not
     * appear in the Dock (e.g. WindowManager). */
    NSBundle *bundle = [NSBundle bundleWithPath: appPath];
    if ([[bundle objectForInfoDictionaryKey: @"GSSuppressAppIcon"] boolValue]) {
      DockIcon *icon = [self iconForApplicationPath: appPath];
      if (icon) {
        [self removeIcon: icon];
      }
      return;
    }

    DockIcon *icon = [self iconForApplicationPath: appPath name: appName];

    if (icon == nil) {
      icon = [self addIconForApplicationAtPath: appPath
                                      withName: appName
                                       atIndex: -1];
    }
    
    if (icon && pid > 0) {
      [icon setAppPID: pid];
      [self updateIconGeometryForDockIcon: icon];
    }
  
    [self tile];
    if (icon && ([icon isLaunched] == NO)) {
      [icon animateLaunch];
    }
  }
}

- (void)appDidLaunch:(NSString *)appPath
             appName:(NSString *)appName
{
  [self appDidLaunch: appPath appName: appName pid: 0];
}

- (void)appDidLaunch:(NSString *)appPath
             appName:(NSString *)appName
                 pid:(pid_t)pid
{
  if (appName != nil) {
  } else
    {
      return;
    }
  if ([appName isEqual: [gw gworkspaceProcessName]] == NO) {
    /* Honor GSSuppressAppIcon — skip apps that declare they should not
     * appear in the Dock (e.g. WindowManager). */
    NSBundle *bundle = [NSBundle bundleWithPath: appPath];
    if ([[bundle objectForInfoDictionaryKey: @"GSSuppressAppIcon"] boolValue]) {
      DockIcon *icon = [self iconForApplicationPath: appPath];
      if (icon) {
        [self removeIcon: icon];
      }
      return;
    }

    DockIcon *icon = [self iconForApplicationPath: appPath name: appName];

    if (icon == nil) {
      icon = [self addIconForApplicationAtPath: appPath
                                      withName: appName
                                       atIndex: -1];
      [self tile];
    }
    
    if (icon) {
      if (pid > 0) {
        [icon setAppPID: pid];
        [self updateIconGeometryForDockIcon: icon];
      }
      [icon setLaunched: YES];
    }
  }
}

- (DockIcon *)iconForApplicationPID:(pid_t)pid
{
  NSUInteger i;
  
  if (pid <= 0) return nil;
  
  for (i = 0; i < [icons count]; i++) {
    DockIcon *icon = [icons objectAtIndex: i];
    
    if ([icon appPID] == pid) {
      return icon;
    }
  }
  
  return nil;
}

- (void)appTerminated:(NSString *)appPath
             appName:(NSString *)appName
{
  if (appName == nil) return;
  if ([appName isEqual: [gw gworkspaceProcessName]] == NO) {
    DockIcon *icon = [self iconForApplicationPath: appPath name: appName];

    if (icon) {
      [icon setAppPID: 0]; /* Clear PID on termination */
      if (([icon isDocked] == NO) && ([icon isSpecialIcon] == NO)) {
        [self removeIcon: icon];
      } else {
        [icon setAppHidden: NO];
        [icon setLaunched: NO];
      }
    }
  }
}

- (void)appDidHide:(NSString *)appPath
          appName:(NSString *)appName
{
  if (appName == nil) return;
  if ([appName isEqual: [gw gworkspaceProcessName]] == NO) {
    DockIcon *icon = [self iconForApplicationPath: appPath];

    if (icon) {
      [icon setAppHidden: YES];
    }
  }
}

- (void)appDidUnhide:(NSString *)appPath
            appName:(NSString *)appName
{
  if (appName == nil) return;
  if ([appName isEqual: [gw gworkspaceProcessName]] == NO) {
    DockIcon *icon = [self iconForApplicationPath: appPath];

    if (icon) {
      [icon setAppHidden: NO];
    }
  }
}

- (void)iconMenuAction:(id)sender
{
  NSString *title = [(NSMenuItem *)sender title];
  id representedObject = [(NSMenuItem *)sender representedObject];
  
  if ([title isEqual: NSLocalizedString(@"Show In File Viewer", @"")]) {
    NSString *path = representedObject;
    NSString *basePath = [path stringByDeletingLastPathComponent];
  
    [gw selectFile: path inFileViewerRootedAtPath: basePath];

  } else if ([title isEqual: NSLocalizedString(@"Open", @"")]) {
    [gw newViewerAtPath: representedObject];
  
  } else if ([title isEqual: NSLocalizedString(@"Keep in Dock", @"")]) {
    DockIcon *icon = (DockIcon *)representedObject;
    [icon setDocked: YES];
    [self saveDockConfiguration];
    [self tile];
    
  } else if ([title isEqual: NSLocalizedString(@"Remove from Dock", @"")]) {
    DockIcon *icon = (DockIcon *)representedObject;
    [icon setDocked: NO];
    /* Save immediately - remove from plist right away */
    [self saveDockConfiguration];
    /* Only remove the icon if it's NOT currently showing a dot (not running) */
    if (([icon isLaunched] == NO) && ([icon isSpecialIcon] == NO)) {
      [self removeIcon: icon];
    } else {
      [self tile];
    }
    
  } else {
    GWLaunchedApp *app = (GWLaunchedApp *)representedObject;
  
    if ([app isRunning] == NO) {
      /* terminated while the icon menu is open */
      return;
    }
  
    if ([title isEqual: NSLocalizedString(@"Hide", @"")]) {
      [app hideApplication];
    } else if ([title isEqual: NSLocalizedString(@"Unhide", @"")]) {
      [app unhideApplication];
    } else if ([title isEqual: NSLocalizedString(@"Bring to Front", @"")]) {
      if ([app isHidden]) {
        [app unhideApplication];
      }
      [app activateApplication];
    } else if ([title isEqual: NSLocalizedString(@"Quit", @"")]) {
      [app terminateApplication];
    }  
  }
}

- (void)setSingleClickLaunch:(BOOL)value
{
  NSUInteger i;

  singleClickLaunch = value;
  for (i = 0; i < [icons count]; i++)
    {
      DockIcon *icon = [icons objectAtIndex: i];
      [icon setSingleClickLaunch: singleClickLaunch];
    }
}

- (void)setPosition:(DockPosition)pos
{
  position = pos;
  [self tile];
}

- (DockPosition)position
{
  return position;
}

- (void)setStyle:(DockStyle)s
{
  if(style != s)
    {
      if (s == DockStyleClassic)
	{
	  [self setBackColor: [NSColor grayColor]];
	}
      else if (s == DockStyleModern)
	{
	  [self setBackColor: [[NSColor grayColor] colorWithAlphaComponent: 0.33]];
	}
    }
  style = s;
}

- (DockStyle)style
{
  return style;
}

- (void)setBackColor:(NSColor *)color
{
  NSColor *hlgtcolor = [color highlightWithLevel: 0.2];
  int i;
  
  for (i = 0; i < [icons count]; i++) {
    [[icons objectAtIndex: i] setHighlightColor: hlgtcolor];
  }
  
  ASSIGN (backColor, hlgtcolor);
  if ([self superview]) {
    [self tile];
  }
}

/* The Dock lays out along one axis: from the left when it is at the bottom
 * of the screen, from the top when it is at a side.  This turns a span
 * along that axis into a tile of the given thickness, kept against the edge
 * of the screen the Dock sits on so that magnified icons grow away from it. */
- (NSRect)rectForSpanStart:(CGFloat)start
                    length:(CGFloat)length
                 thickness:(CGFloat)thickness
{
  NSRect bounds = [self bounds];

  if (position == DockPositionBottom)
    return NSMakeRect(start, 0, length, thickness);

  if (position == DockPositionLeft)
    return NSMakeRect(0, bounds.size.height - start - length,
                      thickness, length);

  return NSMakeRect(bounds.size.width - thickness,
                    bounds.size.height - start - length,
                    thickness, length);
}

/* Places the icons, the line between the sections and the gaps a drag opens
 * one after another along the Dock, and works out how far the bar itself
 * reaches once the icons around the pointer have pushed it apart. */
- (void)layoutIcons
{
  /* As much of the effect as is showing; at rest this spreads nothing and
   * every tile is laid out where it lies. */
  DockMagnification shown = DockMagnificationScale(magnification,
                                                   magnifyFraction);
  NSUInteger docs = [self firstDocumentIndex];
  BOOL divided = (docs > 0) && (docs < [icons count]);
  CGFloat dividerLength = divided ? DIVIDER_SIZE : 0;
  /* Armed, the bar lies in the middle of the room kept for the whole
   * effect, so that no tile ever needs more of it than there is. */
  CGFloat lead = magnifyArmed ? magnification.spread : 0.0;
  CGFloat pos = lead;
  CGFloat barStart, barEnd, start, size;
  NSUInteger i;

  dividerRect = NSZeroRect;
  folderGapRect = NSZeroRect;

  DockMagnificationSpan(shown, magnifyPos, pos, 0, &barStart, &size);

  for (i = 0; i < [icons count]; i++)
    {
      DockIcon *icon = [icons objectAtIndex: i];

      if (divided && (i == docs))
        {
          DockMagnificationSpan(shown, magnifyPos, pos, dividerLength,
                                &start, &size);
          dividerRect = [self rectForSpanStart: start
                                        length: size
                                     thickness: baseCell];
          pos += dividerLength;
        }

      if ((NSInteger)i == folderTargetIndex)
        {
          DockMagnificationSpan(shown, magnifyPos, pos, baseCell,
                                &start, &size);
          folderGapRect = [self rectForSpanStart: start
                                          length: size
                                       thickness: size];
          pos += baseCell;
        }

      DockMagnificationSpan(shown, magnifyPos, pos, baseCell, &start, &size);
      [icon setMagnifiedIconSize:
              ((magnifyFraction > 0.0) ? (iconSize * size / baseCell) : 0.0)
                           frame: [self rectForSpanStart: start
                                                  length: size
                                               thickness: size]];
      pos += baseCell;

      if ((targetIndex != -1) && ((NSInteger)i == targetIndex))
        pos += baseCell;
    }

  /* The bar runs from where the first tile begins to where the last one
   * ends, so it grows with the icons instead of leaving them hanging over
   * its ends. */
  DockMagnificationSpan(shown, magnifyPos, pos, 0, &barEnd, &size);
  barRect = [self rectForSpanStart: barStart
                            length: barEnd - barStart
                         thickness: baseCell];

  [self setNeedsDisplay: YES];
}

- (void)tile
{
  NSView *view = [self superview];
  NSRect scrrect = [[[NSScreen screens] objectAtIndex:0] frame];
  int oldIcnSize = iconSize;
  CGFloat maxheight = scrrect.size.height;
  NSRect rect = NSZeroRect;
  NSUInteger i;
  NSUInteger docs = [self firstDocumentIndex];
  /* Only a Dock with something on both sides is divided. */
  BOOL divided = (docs > 0) && (docs < [icons count]);
  CGFloat dividerLength = divided ? DIVIDER_SIZE : 0;
  /* The icons, and the gaps opened where a dragged item would go. */
  CGFloat slots = [icons count] + ((targetIndex != -1) ? 1 : 0)
                                + ((folderTargetIndex != -1) ? 1 : 0);
  CGFloat sf = _dockScaleFactor();
  CGFloat cell, scaledCell, barLength, viewLength, viewThickness, screenLength;
  CGFloat large;
  BOOL inOwnDockWindow;

  iconSize = MAX_ICN_SIZE;

  /* Compute unscaled cell size (used for icon subview layout inside the view,
   * where the backend's HiDPI transform is already active). */
  cell = ceil(iconSize / 3 * 4);

  /* Use SCALED cell for the dock window frame (screen pixel coordinates). */
  scaledCell = cell * sf;

  maxheight -= (scaledCell * 2);

  while ((slots * scaledCell + dividerLength * sf) > maxheight) {
    iconSize -= ICN_INCR;
    cell = ceil(iconSize / 3 * 4);
    scaledCell = cell * sf;

    if (iconSize <= MIN_ICN_SIZE) {
      break;
    }
  }

  baseCell = cell;
  barLength = slots * cell + dividerLength;

  /* The tiles grow along the curve of the expired patent US7434177, over an
   * effect region a few tiles wide to either side of the pointer, and only
   * as far apart as the screen beside the bar allows. */
  screenLength = ((position == DockPositionBottom)
                  ? scrrect.size.width : scrrect.size.height) / sf;
  /* An icon larger than the tile it sits in is what makes the effect; below
   * that there is nothing to show, and the largest is kept within reach of
   * the sizes the icons are drawn at. */
  large = MIN(largeIconSize, MAX_LARGE_ICN_SIZE);
  magnification = DockMagnificationMake(cell,
                                        magnifyEnabled
                                          ? (cell * large / iconSize) : cell,
                                        MAGNIFY_CELLS * cell);
  /* The bar keeps the same distance from the ends of the screen that it is
   * laid out with, magnified or not. */
  magnification = DockMagnificationFit(magnification,
                                       screenLength - 2 * cell - barLength);

  /* Armed, the Dock takes the room the icons can grow into all at once: as
   * tall as the largest tile, and long enough for the spread to either
   * side.  The window is then left alone for as long as the pointer plays
   * with the Dock, so that growing an icon never moves it.  At rest the
   * Dock is just the bar again. */
  viewLength = magnifyArmed ? (barLength + 2 * magnification.spread) : barLength;
  viewThickness = magnifyArmed ? magnification.magnifiedSize : cell;

  if (position == DockPositionBottom)
  {
    rect.size.width = viewLength * sf;
    rect.size.height = viewThickness * sf;
  }
  else
  {
    rect.size.width = viewThickness * sf;
    rect.size.height = viewLength * sf;
  }

  // Offset by the primary screen's origin so the dock lands on the correct
  // monitor when the desktop window spans the full virtual desktop.
  CGFloat scrOriginX = scrrect.origin.x;
  CGFloat scrOriginY = scrrect.origin.y;

  if (position == DockPositionBottom)
    {
      rect.origin.x = scrOriginX + ceil((scrrect.size.width - rect.size.width) / 2);
      rect.origin.y = scrOriginY;
    }
  else if (position == DockPositionLeft)
    {
      rect.origin.x = scrOriginX;
      rect.origin.y = scrOriginY + ceil((scrrect.size.height - rect.size.height) / 2);
    }
  else // DockPositionRight
    {
      rect.origin.x = scrOriginX + scrrect.size.width - rect.size.width;
      rect.origin.y = scrOriginY + ceil((scrrect.size.height - rect.size.height) / 2);
    }

  
  /*
   * When the dock lives in its own GWDockWindow, resize the window to the
   * computed screen-coordinate rect instead of setting this view's frame
   * (the window's content view is expected to stay at {0,0} within the
   * window content area).
   */
  inOwnDockWindow = [[self window] isKindOfClass: [GWDockWindow class]];

  if (inOwnDockWindow)
    {
      [[self window] setFrame: rect display: YES];
      [self setNeedsDisplay: YES];
    }
  else
    {
      if (view)
        {
          [view setNeedsDisplayInRect: [self frame]];
        }
      [self setFrame: rect];
    }

  /* Icon image size stays unscaled (48pt at most); only the pointer
   * magnifies it. */
  if (oldIcnSize != iconSize)
    {
      for (i = 0; i < [icons count]; i++)
        [[icons objectAtIndex: i] setIconSize: iconSize];
    }

  [self layoutIcons];

  if (view && (inOwnDockWindow == NO)) {
    [view setNeedsDisplayInRect: [self frame]];
  }

  [self updateIconGeometries];
}

- (NSRect)barFrame
{
  NSRect wframe;
  CGFloat sf;

  if (([self window] == nil) || NSIsEmptyRect(barRect))
    return NSZeroRect;

  /* The Dock places its icons in unscaled points and sizes its window in
   * screen pixels, so the bar is converted the same way. */
  wframe = [[self window] frame];
  sf = _dockScaleFactor();

  return NSMakeRect(wframe.origin.x + barRect.origin.x * sf,
                    wframe.origin.y + barRect.origin.y * sf,
                    barRect.size.width * sf,
                    barRect.size.height * sf);
}

- (NSRect)x11IconRectForDockIcon:(DockIcon *)icon
{
  if (!icon || ![icon window]) {
    return NSZeroRect;
  }

  NSRect iconBounds = [icon bounds];
  NSRect rectInWindow = [icon convertRect: iconBounds toView: nil];
  NSRect rectOnScreen = [[icon window] convertRectToScreen: rectInWindow];
  NSScreen *screen = [[icon window] screen] ?: [NSScreen mainScreen];
  CGFloat screenHeight = [screen frame].size.height;

  NSRect x11Rect = rectOnScreen;
  x11Rect.origin.y = screenHeight - (rectOnScreen.origin.y + rectOnScreen.size.height);

  return x11Rect;
}

- (void)updateIconGeometryForDockIcon:(DockIcon *)icon
{
  if (!icon) return;

  pid_t pid = [icon appPID];
  NSRect x11Rect = [self x11IconRectForDockIcon: icon];
  if (NSEqualRects(x11Rect, NSZeroRect)) return;

  GWX11WindowManager *wm = [GWX11WindowManager sharedManager];
  if (pid > 0) {
    [wm setIconGeometry: x11Rect forPID: pid];
  } else if ([icon appName] && [[icon appName] length] > 0) {
    [wm setIconGeometry: x11Rect forName: [icon appName]];
  }
}

- (void)updateIconGeometries
{
  NSUInteger i;
  for (i = 0; i < [icons count]; i++) {
    DockIcon *icon = [icons objectAtIndex: i];
    if ([icon isSpecialIcon]) continue;
    if ([icon appPID] <= 0) continue;
    [self updateIconGeometryForDockIcon: icon];
  }
}

/* Applications by their place in the Dock, as they have always been kept;
 * folders in their own list, in order. */
- (NSDictionary *)dockedApplicationEntries
{
  NSMutableDictionary *dict = [NSMutableDictionary dictionary];
  NSUInteger i;

  for (i = 0; i < [icons count]; i++)
    {
      DockIcon *icon = [icons objectAtIndex: i];

      if ([icon isApplicationIcon] && [icon isDocked])
	{
	  /* Save both name and path so non-GNUstep apps can be restored */
	  NSMutableDictionary *appEntry = [NSMutableDictionary dictionary];
	  [appEntry setObject: [icon appName] forKey: @"name"];
	  [appEntry setObject: [[icon node] path] forKey: @"path"];
	  [dict setObject: appEntry forKey: [[NSNumber numberWithInt: i] stringValue]];
	}
    }

  return dict;
}

- (NSArray *)dockedFolderPaths
{
  NSMutableArray *paths = [NSMutableArray array];
  NSUInteger i;

  for (i = 0; i < [icons count]; i++)
    {
      DockIcon *icon = [icons objectAtIndex: i];

      if ([icon isFolderIcon] && [icon isDocked])
        [paths addObject: [icon path]];
    }

  return paths;
}

/* How each kept folder shows its stack, by path; beside "folders", which
 * keeps the plain list of paths it always had. */
- (NSDictionary *)dockedFolderStacks
{
  NSMutableDictionary *stacks = [NSMutableDictionary dictionary];
  NSUInteger i;

  for (i = 0; i < [icons count]; i++)
    {
      DockIcon *icon = [icons objectAtIndex: i];

      if ([icon isFolderIcon] && [icon isDocked])
        {
          [stacks setObject: [NSDictionary dictionaryWithObjectsAndKeys:
                               [NSNumber numberWithInt: [icon stackViewStyle]], @"view",
                               [NSNumber numberWithInt: [icon stackSort]], @"sort", nil]
                     forKey: [icon path]];
        }
    }

  return stacks;
}

- (void)saveDockConfiguration
{
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];	

  [defaults setObject: [self dockedApplicationEntries] forKey: @"applications"];
  [defaults setObject: [self dockedFolderPaths] forKey: @"folders"];
  [defaults setObject: [self dockedFolderStacks] forKey: @"folderstacks"];
  [defaults synchronize];
}

- (void)updateDefaults
{
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];	
  NSUInteger i;  

  [defaults setObject: [NSNumber numberWithInt: style]
               forKey: @"dockstyle"];
  [defaults setBool: singleClickLaunch forKey: @"singleclicklaunch"];
  /* The magnification settings are not written back: the Dock never changes
   * them itself, and saving them over what is on disk would undo a
   * "defaults write" the moment the Dock is next shut down. */
  [defaults removeObjectForKey: @"dockmagnifiedsize"];
  [defaults setObject: [self dockedApplicationEntries] forKey: @"applications"];
  [defaults setObject: [self dockedFolderPaths] forKey: @"folders"];
  [defaults setObject: [self dockedFolderStacks] forKey: @"folderstacks"];

  for (i = 0; i < [icons count]; i++)
    {
      DockIcon *icon = [icons objectAtIndex: i];    

      if (([icon isSpecialIcon] == NO) && [icon isDocked])
	{
	  [manager removeWatcherForPath: [[icon node] path]];
	}

      [icon setSingleClickLaunch: singleClickLaunch];
    }

  [manager removeWatcherForPath: [manager trashPath]];
}

- (void)checkRemovedApp:(id)sender
{
  DockIcon *icon = (DockIcon *)[sender userInfo];
  
  if ([[icon node] isValid] == NO) {
    [self removeIcon: icon];
  }
}

#pragma mark - magnification

- (BOOL)magnificationEnabledDefault
{
  id defEntry = [[NSUserDefaults standardUserDefaults]
                  objectForKey: @"dockmagnification"];

  return (defEntry == nil) ? YES : [defEntry boolValue];
}

- (CGFloat)largeIconSizeDefault
{
  id defEntry = [[NSUserDefaults standardUserDefaults]
                  objectForKey: @"docklargesize"];

  return (defEntry == nil) ? LARGE_ICN_SIZE : [defEntry floatValue];
}

- (void)magnificationDefaultsDidChange:(NSNotification *)notif
{
  [self setMagnificationEnabled: [self magnificationEnabledDefault]];
  [self setLargeIconSize: [self largeIconSizeDefault]];
}

- (void)setMagnificationEnabled:(BOOL)value
{
  if (value == magnifyEnabled)
    return;

  magnifyEnabled = value;
  magnifyPhase = 0.0;
  magnifyFraction = 0.0;
  magnifyArmed = NO;
  [self tile];
  [self setMagnificationTracking: ([self window] != nil)];
}

- (BOOL)isMagnificationEnabled
{
  return magnifyEnabled;
}

- (void)setLargeIconSize:(CGFloat)size
{
  if (size == largeIconSize)
    return;

  largeIconSize = size;
  magnifyPhase = 0.0;
  magnifyFraction = 0.0;
  magnifyArmed = NO;
  /* Laying the Dock out again works out how far the new size can go. */
  [self tile];
}

- (CGFloat)largeIconSize
{
  return largeIconSize;
}

/* How long the Dock can wait before looking at the pointer again. */
- (NSTimeInterval)magnifyIntervalForDistance:(CGFloat)distance
                                        near:(CGFloat)near
{
  NSTimeInterval wait;

  if (magnifyArmed || (distance < near))
    return MAGNIFY_FRAME_INTERVAL;

  wait = (distance - near) / MAGNIFY_POINTER_SPEED;

  if (wait < MAGNIFY_FRAME_INTERVAL)
    return MAGNIFY_FRAME_INTERVAL;
  if (wait > MAGNIFY_IDLE_INTERVAL)
    return MAGNIFY_IDLE_INTERVAL;

  return wait;
}

- (void)setMagnifyInterval:(NSTimeInterval)interval
{
  NSRunLoop *loop = [NSRunLoop currentRunLoop];

  /* Putting up a new timer for every small change would cost more than
   * looking a little too often. */
  if (magnifyTimer
      && (fabs(interval - magnifyInterval) < magnifyInterval / 4.0))
    return;

  [magnifyTimer invalidate];
  magnifyInterval = interval;
  magnifyTimer = [NSTimer timerWithTimeInterval: interval
                                         target: self
                                       selector: @selector(magnifyTick:)
                                       userInfo: nil
                                        repeats: YES];
  /* Also while a menu or a drag is being tracked: the pointer goes on
   * moving there, and a Dock left half grown would stay that way. */
  [loop addTimer: magnifyTimer forMode: NSDefaultRunLoopMode];
  [loop addTimer: magnifyTimer forMode: NSEventTrackingRunLoopMode];
}

- (void)setMagnificationTracking:(BOOL)value
{
  if (value == NO)
    {
      [magnifyTimer invalidate];
      magnifyTimer = nil;
      magnifyInterval = 0.0;
      [self endMagnification];
      return;
    }

  if (magnifyEnabled == NO)
    return;

  magnifyTime = 0.0;
  [self setMagnifyInterval: MAGNIFY_IDLE_INTERVAL];
}

- (void)viewDidMoveToWindow
{
  [super viewDidMoveToWindow];
  [self setMagnificationTracking: ([self window] != nil)];
}

/* Where the pointer is along the Dock: from the left when it is at the
 * bottom of the screen, from the top when it is at a side.
 *
 * Taken from the pointer itself and the window as the Dock has just placed
 * it: the Dock follows the pointer on a timer, and there is no event whose
 * coordinates it could use instead. */
- (CGFloat)axisPositionForPointer:(NSPoint)p
{
  NSRect wframe = [[self window] frame];
  NSRect bounds = [self bounds];
  CGFloat sf = _dockScaleFactor();
  CGFloat lead = magnifyArmed ? magnification.spread : 0.0;
  CGFloat length = (position == DockPositionBottom)
    ? bounds.size.width : bounds.size.height;
  CGFloat pos = (position == DockPositionBottom)
    ? ((p.x - NSMinX(wframe)) / sf)
    : ((NSMaxY(wframe) - p.y) / sf);

  /* A pointer past the end of the bar would push every tile away from
   * itself, so that the icons walk off as it comes nearer.  It is taken as
   * being at the end it is coming for, which keeps that end where it is and
   * lets the Dock spread the other way. */
  if (pos < lead)
    return lead;
  if (pos > length - lead)
    return length - lead;

  return pos;
}

/* How far the pointer is from the bar, which is nothing while it is on it. */
- (CGFloat)distanceFromBarToPointer:(NSPoint)p
{
  NSRect bar = [self barFrame];
  CGFloat dx = 0.0;
  CGFloat dy = 0.0;

  if (NSIsEmptyRect(bar))
    return CGFLOAT_MAX;

  if (p.x < NSMinX(bar))
    dx = NSMinX(bar) - p.x;
  else if (p.x > NSMaxX(bar))
    dx = p.x - NSMaxX(bar);

  if (p.y < NSMinY(bar))
    dy = NSMinY(bar) - p.y;
  else if (p.y > NSMaxY(bar))
    dy = p.y - NSMaxY(bar);

  return sqrt(dx * dx + dy * dy) / _dockScaleFactor();
}

/* Follows the pointer: the nearer it comes, the more of the effect is
 * shown, and the effect eases towards that rather than jumping to it.  The
 * room for it is taken while there is still nothing to see, and given back
 * once there is nothing left. */
- (void)magnifyTick:(NSTimer *)timer
{
  NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
  CGFloat elapsed = (magnifyTime > 0.0) ? (now - magnifyTime)
                                        : MAGNIFY_FRAME_INTERVAL;
  CGFloat distance, rise, target, phase, fraction, pos;
  BOOL dragging = (isDragTarget || (dndSourceIcon != nil));
  /* Asked for once a frame: every one of these is a question to the X
   * server, and the Dock is the only one that has to keep asking. */
  NSPoint pointer;

  magnifyTime = now;

  if ((magnifyEnabled == NO) || ([self window] == nil)
      || ([[self window] isVisible] == NO) || (magnification.spread <= 0.0))
    return;

  pointer = [NSEvent mouseLocation];
  distance = [self distanceFromBarToPointer: pointer];
  /* How far the tiles stand out beyond the bar at the moment: the pointer
   * is on the Dock while it is on one of them. */
  rise = magnifyFraction * (magnification.magnifiedSize - baseCell);
  target = dragging ? 0.0 : DockMagnificationTarget(distance, rise);
  phase = DockMagnificationPhase(magnifyPhase, target, elapsed,
                                 MAGNIFY_DURATION);
  fraction = DockMagnificationSmooth(phase);

  /* The room for the effect is taken while there is still nothing to see,
   * and given back a little after the pointer has gone, so that a pointer
   * resting on the edge of the Dock does not do both every frame. */
  if ((phase > 0.0) && (magnifyArmed == NO))
    {
      magnifyArmed = YES;
      [self tile];
    }
  else if ((phase == 0.0) && magnifyArmed && (distance > baseCell / 2))
    {
      magnifyPhase = 0.0;
      magnifyFraction = 0.0;
      magnifyArmed = NO;
      [self tile];
    }

  magnifyPhase = phase;

  if (magnifyArmed)
    {
      pos = [self axisPositionForPointer: pointer];

      if ((fraction != magnifyFraction) || (pos != magnifyPos))
        {
          magnifyFraction = fraction;
          magnifyPos = pos;
          [self layoutIcons];
        }
    }

  [self setMagnifyInterval: [self magnifyIntervalForDistance: distance
                                                        near: rise + baseCell]];
}

- (void)endMagnification
{
  if ((magnifyArmed == NO) && (magnifyFraction == 0.0))
    return;

  magnifyPhase = 0.0;
  magnifyFraction = 0.0;
  magnifyArmed = NO;
  [self tile];
}

- (BOOL)isOpaque
{
  /* Modern style draws a semi-transparent gray, so the view is not opaque;
   * neither is a Dock holding room for the magnification, which only fills
   * its bar. */
  return (style != DockStyleModern) && (magnifyArmed == NO);
}

- (void)drawRect:(NSRect)rect
{
  // NSLog(@"DEBUG: Dock drawRect called, rect: %@, superview: %@", NSStringFromRect(rect), [self superview]);
  [super drawRect: rect];

  /* Only the bar itself is filled: while the pointer magnifies the Dock,
   * the view also covers the room the enlarged icons grow into. */
  [backColor set];
  NSRectFill(NSIntersectionRect(rect, barRect));

  if (NSIsEmptyRect(dividerRect) == NO)
    {
      NSRect line;

      /* A line across the Dock, short of its edges. */
      if (position == DockPositionBottom)
        line = NSMakeRect(NSMidX(dividerRect) - 1, NSMinY(dividerRect) + 8,
                          2, NSHeight(dividerRect) - 16);
      else
        line = NSMakeRect(NSMinX(dividerRect) + 8, NSMidY(dividerRect) - 1,
                          NSWidth(dividerRect) - 16, 2);

      [[backColor shadowWithLevel: 0.4] set];
      NSRectFill(line);
    }
}

@end


@implementation Dock (NodeRepContainer)

- (void)nodeContentsDidChange:(NSDictionary *)info
{
  NSString *operation = [info objectForKey: @"operation"];
	NSString *source = [info objectForKey: @"source"];	  
	NSString *destination = [info objectForKey: @"destination"];	 
	NSArray *files = [info objectForKey: @"files"];	 
  NSUInteger i, count;
  
  if ([operation isEqual: NSWorkspaceMoveOperation]
        || [operation isEqual: NSWorkspaceDestroyOperation]
		    || [operation isEqual: NSWorkspaceRecycleOperation]
        || [operation isEqual: @"WorkspaceRenameOperation"]) {
    count = [icons count];
    
    for (i = 0; i < count; i++) {
      DockIcon *icon = [icons objectAtIndex: i];
      FSNode *node = [icon node];
      
      if ([source isEqual: [node parentPath]]) {
        if ([files containsObject: [node name]]) {
          if ([icon isSpecialIcon] == NO) {
            [self removeIcon: icon];
            count--;
            i--;
          }
        }
      }
    }
  }  
  
  if ([operation isEqual: NSWorkspaceMoveOperation]
      || [operation isEqual: NSWorkspaceCopyOperation]
			|| [operation isEqual: NSWorkspaceRecycleOperation]) { 
    DockIcon *icon = [self trashIcon];
    NSString *trashPath = [[icon node] path];
    
    if ([destination isEqual: trashPath]) {
      [icon setTrashFull: YES];
    }
  }

  if ([operation isEqual: @"WorkspaceRecycleOutOperation"]
			    || [operation isEqual: @"WorkspaceemptyTrashOperation"]
          || [operation isEqual: NSWorkspaceMoveOperation]
          || [operation isEqual: NSWorkspaceDestroyOperation]) { 
    DockIcon *icon = [self trashIcon];
    FSNode *node = [icon node];
    NSString *trashPath = [node path];
    NSString *basePath;
    
    if ([operation isEqual: @"WorkspaceemptyTrashOperation"]
                || [operation isEqual: NSWorkspaceDestroyOperation]) { 
      basePath = destination;  
    } else {
      basePath = source;  
    }
    
    if ([basePath isEqual: trashPath]) {
      NSArray *subNodes = [node subNodes];
      NSUInteger count = [subNodes count];
    
      for (i = 0; i < [subNodes count]; i++) {
        if ([[subNodes objectAtIndex: i] isReserved]) {
          count --;
        }
      }
      
      if (count == 0) {
        [icon setTrashFull: NO];
      }
    }
  }
}

- (void)watchedPathChanged:(NSDictionary *)info
{
  CREATE_AUTORELEASE_POOL(arp);
  NSString *event = [info objectForKey: @"event"];
  NSString *path = [info objectForKey: @"path"];
    
  if ([event isEqual: @"GWWatchedPathDeleted"])
    {
      NSUInteger i;

      for (i = 0; i < [icons count]; i++) {
	DockIcon *icon = [icons objectAtIndex: i];
      
	if ([icon isSpecialIcon] == NO) {
	  FSNode *node = [icon node];
        
	  if ([path isEqual: [node path]]) {
	    [NSTimer scheduledTimerWithTimeInterval: 1.0
					     target: self
					   selector: @selector(checkRemovedApp:)
					   userInfo: icon
					    repeats: NO];
	  }
	}
      }
    
    }
  else if ([event isEqual: @"GWWatchedPathRenamed"])
    {
      /* A watched path was moved away */
      NSString *oldpath = [info objectForKey: @"oldpath"];
      NSUInteger i;

      if (oldpath)
        {
          for (i = 0; i < [icons count]; i++) {
            DockIcon *icon = [icons objectAtIndex: i];
          
            if ([icon isSpecialIcon] == NO) {
              FSNode *node = [icon node];
              
              if ([oldpath isEqual: [node path]]) {
                [NSTimer scheduledTimerWithTimeInterval: 1.0
                                                 target: self
                                               selector: @selector(checkRemovedApp:)
                                               userInfo: icon
                                                repeats: NO];
              }
            }
          }
        }
    }
  else if ([event isEqual: @"GWFileDeletedInWatchedDirectory"])
    {
      NSArray *files = [info objectForKey: @"files"];
      NSUInteger i;
    
      for (i = 0; i < [files count]; i++)
	{
	  NSString *fname = [files objectAtIndex: i];
	  NSString *fullpath = [path stringByAppendingPathComponent: fname];
	  int j;
      
	  for (j = 0; j < [icons count]; j++)
	    {
	      DockIcon *icon = [icons objectAtIndex:j];

	      if ([icon isSpecialIcon] == NO) {
		FSNode *node = [icon node];

		if ([fullpath isEqual: [node path]])
		  {
		    [NSTimer scheduledTimerWithTimeInterval: 1.0
						     target: self
						   selector: @selector(checkRemovedApp:)
						   userInfo: icon
						    repeats: NO];
		  }
	      }
	    }
	}
    
      if ([path isEqual: [manager trashPath]])
	{
	  DockIcon *icon = [self trashIcon];
	  FSNode *node = [icon node];
	  NSArray *subNodes = [node subNodes];
	  int count = [subNodes count];
	  int i;

	  for (i = 0; i < [subNodes count]; i++) {
	    if ([[subNodes objectAtIndex: i] isReserved]) {
	      count --;
	    }
	  }
      
	  if (count == 0) {
	    [icon setTrashFull: NO];
	  }
	}
    
    }
  else if ([event isEqual: @"GWFileCreatedInWatchedDirectory"])
    {
      if ([path isEqual: [manager trashPath]])
	{
	  DockIcon *icon = [self trashIcon];
	  FSNode *node = [icon node];
	  NSArray *subNodes = [node subNodes];
	  NSUInteger i;

	  for (i = 0; i < [subNodes count]; i++)
	    {
	      if ([[subNodes objectAtIndex: i] isReserved] == NO)
		{
		  [icon setTrashFull: YES];
		  break;
		}
	    }
	}
    }
  
  RELEASE (arp);
}

- (void)unselectOtherReps:(id)arep
{
  NSUInteger i;
  
  for (i = 0; i < [icons count]; i++) {
    DockIcon *icon = [icons objectAtIndex: i];    

    if (icon != arep) {
      [icon unselect];
    }
  }
}

- (FSNSelectionMask)selectionMask
{
  return NSSingleSelectionMask;
}

- (void)setBackgroundColor:(NSColor *)acolor
{
  NSColor *hlgtcolor = [acolor highlightWithLevel: 0.2];
  NSUInteger i;
  
  for (i = 0; i < [icons count]; i++)
    [[icons objectAtIndex: i] setHighlightColor: hlgtcolor];
  
  ASSIGN (backColor, hlgtcolor);
  if ([self superview]) {
    [self tile];
  }
}

- (NSColor *)backgroundColor
{
  return backColor;
}

- (NSColor *)textColor
{
  return [NSColor controlTextColor];
}

- (NSColor *)disabledTextColor
{
  return [NSColor disabledControlTextColor];
}

- (void)dragMountpointStarted:(NSNotification *)notification
{
  NSUInteger i;
  BOOL allAreMountpoints = NO;
  
  if ([notification userInfo]) {
    NSNumber *value = [[notification userInfo] objectForKey: @"allAreMountpoints"];
    if (value) {
      allAreMountpoints = [value boolValue];
    }
  }

  /* Update all trash icons with the drag state */
  for (i = 0; i < [icons count]; i++) {
    DockIcon *icon = [icons objectAtIndex: i];
    if ([icon isTrashIcon]) {
      [icon setIsDragMountpointOnly: allAreMountpoints];
    }
  }
}

- (void)dragMountpointEnded:(NSNotification *)notification
{
  NSUInteger i;
  
  /* Reset the mountpoint flag on all trash icons */
  for (i = 0; i < [icons count]; i++) {
    DockIcon *icon = [icons objectAtIndex: i];
    if ([icon isTrashIcon]) {
      [icon setIsDragMountpointOnly: NO];
    }
  }
}

#import "../../FSNode/FSNodeRep.h"

- (BOOL)allPathsAreMountpoints:(NSArray *)paths
{
  NSWorkspace *workspace = [NSWorkspace sharedWorkspace];
  NSArray *volumePaths = [workspace mountedLocalVolumePaths];
  NSSet *extraVolumes = [[FSNodeRep sharedInstance] volumes];
  NSUInteger i;

  if ([paths count] == 0) {
    return NO;
  }

  for (i = 0; i < [paths count]; i++) {
    NSString *path = [paths objectAtIndex: i];
    if ((![volumePaths containsObject: path]) && (![extraVolumes containsObject: path])) {
      return NO;
    }
  }

  return YES;
}

@end


@implementation Dock (DraggingDestination)

/* The paths of a drag that could be kept in the Dock: folders, and only
 * folders, from outside it. */
- (NSArray *)draggedFolderPaths:(id <NSDraggingInfo>)sender
{
  NSPasteboard *pb = [sender draggingPasteboard];
  NSArray *paths;
  NSUInteger i;

  if (dndSourceIcon != nil || [[pb types] containsObject: @"DockIconPboardType"])
    return nil;

  paths = [FSNSpringLoader draggedPathsOfDraggingInfo: sender];
  if ([paths count] == 0)
    return nil;

  for (i = 0; i < [paths count]; i++)
    {
      FSNode *nd = [FSNode nodeWithPath: [paths objectAtIndex: i]];

      if ([nd isDirectory] == NO || [nd isPackage])
        return nil;
    }

  return paths;
}

/* Where dragged folders would be kept with the pointer at p, or -1 when
 * letting go there does something else.  The middle of a folder takes the
 * items into it and the middle of the Trash throws them away; between
 * icons they are kept.  Among the applications they can only be kept at
 * the start of the folders. */
- (NSInteger)folderInsertionIndexAtPoint:(NSPoint)p
{
  NSUInteger docs = [self firstDocumentIndex];
  DockIcon *icon;
  NSRect r;
  CGFloat along;
  NSUInteger i;

  /* The gap the icons moved apart for stays: the pointer is in it. */
  if (folderTargetIndex != -1 && NSPointInRect(p, folderGapRect))
    return folderTargetIndex;
  if (NSPointInRect(p, dividerRect))
    return docs;

  icon = [self iconContainingPoint: p];
  if (icon == nil || [icon isWsIcon])
    return -1;

  i = [icons indexOfObjectIdenticalTo: icon];
  r = [icon frame];
  /* How far into the icon the pointer is, in the order the icons go. */
  along = (position == DockPositionBottom)
    ? (p.x - NSMinX(r)) / NSWidth(r)
    : (NSMaxY(r) - p.y) / NSHeight(r);

  if ([icon isFolderIcon])
    {
      if (along < 0.25)
        return i;
      if (along > 0.75)
        return i + 1;
      return -1;
    }
  if ([icon isTrashIcon])
    return (along < 0.25) ? (NSInteger)i : -1;

  return (along < 0.25 || along > 0.75) ? (NSInteger)docs : -1;
}

/* Opens or moves the gap for dragged folders.  Returns whether the drag is
 * over a place that keeps them. */
- (BOOL)trackFolderInsertion:(id <NSDraggingInfo>)sender
{
  NSInteger index = -1;

  if ([self draggedFolderPaths: sender] != nil)
    index = [self folderInsertionIndexAtPoint:
                    [self convertPoint: [sender draggingLocation] fromView: nil]];

  if (index != folderTargetIndex)
    {
      folderTargetIndex = index;
      [self tile];
    }

  return (index != -1);
}

/* The Dock keeps a reference to the folder; nothing is moved or copied. */
- (NSDragOperation)keepingOperation:(id <NSDraggingInfo>)sender
{
  NSDragOperation mask = [sender draggingSourceOperationMask];

  if (mask & NSDragOperationLink)
    return NSDragOperationLink;
  if (mask & NSDragOperationGeneric)
    return NSDragOperationGeneric;
  return mask & NSDragOperationCopy;
}

- (void)keepDraggedFolders:(id <NSDraggingInfo>)sender
{
  NSArray *paths = [self draggedFolderPaths: sender];
  NSInteger index = folderTargetIndex;
  NSUInteger i;

  folderTargetIndex = -1;

  for (i = 0; i < [paths count]; i++)
    {
      NSString *path = [paths objectAtIndex: i];
      DockIcon *kept = [self folderIconForPath: path];

      if (kept != nil)
        {
          /* Already in the Dock: it moves to where it was dropped. */
          NSUInteger at = [icons indexOfObjectIdenticalTo: kept];

          RETAIN (kept);
          [icons removeObjectAtIndex: at];
          if ((NSInteger)at < index)
            index--;
          [icons insertObject: kept atIndex: index];
          RELEASE (kept);
          index++;
        }
      else if ([self addFolderIconAtPath: path atIndex: index] != nil)
        {
          index++;
        }
    }

  [self saveDockConfiguration];
}

/* Applications and folders each keep to their own side of the divider. */
- (BOOL)icon:(DockIcon *)a sharesSectionWith:(DockIcon *)b
{
  return ([a isFolderIcon] && [b isFolderIcon])
    || ([a isApplicationIcon] && [b isApplicationIcon]);
}

/* A dragged application is added after the application under the pointer,
 * or after the last one when the pointer is past them. */
- (NSInteger)applicationTargetIndexForIndex:(NSUInteger)index
{
  NSUInteger docs = [self firstDocumentIndex];

  return (index < docs) ? (NSInteger)index : (NSInteger)docs - 1;
}

/* A file drag resting on an icon springs it open: a running application
 * comes to the front, the Workspace icon opens the System Disk, a folder
 * opens. */
- (void)trackSpringForDrag:(id <NSDraggingInfo>)sender
{
  NSPoint p = [self convertPoint: [sender draggingLocation] fromView: nil];
  DockIcon *icon = nil;
  FSNode *springNode;

  /* Between icons, where a folder is about to be kept, nothing opens. */
  if (folderTargetIndex == -1)
    icon = [self iconContainingPoint: p];

  if (icon != springIcon)
    {
      [[FSNSpringLoader sharedLoader] pointerLeftView: springIcon];
      springIcon = icon;
    }

  if (icon == nil || [icon isTrashIcon])
    return;

  springNode = [icon isWsIcon] ? [FSNode nodeWithPath: path_separator()]
                               : [icon node];

  [[FSNSpringLoader sharedLoader]
    pointerRestsOnNode: springNode
                inView: icon
               flasher: icon
          draggedPaths: [FSNSpringLoader draggedPathsOfDraggingInfo: sender]];
}

- (void)leaveSpringIcon
{
  [[FSNSpringLoader sharedLoader] pointerLeftView: springIcon];
  springIcon = nil;
}

- (NSDragOperation)draggingEntered:(id <NSDraggingInfo>)sender
{
  /* A drag needs the Dock as it lies: the gap for the dragged item is
   * opened in the plain layout, not around the pointer. */
  [self endMagnification];

  NSPoint location = [sender draggingLocation];
  DockIcon *icon;
  NSUInteger i;
        
  isDragTarget = YES;  
  targetIndex = -1;
  targetRect = NSZeroRect;
  dragdelay = 0;
  
  /* Reset mountpoint flag on all trash icons at the start */
  for (i = 0; i < [icons count]; i++) {
    DockIcon *trashIcon = [icons objectAtIndex: i];
    if ([trashIcon isTrashIcon]) {
      [trashIcon setIsDragMountpointOnly: NO];
    }
  }

  if ([self trackFolderInsertion: sender]) {
    return [self keepingOperation: sender];
  }

  location = [self convertPoint: location fromView: nil];
  icon = [self iconContainingPoint: location];
                 
  if (icon) {
    NSUInteger index = [icons indexOfObjectIdenticalTo: icon];
        
    if (dndSourceIcon && ([sender draggingSource] == dndSourceIcon)) {
      if ((icon != dndSourceIcon)
          && [self icon: icon sharesSectionWith: dndSourceIcon]) {
        RETAIN (dndSourceIcon);
        [icons removeObject: dndSourceIcon];
        [icons insertObject: dndSourceIcon atIndex: index];
        RELEASE (dndSourceIcon);
        [self tile];  
        return NSDragOperationMove;    
      }

    } else {
      NSPasteboard *pb = [sender draggingPasteboard];
      
      if ([[pb types] containsObject: @"DockIconPboardType"]) {
        if ([icon isTrashIcon] == NO) {
          targetIndex = [self applicationTargetIndexForIndex: index];
          return NSDragOperationMove;
        }
        
      } else if ([[pb types] containsObject: NSFilenamesPboardType]) {
        NSArray *sourcePaths = [pb propertyListForType: NSFilenamesPboardType];
        
        if (!sourcePaths || [sourcePaths count] == 0) {
          return NSDragOperationNone;
        }
        
        NSString *path = [sourcePaths objectAtIndex: 0];
        FSNode *node = [FSNode nodeWithPath: path];
      
        if ([node isApplication] && ([icon isSpecialIcon] == NO)) {
          NSUInteger i;
          
          for (i = 0; i < [icons count]; i++) {
            if ([[[icons objectAtIndex: i] node] isEqualToNode: node]) {
              isDragTarget = NO;
              return NSDragOperationNone;
            }
          }
          
          targetIndex = [self applicationTargetIndexForIndex: index];
          /* Decide operation based on source writability */
          {
            NSString *fromPath = [path stringByDeletingLastPathComponent];
            NSDragOperation sourceDragMask = [sender draggingSourceOperationMask];
            forceCopy = NO;

            if (sourceDragMask & NSDragOperationMove)
              {
                if ([[NSFileManager defaultManager] isWritableFileAtPath: fromPath])
                  {
                    return NSDragOperationMove;
                  }
                forceCopy = YES;
                return NSDragOperationCopy;
              }
            if (sourceDragMask & NSDragOperationCopy)
              {
                return NSDragOperationCopy;
              }
            if (sourceDragMask & NSDragOperationLink)
              {
                return NSDragOperationLink;
              }
          }
          
        } else {
          if ([icon acceptsDraggedPaths: sourcePaths]) {
            /* If dragging over Trash icon with only mountpoints, mark it */
            if ([icon isTrashIcon]) {
              if ([self allPathsAreMountpoints: sourcePaths]) {
                [icon setIsDragMountpointOnly: YES];
              } else {
                [icon setIsDragMountpointOnly: NO];
              }
            }
            {
              NSString *fromPath = [[sourcePaths objectAtIndex: 0] stringByDeletingLastPathComponent];
              NSDragOperation sourceDragMask = [sender draggingSourceOperationMask];
              forceCopy = NO;

              if (sourceDragMask & NSDragOperationMove)
                {
                  if ([[NSFileManager defaultManager] isWritableFileAtPath: fromPath])
                    {
                      return NSDragOperationMove;
                    }
                  forceCopy = YES;
                  return NSDragOperationCopy;
                }
              if (sourceDragMask & NSDragOperationCopy)
                {
                  return NSDragOperationCopy;
                }
              if (sourceDragMask & NSDragOperationLink)
                {
                  return NSDragOperationLink;
                }
            }
          } else {
            /* Reset flag if icon rejects the drag */
            if ([icon isTrashIcon]) {
              [icon setIsDragMountpointOnly: NO];
            }
            [icon showDropHighlight: NO];
          }
        }
      }
    }
  }

  isDragTarget = NO;    
  forceCopy = NO;
  return NSDragOperationNone;
}

- (NSDragOperation)draggingUpdated:(id <NSDraggingInfo>)sender
{
  NSPoint location;
  DockIcon *icon;
  BOOL keeping = [self trackFolderInsertion: sender];

  [self trackSpringForDrag: sender];

  if (keeping) {
    isDragTarget = YES;
    [self unselectOtherReps: nil];
    return [self keepingOperation: sender];
  }
 
  if (dragdelay < 2) {
    dragdelay++;
    return NSDragOperationNone;
  }
  
  isDragTarget = YES;  
  location = [sender draggingLocation];  
  icon = [self iconContainingPoint: location];
 
  if (targetIndex != -1) {
    if (NSEqualRects(targetRect, NSZeroRect)) {
      [self tile];
      return NSDragOperationMove;
    }
  }

  if (targetIndex != -1) {
    if (NSPointInRect(location, NSInsetRect(targetRect, 0.0, 2.0))) {
      return NSDragOperationMove;
    }
  }
  
  location = [self convertPoint: location fromView: nil];
  
  if (NSPointInRect(location, NSInsetRect(targetRect, 0.0, 2.0))) {
    return NSDragOperationMove;
  }
  
  if (icon == nil) {
    icon = [self iconContainingPoint: location];
  }
    
  if (icon) {
    NSUInteger index = [icons indexOfObjectIdenticalTo: icon];

    if (dndSourceIcon && ([sender draggingSource] == dndSourceIcon)) {
      if ((icon != dndSourceIcon)
          && [self icon: icon sharesSectionWith: dndSourceIcon]) {
        RETAIN (dndSourceIcon);
        [icons removeObject: dndSourceIcon];
        [icons insertObject: dndSourceIcon atIndex: index];
        RELEASE (dndSourceIcon);
        [self tile];
      } 
      
      return NSDragOperationMove;
    
    } else {
      NSPasteboard *pb = [sender draggingPasteboard];

      if (pb && [[pb types] containsObject: @"DockIconPboardType"]) {
        NSInteger appTarget = [self applicationTargetIndexForIndex: index];

        if ((targetIndex != appTarget) && ([icon isTrashIcon] == NO)) {
          targetIndex = appTarget;
          [self tile];
          return NSDragOperationMove;
        }

      } else if (pb && [[pb types] containsObject: NSFilenamesPboardType]) {
        NSArray *sourcePaths = [pb propertyListForType: NSFilenamesPboardType]; 
        NSString *path = [sourcePaths objectAtIndex: 0];
        FSNode *node = [FSNode nodeWithPath: path];

        if (([node isApplication] == NO) 
                          || ([node isApplication] && [icon isTrashIcon])) {
          if ([icon acceptsDraggedPaths: sourcePaths]) {
            /* If dragging over Trash icon with only mountpoints, mark it */
            if ([icon isTrashIcon] && [self allPathsAreMountpoints: sourcePaths]) {
              [icon setIsDragMountpointOnly: YES];
            } else if ([icon isTrashIcon]) {
              [icon setIsDragMountpointOnly: NO];
            }

            if (forceCopy) {
              return NSDragOperationCopy;
            }

            /* Fallback: compute based on source writability if forceCopy not set */
            {
              NSString *fromPath = [[sourcePaths objectAtIndex: 0] stringByDeletingLastPathComponent];
              NSDragOperation sourceDragMask = [sender draggingSourceOperationMask];

              if (sourceDragMask & NSDragOperationMove) {
                if ([[NSFileManager defaultManager] isWritableFileAtPath: fromPath]) {
                  return NSDragOperationMove;
                }
                forceCopy = YES;
                return NSDragOperationCopy;
              }
              if (sourceDragMask & NSDragOperationCopy) {
                return NSDragOperationCopy;
              }
              if (sourceDragMask & NSDragOperationLink) {
                return NSDragOperationLink;
              }

              return NSDragOperationNone;
            }
          } else {
            [icon showDropHighlight: NO];
          }

        } else if (([icon isTrashIcon] == NO)
                   && (targetIndex != [self applicationTargetIndexForIndex: index])) {
          targetIndex = [self applicationTargetIndexForIndex: index];
          [self tile]; 
          return NSDragOperationMove;
        } 
      }
    }   
  }

  return NSDragOperationNone;
}

- (void)draggingExited:(id <NSDraggingInfo>)sender
{
  NSUInteger i;
  
  [self leaveSpringIcon];
  if (folderTargetIndex != -1) {
    folderTargetIndex = -1;
    [self tile];
  }

  isDragTarget = NO;  
  dragdelay = 0;
  forceCopy = NO;
  
  /* Reset the mountpoint flag on all trash icons */
  for (i = 0; i < [icons count]; i++) {
    DockIcon *icon = [icons objectAtIndex: i];
    if ([icon isTrashIcon]) {
      [icon setIsDragMountpointOnly: NO];
    }
  }
  
  [self unselectOtherReps: nil];
      
  if (dndSourceIcon && [dndSourceIcon superview]) {
    [self removeIcon: dndSourceIcon];
    [self setDndSourceIcon: nil];
  }
  if (targetIndex != -1) {
    targetIndex = -1;
    targetRect = NSZeroRect;
    [self tile];
  }
}

- (BOOL)prepareForDragOperation:(id <NSDraggingInfo>)sender
{
  return isDragTarget;
}

- (BOOL)performDragOperation:(id <NSDraggingInfo>)sender
{
  return isDragTarget;
}

- (void)concludeDragOperation:(id <NSDraggingInfo>)sender
{
  NSUInteger i;

  [self leaveSpringIcon];

  if (folderTargetIndex != -1) {
    [self keepDraggedFolders: sender];
    [self unselectOtherReps: nil];
    isDragTarget = NO;
    targetIndex = -1;
    targetRect = NSZeroRect;
    [self tile];
    return;
  }
  
  /* Reset the mountpoint flag on all trash icons */
  for (i = 0; i < [icons count]; i++) {
    DockIcon *icon = [icons objectAtIndex: i];
    if ([icon isTrashIcon]) {
      [icon setIsDragMountpointOnly: NO];
    }
  }
  
  [self unselectOtherReps: nil];

  if (dndSourceIcon && ([sender draggingSource] == dndSourceIcon)) {
    [dndSourceIcon setIsDndSourceIcon: NO];
    [self setDndSourceIcon: nil];

  } else {
    NSPasteboard *pb = [sender draggingPasteboard];

    if ([[pb types] containsObject: @"DockIconPboardType"]) { 
      [self addDraggedIcon: [pb dataForType: @"DockIconPboardType"] 
                   atIndex: targetIndex];
      /* Persist after adding a dragged icon from another dock */
      [self saveDockConfiguration];

    } else if ([[pb types] containsObject: NSFilenamesPboardType]) {
      NSArray *sourcePaths = [pb propertyListForType: NSFilenamesPboardType];
      NSPoint location = [sender draggingLocation];
      DockIcon *icon;
      BOOL concluded = NO;

      location = [self convertPoint: location fromView: nil];
      icon = [self iconContainingPoint: location];

      // Handle multiple applications being dropped
      if ([sourcePaths count] >= 1) {
        NSUInteger pathIndex;
        NSUInteger addedCount = 0;
        
        for (pathIndex = 0; pathIndex < [sourcePaths count]; pathIndex++) {
          NSString *path = [sourcePaths objectAtIndex: pathIndex];
          FSNode *node = [FSNode nodeWithPath: path];
          NSString *appName = [[node name] stringByDeletingPathExtension];
          
          if ([node isApplication]) {
            if ((icon == nil) || (icon && ([icon isTrashIcon] == NO))) {
              BOOL duplicate = NO;
              NSUInteger i;

              for (i = 0; i < [icons count]; i++) {
                DockIcon *checkIcon = [icons objectAtIndex: i];

                /* The same logical application can be reached via different
                 * paths (domain copies, symlinks); match by name so dragging
                 * it to the Dock never produces a duplicate icon. */
                if ([[checkIcon appName] isEqual: appName]) {
                  RETAIN (checkIcon);
                  [icons removeObject: checkIcon];
                  [icons insertObject: checkIcon atIndex: targetIndex];
                  RELEASE (checkIcon);
                  duplicate = YES;      
                  break;
                }
              }

              if (duplicate == NO) {
                DockIcon *newIcon = [self addIconForApplicationAtPath: path
                                                          withName: appName 
                                                           atIndex: targetIndex];
                [newIcon setDocked: YES];
                addedCount++;
              }

              concluded = YES;
            }
          }
        }
        
        /* Persist after adding new application icons */
        if (addedCount > 0) {
          [self saveDockConfiguration];
        }
      }
      
      if (concluded == NO) {
        if (icon) {
          [icon setDraggedPaths: sourcePaths];
        }
      }    
    }
  }

  isDragTarget = NO;
  targetIndex = -1;
  targetRect = NSZeroRect;
  
  [self tile];
}

- (BOOL)isDragTarget
{
  return isDragTarget;
}

- (void)_launchRefreshTimerFired:(NSTimer *)timer
{
  for (DockIcon *icon in icons)
    {
      if ([icon isFolderIcon])
        continue;
      /* The X window scans (windowsMatchingName:/hasWindowsForPID:) open X
       * connections and issue synchronous round-trips.  Done on the main
       * thread they can wedge the app: while the main thread blocks in a
       * synchronous X request it stops draining the GNUstep event queue, the X
       * server gets stuck writing the accumulated events, and the reply never
       * comes (X11 self-deadlock).  Run each icon's refresh on a worker
       * thread; the state changes are applied back on the main thread. */
      [icon refreshLaunchedStateAsync];
    }
}

@end







