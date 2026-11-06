/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

/* The rect the window manager animates a folder window from (birth) or
 * into (close) is given in X root coordinates; Workspace knows the folder
 * icon in GNUstep screen coordinates. */

#ifndef GW_WINDOW_ANIMATION_GEOMETRY_H
#define GW_WINDOW_ANIMATION_GEOMETRY_H

#import <Foundation/Foundation.h>

/* `screenRect` in GNUstep screen coordinates (as -convertRectToScreen:
   gives it: device pixels, origin at the bottom left of the whole X
   screen, not of the monitor the rect is on) as a rect in X root
   coordinates (origin top left, y down) of an X screen `rootHeight`
   pixels tall, its edges rounded to whole pixels. */
NSRect GWX11RootRectForScreenRect(NSRect screenRect, CGFloat rootHeight);

#endif
