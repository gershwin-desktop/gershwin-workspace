/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

/* Opening something that is not a folder (a document, an application) shows
 * where it came from: the item's icon grows out of its place and fades away
 * while the application comes up.
 *
 * It is drawn by a transparent view laid over the content of the window that
 * shows the icon (a viewer, the desktop), for the few frames the animation
 * lasts; no window of its own.  The icon can therefore only grow as far as
 * that window reaches. */

#ifndef GW_OPEN_ITEM_ANIMATION_H
#define GW_OPEN_ITEM_ANIMATION_H

#import <AppKit/AppKit.h>

@class FSNode;

@interface GWOpenItemAnimation : NSView
{
  NSImage *icon;
  NSRect iconRect;            /* in this view's coordinates */
  NSRect lastDrawnRect;
  NSRect area;                /* the icon's monitor, in this view's coordinates */
  NSTimeInterval startTime;
  NSTimer *timer;
}

/* The icon's rect at `progress` (0 to 1): it grows uniformly about its
   center to GWOpenItemGrowth times its size, keeping its aspect. */
+ (NSRect)rectForIconRect:(NSRect)rect progress:(CGFloat)progress;

/* How far it is at `now` when its clock started at `start`; 0 (the first
   frame) while the clock has not started yet (`start` 0). */
+ (CGFloat)progressAtTime:(NSTimeInterval)now startedAt:(NSTimeInterval)start;

/* Its opacity at `progress`: fully opaque at the start, gone at the end. */
+ (CGFloat)opacityAtProgress:(CGFloat)progress;

/* `rect` moved, at its size, the least distance that keeps it inside
   `area` (the monitor the icon is on): grown near an edge it would be cut
   off there.  Larger than `area` it is centered on it. */
+ (NSRect)rect:(NSRect)rect keptInside:(NSRect)area;

/* The largest rect of the aspect of `size` centered in `rect`: the picture
   is never stretched, whatever rect it is given. */
+ (NSRect)rect:(NSRect)rect fittedToAspectOfSize:(NSSize)size;

/* `rect` of `view` (nil: the window's base coordinates) in the coordinates
   of `overlay`. */
+ (NSRect)iconRectInOverlay:(NSView *)overlay
                    forRect:(NSRect)rect
                     ofView:(NSView *)view;

/* Plays the animation over `window` with `image`, the picture the item
   shows at `screenRect` (a thumbnail, or its icon; nil: the node's icon),
   starting `delay` seconds from now.
   Does nothing without a window, for an empty rect, or with reduced motion. */
+ (void)playImage:(NSImage *)image
           ofNode:(FSNode *)node
         inWindow:(NSWindow *)window
     atScreenRect:(NSRect)screenRect
       afterDelay:(NSTimeInterval)delay;

@end

#endif
