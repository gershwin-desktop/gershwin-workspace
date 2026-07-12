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

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <objc/runtime.h>
#import "Dock.h"
#import "DockIcon.h"
#import "DockMiniWindow.h"
#import "GWDesktopView.h"
#import "Workspace.h"
#import "GWFunctions.h"
#import "X11AppSupport.h"
#import "GWDockWindow.h"

#define MAX_ICN_SIZE 48
#define MIN_ICN_SIZE 16
#define ICN_INCR 4

#define MAGNIFY_MAX_RATIO 2.0
#define MAGNIFY_EFFECT_WIDTH 200.0

static CGFloat
magnifyScaleForDistance(CGFloat d)
{
  if (d > MAGNIFY_EFFECT_WIDTH) return 1.0;
  /* Quartic falloff: (1 - (d/W)²)²
   * Peaks sharply at d=0 (cursor at tile center), reaches 0 at d=W.
   * This ensures the tile under the cursor is always the largest. */
  CGFloat t = d / MAGNIFY_EFFECT_WIDTH;
  CGFloat falloff = 1.0 - t * t;
  return 1.0 + (MAGNIFY_MAX_RATIO - 1.0) * falloff * falloff;
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

@implementation Dock

- (void)dealloc
{
  [[NSNotificationCenter defaultCenter] removeObserver: self];
  [mouseWatchTimer invalidate];
  RELEASE (mouseWatchTimer);
  RELEASE (miniWindowsByID);
  RELEASE (icons);
  RELEASE (backColor);
  if (lastIconSizes) free(lastIconSizes);
  
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
      magnifyActive = YES;
      magnifyCursorX = -1e6;
      magnifyCursorY = -1e6;
      magnifyTrackingTag = 0;
      magnifiedOnce = NO;
      needsTile = YES;
      lastIconSizes = NULL;
      lastIconSizesCount = 0;
      mouseWatchTimer = [NSTimer scheduledTimerWithTimeInterval: 0.033
                                                         target: self
                                                       selector: @selector(mouseWatchFired:)
                                                       userInfo: nil
                                                        repeats: YES];
                                
      dndSourceIcon = nil;
      isDragTarget = NO;
      dragdelay = 0;
      targetIndex = -1;
      targetRect = NSZeroRect;
    
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
                GWDebugLog(@"Dock: skipping invalid entry (no name)");
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
		        GWDebugLog(@"Dock: failed to create icon for app \"%@\" at path %@", name, path);
		      }
		    }
		  NS_HANDLER
		    {
		      GWDebugLog(@"Dock: exception loading app \"%@\": %@", name, [localException reason]);
		    }
		  NS_ENDHANDLER
		}
	      else
		{
		  /* Application no longer exists - remove it from preferences */
		  if (name) {
		    GWDebugLog(@"Dock: app \"%@\" no longer exists at saved path; removing from dock.", name);
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

      [self createTrashIcon];

      /* Initialize minimized windows tracking */
      miniWindowsByID = [[NSMutableDictionary alloc] init];
      separatorLeft = 0;
      separatorRight = 0;


      /* Register for drag notifications */
      [[NSNotificationCenter defaultCenter] addObserver: self
                                               selector: @selector(dragMountpointStarted:)
                                                   name: @"GWDragMountpointStarted"
                                                 object: nil];
      [[NSNotificationCenter defaultCenter] addObserver: self
                                               selector: @selector(dragMountpointEnded:)
                                                   name: @"GWDragMountpointEnded"
                                                 object: nil];
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
  needsTile = YES;
  [self addSubview: icon];
  RELEASE (icon);
  
  [manager addWatcherForPath: path];
}

- (DockIcon *)addIconForApplicationAtPath:(NSString *)path
                                 withName:(NSString *)name
                                  atIndex:(int)index
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

      if (index == -1) {
        icnindex = ([icons count]) ? ([icons count] - 1) : 0;
      } else {
        icnindex = (index < [icons count]) ? (index + 1) : [icons count];
      }

      [icon setHighlightColor: backColor];
      [icons insertObject: icon atIndex: icnindex];
      needsTile = YES;
      [icon setSingleClickLaunch: singleClickLaunch];
      [self addSubview: icon];
      RELEASE (icon);
      
      [manager addWatcherForPath: [node path]];
      
      return icon;
    }
  }
  
  return nil;
}

- (void)addDraggedIcon:(NSData *)icondata
               atIndex:(int)index
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
  [manager removeWatcherForPath: [[icon node] path]];
  
  if ([icon superview]) {
    [icon removeFromSuperview];
  }
  if ([icon isLaunched]) {
    [icon setLaunched: NO];
  }
  [icons removeObject: icon];
  needsTile = YES;
  [self tile];
  
  /* Persist the removal immediately */
  [self saveDockConfiguration];
}

