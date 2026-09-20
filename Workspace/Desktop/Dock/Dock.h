/* Dock.h
 *  
 * Copyright (C) 2005-2012 Free Software Foundation, Inc.
 *
 * Author: Enrico Sersale <enrico@imago.ro>
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


#import <AppKit/NSView.h>
#import "GWDesktopManager.h"
#import "FSNodeRep.h"
#import "DockMagnification.h"

@class NSWindow;
@class NSColor;
@class NSImage;
@class DockIcon;
@class Workspace;

typedef enum DockStyle
{   
  DockStyleClassic = 0,
  DockStyleModern = 1
} DockStyle;

@interface Dock : NSView 
{
  DockPosition position;
  DockStyle style;
  BOOL singleClickLaunch;

  NSMutableArray *icons;
  int iconSize;

  NSColor *backColor;
  
  DockIcon *dndSourceIcon;
  BOOL isDragTarget;
  BOOL forceCopy;
  int dragdelay;
  NSInteger targetIndex;
  NSRect targetRect;

  /* Where folders dragged to the Dock would be kept, while the drag is
   * over a place that keeps them; -1 otherwise. */
  NSInteger folderTargetIndex;
  NSRect folderGapRect;
  /* Between the applications and the folders and Trash. */
  NSRect dividerRect;
  /* The icon a file drag rests on, which springs open. */
  DockIcon *springIcon;
  
  NSTimer *launchRefreshTimer;

  /* The magnification of the expired patent US7434177: while the pointer is
   * on the Dock, the icons around it are drawn larger and the rest slide
   * away to make room.  The view then covers the whole area the enlarged
   * icons reach into, and barRect is the bar itself within it. */
  BOOL magnifyEnabled;
  CGFloat magnifyIconSize;
  /* The effect at its full strength, as the room beside the bar allows. */
  DockMagnification magnification;
  /* How far along the way in the effect is, how much of it that puts on
   * the screen, and where the pointer is along the Dock, from the left or
   * from the top. */
  CGFloat magnifyPhase;
  CGFloat magnifyFraction;
  CGFloat magnifyPos;
  /* Whether the window has been given the room the icons grow into.  It is
   * taken while the effect is still nothing to be seen, so that the growing
   * itself never has to move the window. */
  BOOL magnifyArmed;
  /* The pointer has to be followed before it reaches the Dock, which no
   * event tells us about, so it is looked at on a timer: rarely while it is
   * elsewhere, every frame while it is near. */
  NSTimer *magnifyTimer;
  NSTimeInterval magnifyInterval;
  NSTimeInterval magnifyTime;
  /* The unmagnified size of one cell, and the bar in view coordinates. */
  CGFloat baseCell;
  NSRect barRect;

  GWDesktopManager *manager; 
  Workspace *gw;
  NSFileManager *fm; 
  id ws;
}

- (id)initForManager:(id)mngr;

- (void)createWorkspaceIcon;

- (void)createTrashIcon;

- (DockIcon *)addIconForApplicationAtPath:(NSString *)path
                                 withName:(NSString *)name
                                  atIndex:(NSInteger)index;

- (void)addDraggedIcon:(NSData *)icondata
               atIndex:(NSInteger)index;

/* Keeps a folder in the Dock.  Folders live between the divider and the
 * Trash; the index is clamped into that section. */
- (DockIcon *)addFolderIconAtPath:(NSString *)path
                          atIndex:(NSUInteger)index;

- (void)removeIcon:(DockIcon *)icon;

- (void)saveDockConfiguration;

- (DockIcon *)iconForApplicationPath:(NSString *)path;

- (DockIcon *)iconForApplicationName:(NSString *)name;

/* The icon of an application, looked up by path and then by name: the same
 * application can be reached through several paths (a copy in another
 * domain, a symlink), and it must never get a second icon. */
- (DockIcon *)iconForApplicationPath:(NSString *)path
                                name:(NSString *)name;

- (void)setAppIsX11Only:(BOOL)value
                forPath:(NSString *)path
                   name:(NSString *)name;

- (DockIcon *)workspaceAppIcon;

- (DockIcon *)trashIcon;

- (DockIcon *)iconContainingPoint:(NSPoint)p;

- (void)setDndSourceIcon:(DockIcon *)icon;

- (void)appWillLaunch:(NSString *)appPath
              appName:(NSString *)appName;

- (void)appWillLaunch:(NSString *)appPath
              appName:(NSString *)appName
                  pid:(pid_t)pid;

- (void)appDidLaunch:(NSString *)appPath
             appName:(NSString *)appName;

- (void)appDidLaunch:(NSString *)appPath
             appName:(NSString *)appName
                 pid:(pid_t)pid;

- (void)appTerminated:(NSString *)appPath
             appName:(NSString *)appName;

- (void)appDidHide:(NSString *)appPath
          appName:(NSString *)appName;

- (void)appDidUnhide:(NSString *)appPath
            appName:(NSString *)appName;

- (DockIcon *)iconForApplicationPID:(pid_t)pid;

- (void)iconMenuAction:(id)sender;

- (void)setSingleClickLaunch:(BOOL)value;

- (void)setPosition:(DockPosition)pos;

- (DockPosition)position;

- (DockStyle)style;

- (void)setStyle:(DockStyle)s;

- (void)setBackColor:(NSColor *)color;

- (void)tile;

/* The bar itself, without the room the magnified icons reach into, in
 * screen coordinates: what the Dock takes up when it is left alone. */
- (NSRect)barFrame;

- (void)setMagnificationEnabled:(BOOL)value;

- (BOOL)isMagnificationEnabled;

/* The size an icon is drawn at while the pointer is on it. */
- (void)setMagnifiedIconSize:(CGFloat)size;

- (CGFloat)magnifiedIconSize;

/* Puts the Dock back together at once, with the pointer wherever it is. */
- (void)endMagnification;

/* Whether the Dock watches for the pointer coming near at all; there is
 * nothing to watch for while it is not on the screen. */
- (void)setMagnificationTracking:(BOOL)value;

- (void)updateDefaults;

- (void)checkRemovedApp:(id)sender;

@end


@interface Dock (NodeRepContainer)

- (void)nodeContentsDidChange:(NSDictionary *)info;

- (void)watchedPathChanged:(NSDictionary *)info;

- (void)unselectOtherReps:(id)arep;

- (FSNSelectionMask)selectionMask;

- (void)setBackgroundColor:(NSColor *)acolor;

- (NSColor *)backgroundColor;

- (NSColor *)textColor;

- (NSColor *)disabledTextColor;

@end


@interface Dock (DraggingDestination)

- (NSDragOperation)draggingEntered:(id <NSDraggingInfo>)sender;

- (NSDragOperation)draggingUpdated:(id <NSDraggingInfo>)sender;

- (void)draggingExited:(id <NSDraggingInfo>)sender;

- (BOOL)prepareForDragOperation:(id <NSDraggingInfo>)sender;

- (BOOL)performDragOperation:(id <NSDraggingInfo>)sender;

- (void)concludeDragOperation:(id <NSDraggingInfo>)sender;

- (BOOL)isDragTarget;

@end
