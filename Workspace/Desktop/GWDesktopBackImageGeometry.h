/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

/* GWDesktopBackImageGeometry.h - pure geometry helpers shared by
 * GWDesktopView.m and its test, extracted so they can be verified headless
 * without pulling in the view's full dependency graph. */

#import <Foundation/Foundation.h>

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

/* Where the picture goes in a monitor's bitmap, all in device pixels. */
typedef enum {
  GWDesktopBackImageFill,     /* stretched over the whole monitor */
  GWDesktopBackImageAspect,   /* as large as fits, aspect kept, centered */
  GWDesktopBackImageCentered, /* its own size, centered */
  GWDesktopBackImageTopLeft   /* its own size at the top left: the first tile */
} GWDesktopBackImagePlacement;

static inline NSRect GWDesktopBackImagePixelRect(GWDesktopBackImagePlacement placement,
                                                 NSSize image, NSSize monitor)
{
  switch (placement)
    {
      case GWDesktopBackImageFill:
        return NSMakeRect(0, 0, monitor.width, monitor.height);
      case GWDesktopBackImageAspect:
        {
          CGFloat scale = MIN(monitor.width / image.width,
                              monitor.height / image.height);
          CGFloat w = rint(image.width * scale);
          CGFloat h = rint(image.height * scale);

          return NSMakeRect(rint((monitor.width - w) / 2),
                            rint((monitor.height - h) / 2), w, h);
        }
      case GWDesktopBackImageCentered:
        return NSMakeRect(rint((monitor.width - image.width) / 2),
                          rint((monitor.height - image.height) / 2),
                          image.width, image.height);
      case GWDesktopBackImageTopLeft:
      default:
        /* Bitmap coordinates grow upwards. */
        return NSMakeRect(0, monitor.height - image.height,
                          image.width, image.height);
    }
}
