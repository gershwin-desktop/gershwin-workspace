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

/* A monitor's rect in the desktop view: monitorFrame is in device pixels
 * (-[NSScreen frame]), the view is laid out in points of desktopFactor and
 * starts at viewOrigin (points, screen coordinates).  The wallpaper of each
 * monitor fills exactly this rect, so it covers the monitor's pixels at any
 * factor. */
static inline NSRect GWDesktopMonitorViewRect(NSRect monitorFrame,
                                              NSPoint viewOrigin,
                                              CGFloat desktopFactor)
{
  return NSMakeRect(monitorFrame.origin.x / desktopFactor - viewOrigin.x,
                    monitorFrame.origin.y / desktopFactor - viewOrigin.y,
                    monitorFrame.size.width / desktopFactor,
                    monitorFrame.size.height / desktopFactor);
}

/* The size a centered or tiled picture has on a monitor, in the desktop
 * view's points: its own size at the monitor's scale.  The desktop view is
 * scaled by desktopFactor, so a monitor of another scale would otherwise
 * show the picture as large as the desktop's factor makes it. */
static inline NSSize GWDesktopBackImageSizeOnMonitor(NSSize imageSize,
                                                     CGFloat monitorFactor,
                                                     CGFloat desktopFactor)
{
  CGFloat ratio = monitorFactor / desktopFactor;

  return NSMakeSize(imageSize.width * ratio, imageSize.height * ratio);
}
