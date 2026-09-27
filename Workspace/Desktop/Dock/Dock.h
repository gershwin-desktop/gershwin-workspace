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

/* The pointer is looked at every frame while it is anywhere near the Dock.
 * Further away it is looked at just often enough to catch it coming: the
 * time it would need to cross what is left of the distance, at a speed no
 * pointer is pushed past, and never less often than the idle interval. */
#define MAGNIFY_FRAME_INTERVAL (1.0 / 60.0)
#define MAGNIFY_IDLE_INTERVAL 0.25
/* A pointer that is not headed for the Dock spends most of its time further
 * from the bar than this speed and the idle interval add up to, so it is a
 * comfortable, deliberate approach rather than the fastest a hand can move a
 * mouse: measured live, the old 4000 px/s left the Dock polling at ~12 Hz
 * indefinitely at a resting position a few hundred points away, because the
 * distance needed to reach MAGNIFY_IDLE_INTERVAL scaled with it (1000 px).
 * Lower and the idle rate is actually reached at realistic "parked" spots;
 * a flick that covers this speed's reach within one idle interval can still
 * arrive a frame late, exactly as a flick beyond the old 1000 px bound
 * already could. */
#define MAGNIFY_POINTER_SPEED 1000.0

/* Foundation-only so it can be tested headless (Tests/Dock). Takes the
 * in-progress flag as a parameter rather than reading it off a Dock, so the
 * timing rule can be proven without building one. */
static inline NSTimeInterval
DockMagnifyPollInterval(CGFloat distance, CGFloat near, BOOL armed)
{
  NSTimeInterval wait;

  if (armed || (distance < near))
    return MAGNIFY_FRAME_INTERVAL;

  wait = (distance - near) / MAGNIFY_POINTER_SPEED;

  if (wait < MAGNIFY_FRAME_INTERVAL)
    return MAGNIFY_FRAME_INTERVAL;
  if (wait > MAGNIFY_IDLE_INTERVAL)
    return MAGNIFY_IDLE_INTERVAL;

  return wait;
}

/* Whether -refreshLaunchedStateWorker: would actually touch X for an icon in
 * this state, so a round can leave out the ones it would only relay back
 * unchanged: an X11-tracked icon always re-checks its windows, and a
 * launched icon whose pid is not yet known tries once to discover it (see
 * DockIcon.m); anything else takes the early-return path that makes no X
 * call at all. Foundation-only so it can be tested headless. */
static inline BOOL
DockIconNeedsLaunchedStateScan(BOOL isX11OnlyApp, BOOL isLaunched, pid_t appPID)
{
  return isX11OnlyApp || (isLaunched && (appPID <= 0));
}

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

  /* The one worker thread every launch-refresh round hands its X scans to
   * (see -_launchRefreshTimerFired: in Dock.m), instead of each round
   * detaching a thread of its own: a Dock with eighteen icons used to open
   * ten fresh threads and X connections a second even at rest.  Started on
   * first use, stopped in -dealloc.  -[DockIcon refreshLaunchedStateAsync]
   * shares it too, through -performLaunchRefreshSelector:target:withObject:,
   * rather than pay for a second persistent thread beside this one.  Mirrors
   * -[GWX11AppManager scanThread] in X11AppSupport.m; kept as Dock's own
   * rather than moved into GWX11WindowManager because this worktree does not
   * touch X11AppSupport.h/.m. */
  NSThread *launchRefreshThread;
  volatile BOOL launchRefreshThreadShouldStop;

  /* The magnification of the expired patent US7434177: while the pointer is
   * on the Dock, the icons around it are drawn larger and the rest slide
   * away to make room.  The view then covers the whole area the enlarged
   * icons reach into, and barRect is the bar itself within it. */
  BOOL magnifyEnabled;
  /* How large the icon under the pointer is drawn: the "docklargesize"
   * default, in the same units as the icons' own size. */
  CGFloat largeIconSize;
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

/* The Trash icon's current on-screen rect, in AppKit screen coordinates
 * (origin bottom-left) - the destination for the "fly to Trash" animation
 * (Workspace -moveToTrash / GWTrashFlight).  NSZeroRect when the Trash icon
 * or its window cannot be resolved (Dock not yet shown). */
- (NSRect)trashIconScreenRect;

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
- (void)setLargeIconSize:(CGFloat)size;

- (CGFloat)largeIconSize;

/* Puts the Dock back together at once, with the pointer wherever it is. */
- (void)endMagnification;

/* Whether the Dock watches for the pointer coming near at all; there is
 * nothing to watch for while it is not on the screen. */
- (void)setMagnificationTracking:(BOOL)value;

- (void)updateDefaults;

- (void)checkRemovedApp:(id)sender;

/* Hands a launch-refresh scan off to the Dock's one persistent worker
 * thread (starting it on first use) instead of detaching a thread of its
 * own for the call: see the launchRefreshThread ivar comment above and
 * -_launchRefreshTimerFired: in Dock.m. -[DockIcon refreshLaunchedStateAsync]
 * calls this through -dock so a single icon's own refresh shares the same
 * thread and X connection as the Dock's own round. Runs @p selector on
 * @p target with @p argument; always asynchronous (waitUntilDone: NO), the
 * same as the X scans it replaces - the caller must not depend on the
 * result being ready when this returns. */
- (void)performLaunchRefreshSelector:(SEL)selector
                               target:(id)target
                           withObject:(id)argument;

/* Stops the persistent worker thread and drops its X connection. Called
 * from -dealloc; exposed so Tests/Dock can prove the thread does not
 * outlive the object without building a whole Dock. */
- (void)stopLaunchRefreshThread;

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