- (DockIcon *)iconForApplicationName:(NSString *)name
{
  NSUInteger i;
  
  for (i = 0; i < [icons count]; i++) {
    DockIcon *icon = [icons objectAtIndex: i];
    
    if ([[icon appName] isEqual: name]) {
      return icon;
    }
  }
  
  return nil;
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
      DockIcon *icon = [self iconForApplicationName: appName];
      if (icon) {
        [self removeIcon: icon];
      }
      return;
    }

    DockIcon *icon = [self iconForApplicationName: appName];
  
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
    NSDebugLLog(@"gwspace", @"DEBUG: Dock appDidLaunch for appName: %@", appName);
  } else
    {
      NSDebugLLog(@"gwspace", @"DEBUG: Dock appDidLaunch for nil appName");
      return;
    }
  if ([appName isEqual: [gw gworkspaceProcessName]] == NO) {
    /* Honor GSSuppressAppIcon — skip apps that declare they should not
     * appear in the Dock (e.g. WindowManager). */
    NSBundle *bundle = [NSBundle bundleWithPath: appPath];
    if ([[bundle objectForInfoDictionaryKey: @"GSSuppressAppIcon"] boolValue]) {
      DockIcon *icon = [self iconForApplicationName: appName];
      if (icon) {
        [self removeIcon: icon];
      }
      return;
    }

    DockIcon *icon = [self iconForApplicationName: appName];

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

- (void)appTerminated:(NSString *)appName
{
  if (appName == nil) return;
  if ([appName isEqual: [gw gworkspaceProcessName]] == NO) {
    DockIcon *icon = [self iconForApplicationName: appName];

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

- (void)appDidHide:(NSString *)appName
{
  if (appName == nil) return;
  if ([appName isEqual: [gw gworkspaceProcessName]] == NO) {
    DockIcon *icon = [self iconForApplicationName: appName];

    if (icon) {
      [icon setAppHidden: YES];
    }
  }
}

- (void)appDidUnhide:(NSString *)appName
{
  if (appName == nil) return;
  if ([appName isEqual: [gw gworkspaceProcessName]] == NO) {
    DockIcon *icon = [self iconForApplicationName: appName];

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

- (void)tile
{
  NSView *view = [self superview];
  NSRect scrrect = [[[NSScreen screens] objectAtIndex:0] frame];
  CGFloat maxheight = scrrect.size.height;
  NSRect icnrect = NSZeroRect;  
  NSRect rect = NSZeroRect;
  NSUInteger i;

  iconSize = MAX_ICN_SIZE;

  // Skip the expensive window-resize computation during mouse tracking
  // — the window is already oversized and doesn't need to change until
  // the icon list itself changes.
  if (needsTile == NO && magnifyActive)
    {
      goto do_layout;
    }
  needsTile = NO;

  icnrect.origin.x = 0;
  icnrect.origin.y = 0;
  icnrect.size.width = ceil(iconSize / 3 * 4);
  icnrect.size.height = icnrect.size.width;
    
  /* For window sizing, use the maximum possible magnified size so the
   * window never clips enlarged icons.  The icons themselves are laid
   * out at their actual (potentially smaller) size by
   * layoutTilesWithMagnification. */
  CGFloat magFactor = magnifyActive ? MAGNIFY_MAX_RATIO : 1.0;
  NSRect magIcnRect = icnrect;
  magIcnRect.size.width *= magFactor;
  magIcnRect.size.height *= magFactor;

  NSUInteger miniCount = [miniWindowsByID count];
  NSUInteger totalItems = [icons count] + miniCount;

  rect.size.height = totalItems * magIcnRect.size.height;
  if (targetIndex != -1) {
    rect.size.height += magIcnRect.size.height;
  }
  
  maxheight -= (magIcnRect.size.height * 2);  
  
  while (rect.size.height > maxheight) {
    iconSize -= ICN_INCR;
    icnrect.size.height = ceil(iconSize / 3 * 4);
    icnrect.size.width = icnrect.size.height;
    magIcnRect.size.width = icnrect.size.width * magFactor;
    magIcnRect.size.height = icnrect.size.height * magFactor;
    rect.size.height = totalItems * magIcnRect.size.height;

    if (targetIndex != -1) {
      rect.size.height += magIcnRect.size.height;
    }
      
    if (iconSize <= MIN_ICN_SIZE) {
      break;
    }
  }
 
  if (position == DockPositionBottom)
  {
    rect.size.width = totalItems * magIcnRect.size.width;
    rect.size.height = magIcnRect.size.height;
  }
  else
  {
    rect.size.width = magIcnRect.size.width;
    rect.size.height = totalItems * magIcnRect.size.height;
  }

  // Offset by the primary screen's origin so the dock lands on the correct
  // monitor when the desktop window spans the full virtual desktop.
  CGFloat scrOriginX = scrrect.origin.x;
  CGFloat scrOriginY = scrrect.origin.y;

  if (position == DockPositionBottom)
    {
      // Full-width transparent window; double-height so magnified icons
      // have room to grow upward.
      rect.origin.x = scrOriginX;
      rect.origin.y = scrOriginY;
      rect.size.width = scrrect.size.width;
      rect.size.height = magIcnRect.size.height * 3.0;
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

  NSDebugLLog(@"gwspace", @"DEBUG: Dock tile - setting frame: %@, icons count: %lu", NSStringFromRect(rect), (unsigned long)[icons count]);
  
  /*
   * When the dock lives in its own GWDockWindow, resize the window to the
   * computed screen-coordinate rect instead of setting this view's frame
   * (the window's content view is expected to stay at {0,0} within the
   * window content area).
   */
  BOOL inOwnDockWindow = [[self window] isKindOfClass: [GWDockWindow class]];

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

do_layout:
  // When magnification is disabled entirely, reset all icons to base size.
  if (magnifyActive == NO && magnifiedOnce)
    {
      for (i = 0; i < [icons count]; i++)
        {
          DockIcon *icon = [icons objectAtIndex: i];
          [icon setIconSize: iconSize];
        }
      for (i = 0; i < lastIconSizesCount; i++)
        lastIconSizes[i] = -1;
      magnifiedOnce = NO;
    }

  // Rebuild last-icon-sizes tracking array.
  // Must cover all items in the scales[] array: icons + mini windows.
  {
    NSUInteger total = [icons count] + [miniWindowsByID count];
    if (lastIconSizesCount != total)
      {
        if (lastIconSizes) free(lastIconSizes);
        lastIconSizesCount = total;
        lastIconSizes = malloc(lastIconSizesCount * sizeof(int));
        for (i = 0; i < lastIconSizesCount; i++)
          lastIconSizes[i] = -1;
      }
  }

  [self layoutTilesWithMagnification];

  [self setNeedsDisplay: YES];
  if (view && (inOwnDockWindow == NO)) {
    [view setNeedsDisplayInRect: [self frame]];
  }

  [self updateIconGeometries];
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

- (void)saveDockConfiguration
{
  NSDebugLLog(@"gwspace", @"DEBUG: Dock saveDockConfiguration");
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];	
  NSMutableDictionary *dict = [NSMutableDictionary dictionary];
  NSUInteger i;  

  for (i = 0; i < [icons count]; i++)
    {
      DockIcon *icon = [icons objectAtIndex: i];    

      if (([icon isSpecialIcon] == NO) && [icon isDocked])
	{
	  /* Save both name and path so non-GNUstep apps can be restored */
	  NSMutableDictionary *appEntry = [NSMutableDictionary dictionary];
	  [appEntry setObject: [icon appName] forKey: @"name"];
	  [appEntry setObject: [[icon node] path] forKey: @"path"];
	  [dict setObject: appEntry forKey: [[NSNumber numberWithInt: i] stringValue]];
	}
    }

  [defaults setObject: dict forKey: @"applications"];
  [defaults synchronize];
}

- (void)updateDefaults
{
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];	
  NSMutableDictionary *dict = [NSMutableDictionary dictionary];
  NSUInteger i;  

  [defaults setObject: [NSNumber numberWithInt: style]
               forKey: @"dockstyle"];
  [defaults setBool: singleClickLaunch forKey: @"singleclicklaunch"];

  for (i = 0; i < [icons count]; i++)
    {
      DockIcon *icon = [icons objectAtIndex: i];    

      if (([icon isSpecialIcon] == NO) && [icon isDocked])
	{
	  /* Save both name and path so non-GNUstep apps can be restored */
	  NSMutableDictionary *appEntry = [NSMutableDictionary dictionary];
	  [appEntry setObject: [icon appName] forKey: @"name"];
	  [appEntry setObject: [[icon node] path] forKey: @"path"];
	  [dict setObject: appEntry forKey: [[NSNumber numberWithInt: i] stringValue]];
	  [manager removeWatcherForPath: [[icon node] path]];
	}

      [icon setSingleClickLaunch: singleClickLaunch];
    }

  [defaults setObject: dict forKey: @"applications"];
  
  [manager removeWatcherForPath: [manager trashPath]];
}

- (void)checkRemovedApp:(id)sender
{
  DockIcon *icon = (DockIcon *)[sender userInfo];
  
  if ([[icon node] isValid] == NO) {
    [self removeIcon: icon];
  }
}

- (BOOL)isOpaque
{
  /* Modern style draws a semi-transparent gray, so the view is not opaque. */
  return (style != DockStyleModern);
}

- (void)drawRect:(NSRect)rect
{
  // Clear the entire window (transparent background)
  [[NSColor clearColor] set];
  NSRectFill([self bounds]);

  // Draw semi-transparent grey background behind the icons
  if (iconBgRect.size.width > 0 && iconBgRect.size.height > 0)
    {
      // Rounded corners only at the TOP; bottom corners are square.
      NSBezierPath *bp = [NSBezierPath bezierPath];
      CGFloat r = 8.0, x = iconBgRect.origin.x, y = iconBgRect.origin.y;
      CGFloat w = iconBgRect.size.width, h = iconBgRect.size.height;
      [bp moveToPoint: NSMakePoint(x, y)];  // bottom-left
      [bp lineToPoint: NSMakePoint(x + w, y)];  // bottom-right
      [bp lineToPoint: NSMakePoint(x + w, y + h - r)];  // right edge up
      [bp appendBezierPathWithArcFromPoint: NSMakePoint(x + w, y + h)
                                   toPoint: NSMakePoint(x + w - r, y + h)
                                    radius: r];  // top-right arc
      [bp lineToPoint: NSMakePoint(x + r, y + h)];  // top edge left
      [bp appendBezierPathWithArcFromPoint: NSMakePoint(x, y + h)
                                   toPoint: NSMakePoint(x, y + h - r)
                                    radius: r];  // top-left arc
      [bp closePath];

      [[NSColor colorWithCalibratedWhite: 0.35 alpha: 0.65] set];
      [bp fill];
    }

  NSRect bounds = [self bounds];
  NSUInteger miniCount = [miniWindowsByID ? miniWindowsByID : (id)[NSMutableDictionary dictionary] count];

  if (position == DockPositionBottom)
  {
    // Left separator: between regular apps and miniwindows (or Trash if no miniwindows)
    if (separatorLeft > 0 && separatorLeft < bounds.size.width)
    {
      CGFloat sepY = iconBgRect.origin.y + 4;
      CGFloat sepH = iconBgRect.size.height - 8;
      [[NSColor colorWithCalibratedWhite:1.0 alpha:0.25] set];
      NSRectFill(NSMakeRect(separatorLeft, sepY, 1, sepH));
      [[NSColor colorWithCalibratedWhite:0.0 alpha:0.25] set];
      NSRectFill(NSMakeRect(separatorLeft + 1, sepY, 1, sepH));
    }

    // Right separator: between miniwindows and Trash
    if (miniCount > 0 && separatorRight > 0 && separatorRight < bounds.size.width
        && separatorRight != separatorLeft)
    {
      CGFloat sepY = iconBgRect.origin.y + 4;
      CGFloat sepH = iconBgRect.size.height - 8;
      [[NSColor colorWithCalibratedWhite:1.0 alpha:0.25] set];
      NSRectFill(NSMakeRect(separatorRight, sepY, 1, sepH));
      [[NSColor colorWithCalibratedWhite:0.0 alpha:0.25] set];
      NSRectFill(NSMakeRect(separatorRight + 1, sepY, 1, sepH));
    }
  }
}

#pragma mark - Minimized Window Monitoring

- (NSView *)hitTest:(NSPoint)point
{
  NSPoint loc = [self convertPoint: point fromView: nil];
  if (NSPointInRect(loc, iconBgRect) == NO)
    return nil;  // click-through transparent area
  return [super hitTest: point];
}

- (void)viewDidMoveToWindow
{
  [super viewDidMoveToWindow];
  if ([self window]) {
    [[self window] setOpaque: NO];
    [[self window] setBackgroundColor: [NSColor clearColor]];
  }
}

- (void)animateIconFramesFrom:(NSArray *)savedFrames
{
  if ([savedFrames count] == 0)
    return;

  NSUInteger count = [icons count] + [miniWindowsByID count];
  NSMutableArray *animList = [NSMutableArray arrayWithCapacity: count];
  NSUInteger ci;

  for (ci = 0; ci < [icons count]; ci++)
    {
      DockIcon *ic = [icons objectAtIndex: ci];
      NSRect start = [[savedFrames objectAtIndex: ci] rectValue];
      NSRect end = [ic frame];
      if (!NSEqualRects(start, end))
        {
          [animList addObject:
            @{@"view": ic,
              @"sx": @(start.origin.x), @"sy": @(start.origin.y),
              @"sw": @(start.size.width), @"sh": @(start.size.height),
              @"ex": @(end.origin.x), @"ey": @(end.origin.y),
              @"ew": @(end.size.width), @"eh": @(end.size.height)}];
          // Set back to start so the timer animates forward
          [ic setFrame: start];
        }
    }

  {
    NSUInteger mi = ci;
    for (NSNumber *key in miniWindowsByID)
      {
        DockMiniWindow *mw = [miniWindowsByID objectForKey: key];
        NSRect start = [[savedFrames objectAtIndex: mi] rectValue];
        NSRect end = [mw frame];
        if (!NSEqualRects(start, end))
          {
            [animList addObject:
              @{@"view": mw,
                @"sx": @(start.origin.x), @"sy": @(start.origin.y),
                @"sw": @(start.size.width), @"sh": @(start.size.height),
                @"ex": @(end.origin.x), @"ey": @(end.origin.y),
                @"ew": @(end.size.width), @"eh": @(end.size.height)}];
            [mw setFrame: start];
          }
        mi++;
      }
  }

  if ([animList count] == 0)
    return;

  // Timer-driven interpolation: 8 steps over ~0.12s
  NSMutableDictionary *animState = [NSMutableDictionary dictionaryWithObjectsAndKeys:
    animList, @"list", @(1), @"step", @(8), @"total", nil];
  [NSTimer scheduledTimerWithTimeInterval: 0.015
                                   target: self
                                 selector: @selector(animStep:)
                                 userInfo: animState
                                  repeats: YES];
}

- (void)animStep:(NSTimer *)timer
{
  NSDictionary *state = [timer userInfo];
  NSArray *list = [state objectForKey: @"list"];
  int total = [[state objectForKey: @"total"] intValue];

  NSMutableDictionary *mstate = (NSMutableDictionary *)state;
  int step = [[mstate objectForKey: @"step"] intValue];
  float t = (float)step / (float)total;

  for (NSDictionary *d in list)
    {
      NSView *v = [d objectForKey: @"view"];
      float sx = [[d objectForKey: @"sx"] floatValue];
      float sy = [[d objectForKey: @"sy"] floatValue];
      float sw = [[d objectForKey: @"sw"] floatValue];
      float sh = [[d objectForKey: @"sh"] floatValue];
      float ex = [[d objectForKey: @"ex"] floatValue];
      float ey = [[d objectForKey: @"ey"] floatValue];
      float ew = [[d objectForKey: @"ew"] floatValue];
      float eh = [[d objectForKey: @"eh"] floatValue];
      NSRect cur = NSMakeRect(
        sx + (ex - sx) * t, sy + (ey - sy) * t,
        sw + (ew - sw) * t, sh + (eh - sh) * t);
      [v setFrame: cur];
    }

  if (step >= total)
    {
      for (NSDictionary *d in list)
        {
          NSView *v = [d objectForKey: @"view"];
          float ex = [[d objectForKey: @"ex"] floatValue];
          float ey = [[d objectForKey: @"ey"] floatValue];
          float ew = [[d objectForKey: @"ew"] floatValue];
          float eh = [[d objectForKey: @"eh"] floatValue];
          [v setFrame: NSMakeRect(ex, ey, ew, eh)];
        }
      [timer invalidate];
    }
  else
    {
      [mstate setObject: @(step + 1) forKey: @"step"];
    }
}

// Global mouse-watch timer: fires ~30×/s and reads [NSEvent mouseLocation]
// directly, so magnification responds smoothly even when the cursor is
// outside the dock window (e.g. approaching from above).
#define DOCK_MOUSE_RANGE 300.0  // pixels of influence beyond the dock

- (void)mouseWatchFired:(NSTimer *)timer
{
  NSPoint screenPos = [NSEvent mouseLocation];
  NSWindow *win = [self window];
  if (!win) return;
  NSPoint winPos = [win convertScreenToBase: screenPos];
  NSPoint loc = [self convertPoint: winPos fromView: nil];
  NSRect bounds = [self bounds];
  CGFloat dist = 0;

  if (position == DockPositionBottom)
    {
      // Distance from cursor to the dock band (y=0 .. iconBgHeight)
      if (loc.y > iconBgRect.size.height && loc.y > 0)
        dist = loc.y - iconBgRect.size.height;
      else if (loc.y < 0)
        dist = -loc.y;
      else
        dist = 0;  // inside the dock band
    }
  else
    {
      if (loc.x > bounds.size.width)
        dist = loc.x - bounds.size.width;
      else if (loc.x < 0)
        dist = -loc.x;
      else
        dist = 0;
    }

  if (dist > DOCK_MOUSE_RANGE)
    {
      // Cursor just left the influence range — animate icons back to base
      if (magnifyCursorX != -1e6)
        {
          NSMutableArray *savedFrames = [NSMutableArray array];
          NSUInteger ci;
          for (ci = 0; ci < [icons count]; ci++)
            [savedFrames addObject: [NSValue valueWithRect: [[icons objectAtIndex: ci] frame]]];
          for (NSNumber *key in miniWindowsByID)
            {
              DockMiniWindow *mw = [miniWindowsByID objectForKey: key];
              [savedFrames addObject: [NSValue valueWithRect: [mw frame]]];
            }
          magnifyCursorX = -1e6;
          magnifyCursorY = -1e6;
          [self tile];
          [self animateIconFramesFrom: savedFrames];
        }
      return;
    }

  NSPoint oldPos = NSMakePoint(magnifyCursorX, magnifyCursorY);
  magnifyCursorX = loc.x;
  magnifyCursorY = loc.y;

  // Throttle: skip tile if cursor moved less than 2 px
  if (fabs(loc.x - oldPos.x) < 2.0 && fabs(loc.y - oldPos.y) < 2.0
      && oldPos.x >= 0)
    return;

  [self tile];
}

- (void)mouseEntered:(NSEvent *)theEvent
{
  // Handled by mouseWatchFired:
}

- (void)mouseExited:(NSEvent *)theEvent
{
  // Handled by mouseWatchFired — no abrupt sentinel needed.
}

- (void)mouseMoved:(NSEvent *)theEvent
{
  // Handled by mouseWatchFired:
}

- (void)layoutTilesWithMagnification
{
  NSUInteger i;
  NSRect icnrect = NSZeroRect;
  icnrect.origin.x = 0;
  icnrect.origin.y = 0;
  icnrect.size.width = ceil(iconSize / 3 * 4);
  icnrect.size.height = icnrect.size.width;
  NSUInteger miniCount = [miniWindowsByID count];
  CGFloat baseWidth = icnrect.size.width;
  CGFloat baseHeight = icnrect.size.height;

  CGFloat cursorPos = (position == DockPositionBottom) ? magnifyCursorX : magnifyCursorY;

  if (!magnifyActive || cursorPos < 0)
  {
    // Original layout (no magnification)
    if (position == DockPositionBottom)
    {
      icnrect.origin.x = 0;
      icnrect.origin.y = 0;

      DockIcon *wsIcon = [icons objectAtIndex: 0];
      [wsIcon setFrame: icnrect];
      icnrect.origin.x += icnrect.size.width;
      if (targetIndex == 0)
        icnrect.origin.x += icnrect.size.width;

      for (i = 1; i < [icons count] - 1; i++)
      {
        DockIcon *icon = [icons objectAtIndex: i];
        [icon setFrame: icnrect];
        icnrect.origin.x += icnrect.size.width;
        if ((targetIndex != -1) && (targetIndex == (int)i))
          icnrect.origin.x += icnrect.size.width;
      }

      separatorLeft = icnrect.origin.x;

      for (NSNumber *key in miniWindowsByID)
      {
        DockMiniWindow *mw = [miniWindowsByID objectForKey: key];
        [mw setFrame: NSMakeRect(icnrect.origin.x, icnrect.origin.y,
                                 icnrect.size.width, icnrect.size.height)];
        icnrect.origin.x += icnrect.size.width;
      }

      separatorRight = icnrect.origin.x;

      DockIcon *trashIcon = [icons lastObject];
      [trashIcon setFrame: icnrect];
      icnrect.origin.x += icnrect.size.width;

      // Center non-magnified row within the oversize window
      {
        CGFloat totalW = icnrect.origin.x;
        CGFloat boundsW = [self bounds].size.width;
        if (totalW < boundsW) {
          CGFloat off = (boundsW - totalW) / 2.0;
          NSUInteger ci;
          for (ci = 0; ci < [icons count]; ci++) {
            NSRect f = [[icons objectAtIndex: ci] frame];
            f.origin.x += off;
            [[icons objectAtIndex: ci] setFrame: f];
          }
          for (NSNumber *key in miniWindowsByID) {
            DockMiniWindow *mw = [miniWindowsByID objectForKey: key];
            NSRect f = [mw frame];
            f.origin.x += off;
            [mw setFrame: f];
          }
          separatorLeft += off;
          separatorRight += off;
        }
      }
    }
    else
    {
      NSRect dockBounds = [self bounds];
      icnrect.origin.y = dockBounds.size.height;

      DockIcon *wsIcon = [icons objectAtIndex: 0];
      [wsIcon setFrame: icnrect];
      icnrect.origin.y -= icnrect.size.height;

      for (i = 1; i < [icons count] - 1; i++)
      {
        DockIcon *icon = [icons objectAtIndex: i];
        icnrect.origin.y -= icnrect.size.height;
        [icon setFrame: icnrect];
        if ((targetIndex != -1) && (targetIndex == (int)i))
          icnrect.origin.y -= icnrect.size.height;
      }

      separatorLeft = icnrect.origin.y;

      for (NSNumber *key in miniWindowsByID)
      {
        DockMiniWindow *mw = [miniWindowsByID objectForKey: key];
        icnrect.origin.y -= icnrect.size.height;
        [mw setFrame: NSMakeRect(icnrect.origin.x, icnrect.origin.y,
                                 icnrect.size.width, icnrect.size.height)];
      }

      separatorRight = icnrect.origin.y;

      DockIcon *trashIcon = [icons lastObject];
      icnrect.origin.y -= icnrect.size.height;
      [trashIcon setFrame: icnrect];

      // Center non-magnified column within the oversize window
      {
        CGFloat boundsH = [self bounds].size.height;
        CGFloat yMin = boundsH, yMax = 0;
        NSUInteger ci;
        for (ci = 0; ci < [icons count]; ci++) {
          NSRect f = [[icons objectAtIndex: ci] frame];
          if (f.origin.y < yMin) yMin = f.origin.y;
          if (f.origin.y + f.size.height > yMax) yMax = f.origin.y + f.size.height;
        }
        for (NSNumber *key in miniWindowsByID) {
          DockMiniWindow *mw = [miniWindowsByID objectForKey: key];
          NSRect f = [mw frame];
          if (f.origin.y < yMin) yMin = f.origin.y;
          if (f.origin.y + f.size.height > yMax) yMax = f.origin.y + f.size.height;
        }
        CGFloat contentH = yMax - yMin;
        if (contentH < boundsH) {
          CGFloat off = ((boundsH - contentH) / 2.0) - yMin;
          for (ci = 0; ci < [icons count]; ci++) {
            NSRect f = [[icons objectAtIndex: ci] frame];
            f.origin.y += off;
            [[icons objectAtIndex: ci] setFrame: f];
          }
          for (NSNumber *key in miniWindowsByID) {
            DockMiniWindow *mw = [miniWindowsByID objectForKey: key];
            NSRect f = [mw frame];
            f.origin.y += off;
            [mw setFrame: f];
          }
          separatorLeft += off;
          separatorRight += off;
        }
      }
    }

    // Non-magnified layout done.
    return;
  }

  // Fish-eye layout
  {
    CGFloat cursorMain = cursorPos;
    CGFloat halfBase = baseWidth / 2.0;

    // Centering offset: default-position row is left-aligned at x=0,
    // but after layout it gets shifted to center.  The scale formula
    // must use the ACTUAL centered tile center, not the pre-shift one.
    NSUInteger totalItems = [icons count] + miniCount;
    CGFloat totalDefaultWidth = totalItems * baseWidth;
    CGFloat boundsW = [self bounds].size.width;
    CGFloat centerOff = (position == DockPositionBottom)
                         ? (boundsW > totalDefaultWidth ? (boundsW - totalDefaultWidth) / 2.0 : 0)
                         : 0;

    if (position == DockPositionBottom)
    {
      // Item order: WS (0), apps (1..count-2), miniwindows, Trash (last)
      CGFloat scales[totalItems];
      CGFloat x = 0;
      int idx = 0;

      // Compute vertical distance from cursor to the icon row centre
      CGFloat rowCenterY = iconBgRect.origin.y + iconBgRect.size.height / 2.0;
      CGFloat yDist = fabs(magnifyCursorY - rowCenterY);

      // Pass 1: compute scales using 2D Euclidean distance so the
      // magnification ramps up smoothly as the cursor approaches from
      // any direction (including vertically from above).
      // WS
      {
        CGFloat dx = cursorMain - (centerOff + x + halfBase);
        CGFloat dist = sqrt(dx * dx + yDist * yDist);
        scales[idx] = magnifyScaleForDistance(dist);
      }
      idx++;
      x += baseWidth;

      // Regular apps
      for (i = 1; i < [icons count] - 1; i++)
      {
        CGFloat dx = cursorMain - (centerOff + x + halfBase);
        CGFloat dist = sqrt(dx * dx + yDist * yDist);
        scales[idx] = magnifyScaleForDistance(dist);
        idx++;
        x += baseWidth;
      }

      // Mini windows
      for (NSNumber *key in miniWindowsByID)
      {
        (void)key;
        CGFloat dx = cursorMain - (centerOff + x + halfBase);
        CGFloat dist = sqrt(dx * dx + yDist * yDist);
        scales[idx] = magnifyScaleForDistance(dist);
        idx++;
        x += baseWidth;
      }

      // Trash
      {
        CGFloat dx = cursorMain - (centerOff + x + halfBase);
        CGFloat dist = sqrt(dx * dx + yDist * yDist);
        scales[idx] = magnifyScaleForDistance(dist);
        idx++;
      }

      // Pass 2: re-cascade positions with scaled sizes
      x = 0;
      idx = 0;

      // Helper: call setIconSize: only when the size actually changes.
#define SET_ICON_SIZE(obj, idxv) \
  do { \
    int _new_ = (int)ceil(scales[idxv] * iconSize); \
    if (idxv < (int)lastIconSizesCount && lastIconSizes[idxv] != _new_) { \
      [obj setIconSize: _new_]; \
      lastIconSizes[idxv] = _new_; \
    } \
  } while(0)

      // WS
      {
        CGFloat w = baseWidth * scales[idx];
        CGFloat h = baseHeight * scales[idx];
        [[icons objectAtIndex: 0] setFrame: NSMakeRect(x, 0, w, h)];
        SET_ICON_SIZE([icons objectAtIndex: 0], idx);
        x += w;
        idx++;
      }

      // Regular apps
      for (i = 1; i < [icons count] - 1; i++)
      {
        CGFloat w = baseWidth * scales[idx];
        CGFloat h = baseHeight * scales[idx];
        [[icons objectAtIndex: i] setFrame: NSMakeRect(x, 0, w, h)];
        SET_ICON_SIZE([icons objectAtIndex: i], idx);
        x += w;
        idx++;
      }

      separatorLeft = x;

      // Mini windows
      for (NSNumber *key in miniWindowsByID)
      {
        CGFloat w = baseWidth * scales[idx];
        CGFloat h = baseHeight * scales[idx];
        DockMiniWindow *mw = [miniWindowsByID objectForKey: key];
        [mw setFrame: NSMakeRect(x, 0, w, h)];
        x += w;
        idx++;
      }

      separatorRight = x;

      // Trash
      {
        CGFloat w = baseWidth * scales[idx];
        CGFloat h = baseHeight * scales[idx];
        [[icons lastObject] setFrame: NSMakeRect(x, 0, w, h)];
        SET_ICON_SIZE([icons lastObject], idx);
        x += w;
        idx++;
      }

      magnifiedOnce = YES;

      // Center horizontally within the oversize dock bounds
      {
        CGFloat boundsW = [self bounds].size.width;
        if (x < boundsW) {
          CGFloat offset = (boundsW - x) / 2.0;
          NSUInteger ci;
          for (ci = 0; ci < [icons count]; ci++) {
            DockIcon *ic = [icons objectAtIndex: ci];
            NSRect f = [ic frame];
            f.origin.x += offset;
            [ic setFrame: f];
          }
          for (NSNumber *key in miniWindowsByID) {
            DockMiniWindow *mw = [miniWindowsByID objectForKey: key];
            NSRect f = [mw frame];
            f.origin.x += offset;
            [mw setFrame: f];
          }
          separatorLeft += offset;
          separatorRight += offset;
        }
      }
    }
    else
    {
      // Vertical fish-eye (left/right positions)
      NSRect dockBounds = [self bounds];
      CGFloat boundsH = dockBounds.size.height;
      CGFloat totalDefaultHeight = totalItems * baseHeight;
      CGFloat centerOffV = (boundsH > totalDefaultHeight) ? (boundsH - totalDefaultHeight) / 2.0 : 0;

      CGFloat y = boundsH - centerOffV;
      CGFloat scales[totalItems];
      int idx = 0;

      // Horizontal distance from cursor to dock centre (for side docks)
      CGFloat rowCenterX = iconBgRect.origin.x + iconBgRect.size.width / 2.0;
      CGFloat xDist = fabs(magnifyCursorX - rowCenterX);

      // Pass 1: compute scales using 2D Euclidean distance
      // WS
      y -= baseHeight;
      {
        CGFloat dy = cursorMain - (y + baseHeight / 2.0);
        CGFloat dist = sqrt(dy * dy + xDist * xDist);
        scales[idx] = magnifyScaleForDistance(dist);
      }
      idx++;
      y -= baseHeight;

      // Regular apps
      for (i = 1; i < [icons count] - 1; i++)
      {
        y -= baseHeight;
        CGFloat dy = cursorMain - (y + baseHeight / 2.0);
        CGFloat dist = sqrt(dy * dy + xDist * xDist);
        scales[idx] = magnifyScaleForDistance(dist);
        idx++;
      }

      // Mini windows
      for (NSNumber *key in miniWindowsByID)
      {
        (void)key;
        y -= baseHeight;
        CGFloat dy = cursorMain - (y + baseHeight / 2.0);
        CGFloat dist = sqrt(dy * dy + xDist * xDist);
        scales[idx] = magnifyScaleForDistance(dist);
        idx++;
      }

      // Trash
      y -= baseHeight;
      {
        CGFloat dy = cursorMain - (y + baseHeight / 2.0);
        CGFloat dist = sqrt(dy * dy + xDist * xDist);
        scales[idx] = magnifyScaleForDistance(dist);
      }
      idx++;

      // Pass 2: re-cascade positions with scaled sizes
      y = dockBounds.size.height;
      idx = 0;

      // WS
      {
        CGFloat w = baseWidth * scales[idx];
        CGFloat h = baseHeight * scales[idx];
        y -= h;
        [[icons objectAtIndex: 0] setFrame: NSMakeRect(0, y, w, h)];
        SET_ICON_SIZE([icons objectAtIndex: 0], idx);
        idx++;
      }

      // Regular apps
      for (i = 1; i < [icons count] - 1; i++)
      {
        CGFloat w = baseWidth * scales[idx];
        CGFloat h = baseHeight * scales[idx];
        y -= h;
        [[icons objectAtIndex: i] setFrame: NSMakeRect(0, y, w, h)];
        SET_ICON_SIZE([icons objectAtIndex: i], idx);
        idx++;
      }

      separatorLeft = y;

      // Mini windows
      for (NSNumber *key in miniWindowsByID)
      {
        CGFloat w = baseWidth * scales[idx];
        CGFloat h = baseHeight * scales[idx];
        y -= h;
        DockMiniWindow *mw = [miniWindowsByID objectForKey: key];
        [mw setFrame: NSMakeRect(0, y, w, h)];
        idx++;
      }

      separatorRight = y;

      // Trash
      {
        CGFloat w = baseWidth * scales[idx];
        CGFloat h = baseHeight * scales[idx];
        y -= h;
        [[icons lastObject] setFrame: NSMakeRect(0, y, w, h)];
        SET_ICON_SIZE([icons lastObject], idx);
        idx++;
      }

      // Center vertically within the oversize dock bounds
      {
        CGFloat boundsH = [self bounds].size.height;
        NSUInteger ci;
        CGFloat yMin = boundsH, yMax = 0;
        for (ci = 0; ci < [icons count]; ci++) {
          NSRect f = [[icons objectAtIndex: ci] frame];
          if (f.origin.y < yMin) yMin = f.origin.y;
          if (f.origin.y + f.size.height > yMax) yMax = f.origin.y + f.size.height;
        }
        for (NSNumber *key in miniWindowsByID) {
          DockMiniWindow *mw = [miniWindowsByID objectForKey: key];
          NSRect f = [mw frame];
          if (f.origin.y < yMin) yMin = f.origin.y;
          if (f.origin.y + f.size.height > yMax) yMax = f.origin.y + f.size.height;
        }
        CGFloat contentH = yMax - yMin;
        if (contentH < boundsH) {
          CGFloat offset = ((boundsH - contentH) / 2.0) - yMin;
          for (ci = 0; ci < [icons count]; ci++) {
            DockIcon *ic = [icons objectAtIndex: ci];
            NSRect f = [ic frame];
            f.origin.y += offset;
            [ic setFrame: f];
          }
          for (NSNumber *key in miniWindowsByID) {
            DockMiniWindow *mw = [miniWindowsByID objectForKey: key];
            NSRect f = [mw frame];
            f.origin.y += offset;
            [mw setFrame: f];
          }
          separatorLeft += offset;
          separatorRight += offset;
        }
      }
    }
  // Close the if-else; remaining block is the fish-eye block closure.
  }

  // Compute the semi-transparent background rect behind the icons.
  // The height is FIXED (based on base icon size) so it never changes
  // during magnification — only the width adjusts to the number of icons.
  {
    NSUInteger ci;
    CGFloat x0 = 1e9, x1 = -1e9;
    for (ci = 0; ci < [icons count]; ci++) {
      NSRect f = [[icons objectAtIndex: ci] frame];
      if (f.origin.x < x0) x0 = f.origin.x;
      if (f.origin.x + f.size.width > x1) x1 = f.origin.x + f.size.width;
    }
    for (NSNumber *key in miniWindowsByID) {
      DockMiniWindow *mw = [miniWindowsByID objectForKey: key];
      NSRect f = [mw frame];
      if (f.origin.x < x0) x0 = f.origin.x;
      if (f.origin.x + f.size.width > x1) x1 = f.origin.x + f.size.width;
    }
    if (x0 < x1) {
      // Height matches the original dock window (pre-magnification):
      // ceil(iconSize / 3 * 4) with iconSize = 48 → 64 px.
      CGFloat origH = ceil(iconSize / 3 * 4);
      CGFloat pad = 8.0;
      iconBgRect = NSMakeRect(x0 - pad, 0, x1 - x0 + pad * 2, origH);
    }
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

- (NSDragOperation)draggingEntered:(id <NSDraggingInfo>)sender
{
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

  location = [self convertPoint: location fromView: nil];
  icon = [self iconContainingPoint: location];
                 
  if (icon) {
    NSUInteger index = [icons indexOfObjectIdenticalTo: icon];
        
    if (dndSourceIcon && ([sender draggingSource] == dndSourceIcon)) {
      if (icon != dndSourceIcon) {
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
          targetIndex = index;        
          return NSDragOperationMove;
        }
        
      } else if ([[pb types] containsObject: NSFilenamesPboardType]) {
        NSArray *sourcePaths = [pb propertyListForType: NSFilenamesPboardType];
        
        if (!sourcePaths || [sourcePaths count] == 0) {
          NSDebugLLog(@"gwspace", @"Dock: Drag rejected - empty filename pasteboard");
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
          
          targetIndex = index;
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
            [icon unselect];
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
      if ((icon != dndSourceIcon) && ([icon isSpecialIcon] == NO)) {
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
        if ((targetIndex != index) && ([icon isTrashIcon] == NO)) {
          targetIndex = index;
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
            [icon unselect];
          }

        } else if ((targetIndex != index) && ([icon isTrashIcon] == NO)) {
          targetIndex = index;
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

                if ([[checkIcon node] isEqual: node] 
                            && [[checkIcon appName] isEqual: appName]) {
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

@end







