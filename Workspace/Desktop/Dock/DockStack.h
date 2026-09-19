/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-2.0-or-later
 */

/* Stacks: clicking a folder kept in the Dock shows what is in it, right at
 * the Dock, without opening a viewer - as a fan of icons rising from a Dock
 * at the bottom of the screen, as a grid of icons, or as a list with the
 * folders in it as submenus.  An item opens with a click and can be dragged
 * out; "Open in Workspace" opens the folder itself. */

#ifndef DOCK_STACK_H
#define DOCK_STACK_H

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>

@class DockIcon;

typedef enum
{
  DockStackViewAutomatic = 0,
  DockStackViewFan = 1,
  DockStackViewGrid = 2,
  DockStackViewList = 3
} DockStackViewStyle;

typedef enum
{
  DockStackSortName = 0,
  DockStackSortDateAdded = 1,
  DockStackSortDateModified = 2,
  DockStackSortKind = 3
} DockStackSort;

@interface DockStack : NSObject
{
  DockIcon *icon;
  NSWindow *window;
  NSMenu *menu;
  /* The folder each list menu shows, by menu. */
  NSMutableDictionary *menuFolders;
}

/* Shows the stack of the folder icon, or closes it when it is the one
 * shown.  event is the click that asked for it. */
+ (void)toggleForIcon:(DockIcon *)icon event:(NSEvent *)event;

/* Closes the stack shown, if any. */
+ (void)close;

/* Closes the stack of this icon, if it is shown - the icon is going away. */
+ (void)closeForIcon:(DockIcon *)icon;

/* A window passes the events it handles: a press anywhere but in the stack
 * puts the stack away.  The stack is not always the key window, so losing
 * the keyboard cannot be relied on to tell. */
+ (void)noteEvent:(NSEvent *)event inWindow:(NSWindow *)aWindow;

@end

#endif
