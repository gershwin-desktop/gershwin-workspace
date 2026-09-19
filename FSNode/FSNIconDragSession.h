/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-2.0-or-later
 */

/* A free-position move of icons of a spatial window or the Desktop.
 *
 * A picture of the icons travels with the pointer in a window of its own,
 * shaped like them, over their own view and over any other of the
 * application's windows alike; the icons stay where they are until they are
 * let go.  When the pointer goes on into another window - one a folder
 * sprang open in, or any other - that window hears about the drag the way
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

/* grabPoint is where the pointer took hold of the icons, in the window's
 * base coordinates, while they are still where they were. */
- (id)initWithIcons:(NSArray *)draggedIcons
             source:(id)sourceIcon
           inWindow:(NSWindow *)window
          grabPoint:(NSPoint)grabPoint;

/* The paths of the dragged icons' nodes. */
- (NSArray *)paths;

/* The application's own window under a screen point, taking the stacking
 * order the window manager reports; nil over none of them. */
- (NSWindow *)windowAtScreenPoint:(NSPoint)p;

/* The picture of the icons follows the pointer to this point. */
- (void)followPointerAtScreenPoint:(NSPoint)p;

/* The pointer is away from the icons' own view - over another window, a
 * different drop view of their own window, or no window at all (window
 * nil).  The picture follows it and the window underneath is told about the
 * drag. */
- (void)dragAwayOverWindow:(NSWindow *)window atScreenPoint:(NSPoint)p;

/* The pointer rests where it was: the window underneath hears of the drag
 * again - that is what times a folder springing open there - but nothing is
 * looked up or moved. */
- (void)dragAwayRests;

/* Back over the view the icons belong to: the window the pointer left
 * hears that the drag has gone. */
- (void)returnToSource;

/* The move ends in the icons' own view, or hands over to GNUstep's drag
 * machinery: the picture goes. */
- (void)finish;

/* Takes the icons out of sight, while their files are moved away by a drop
 * elsewhere. */
- (void)hideIcons;

- (BOOL)isAway;

/* Let go away from the source view.  Returns whether the window under the
 * pointer took the drop. */
- (BOOL)dropAtScreenPoint:(NSPoint)p;

@end

#endif
