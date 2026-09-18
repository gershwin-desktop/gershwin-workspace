/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-2.0-or-later
 */

/* A free-position move of icons that leaves the view it started in.
 *
 * The icons of a spatial window or the Desktop follow the pointer inside
 * their own view.  When the pointer goes on into another of the
 * application's windows - one a folder sprang open in, or any other - the
 * icons cannot follow as views, so they travel on in a window of their own,
 * shaped like them.  The window underneath hears about the drag the way
 * GNUstep's drag machinery would tell it: its drop views get the dragging
 * messages, with this session standing in for the dragging info.  What those
 * views do with a drag - highlighting, springing folders open, deciding and
 * performing the drop - so stays the same for every kind of drag. */

#ifndef FSN_ICON_DRAG_SESSION_H
#define FSN_ICON_DRAG_SESSION_H

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>

@interface FSNIconDragSession : NSObject <NSDraggingInfo>
{
  NSWindow *sourceWindow;
  id source;
  NSArray *icons;
  NSArray *paths;
  NSPasteboard *pboard;
  NSInteger sequence;

  NSImage *image;
  NSWindow *overlay;
  NSPoint grabOffset;
  BOOL away;

  NSWindow *targetWindow;
  NSView *targetView;
  NSDragOperation targetOperation;
  NSPoint location;

  NSArray *windowOrder;
  NSTimeInterval windowOrderTime;
}

- (id)initWithIcons:(NSArray *)draggedIcons
             source:(id)sourceIcon
           inWindow:(NSWindow *)window;

/* The paths of the dragged icons' nodes. */
- (NSArray *)paths;

/* The application's own window under a screen point, taking the stacking
 * order the window manager reports; nil over none of them. */
- (NSWindow *)windowAtScreenPoint:(NSPoint)p;

/* The pointer is somewhere the icons cannot follow as views - over another
 * window, a different drop view of their own window, or no window at all
 * (window nil).  The icons travel on as an image and the window underneath
 * is told about the drag. */
- (void)dragAwayOverWindow:(NSWindow *)window atScreenPoint:(NSPoint)p;

/* The pointer rests where it was: the window underneath hears of the drag
 * again - that is what times a folder springing open there - but nothing is
 * looked up or moved. */
- (void)dragAwayRests;

/* Back over the view the icons belong to: they follow as views again. */
- (void)returnToSource;

- (BOOL)isAway;

/* Let go away from the source view.  Returns whether the window under the
 * pointer took the drop. */
- (BOOL)dropAtScreenPoint:(NSPoint)p;

@end

#endif
