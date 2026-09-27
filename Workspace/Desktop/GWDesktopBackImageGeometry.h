/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

/* GWDesktopBackImageGeometry.h - pure geometry helper shared by
 * GWDesktopView.m and its test, extracted so the mapping can be verified
 * headless without pulling in the view's full dependency graph. */

#import <Foundation/Foundation.h>

/* Maps a dirty rect - given in the same view-local coordinate space as
 * localRect, a monitor's onscreen rect - to the matching sub-rect of an
 * image that was pre-rendered at exactly localRect's size.  This lets a
 * partial redraw blit only the dirty portion of a cached wallpaper bitmap
 * instead of re-resampling the whole monitor on every call: a rubber-band
 * selection drag on the desktop fires drawRect: with a thin strip many
 * times a second, and each of those calls used to rescale the entire
 * Fit/Scale wallpaper regardless of how small the dirty rect was.
 *
 * Both rects must already be expressed in the same coordinate space
 * (dirtyRect is normally the intersection of localRect with the view's
 * drawRect: argument); the result subtracts localRect's own origin so a
 * monitor placed anywhere in a multi-monitor layout still maps onto the
 * cached image's own (0,0)-based space. */
static inline NSRect GWDesktopBackImageSourceRect(NSRect localRect, NSRect dirtyRect)
{
  return NSMakeRect(dirtyRect.origin.x - localRect.origin.x,
                     dirtyRect.origin.y - localRect.origin.y,
                     dirtyRect.size.width,
                     dirtyRect.size.height);
}
