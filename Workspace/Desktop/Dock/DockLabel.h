/* DockLabel.h
 *
 * The name of the Dock icon the pointer rests on, in a dark rounded box
 * with an arrow pointing at the icon: above it when the Dock is at the
 * bottom of the screen, beside it, towards the middle, when it is at a
 * side.  It takes the place of NSView tool tips, which are small, appear at
 * the pointer and cannot follow an icon the magnification moves.
 *
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

#ifndef DOCK_LABEL_H
#define DOCK_LABEL_H

#import <AppKit/AppKit.h>

@interface DockLabel : NSObject

/* The Dock's window passes the events it handles: moving over an icon
 * shows its label after a short delay, a press or a drag puts it away
 * until the pointer has left that icon. */
+ (void)noteEvent:(NSEvent *)event inWindow:(NSWindow *)dockWindow;

/* Puts the label away: the Dock is hidden. */
+ (void)hide;

@end

#endif
