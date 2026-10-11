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
  NSTimeInterval startTime;
  NSTimer *timer;
}

/* The icon's rect at `progress` (0 to 1): it grows about its centre to
   GWOpenItemGrowth times its size. */
+ (NSRect)rectForIconRect:(NSRect)rect progress:(CGFloat)progress;

/* Its opacity at `progress`: fully opaque at the start, gone at the end. */
+ (CGFloat)opacityAtProgress:(CGFloat)progress;

/* The part of a list row or browser cell rect the icon takes: a square at
   its left end.  Icon-view rects are already square and kept as they are. */
+ (NSRect)iconPartOfRect:(NSRect)rect;

/* Plays the animation over `window` for `node` whose icon is at `screenRect`.
   Does nothing without a window, for an empty rect, or with reduced motion. */
+ (void)playForNode:(FSNode *)node
           inWindow:(NSWindow *)window
       atScreenRect:(NSRect)screenRect;

@end

#endif
