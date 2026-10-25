/* t_GWDesktopBackImageGeometry.m - headless coverage for the source-rect
 * mapping GWDesktopView uses to blit only the dirty part of a cached,
 * pre-scaled wallpaper bitmap (Fit/Scale styles) instead of re-resampling
 * the whole monitor on every partial redraw (a rubber-band drag on the
 * desktop fires drawRect: with thin strips many times a second).
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */
#import <Foundation/Foundation.h>
#import "Testing.h"
#import "../../Workspace/Desktop/GWDesktopBackImageGeometry.h"

int main(void)
{
  NSAutoreleasePool *arp = [NSAutoreleasePool new];

  {
    /* A thin rubber-band-drag dirty strip near the right edge of a single
     * 1920x1080 monitor whose local rect starts at the view's origin. */
    NSRect localRect = NSMakeRect(0, 0, 1920, 1080);
    NSRect dirty = NSIntersectionRect(localRect, NSMakeRect(1000, 10, 10, 1000));
    NSRect src = GWDesktopBackImageSourceRect(localRect, dirty);

    PASS(src.origin.x == 1000 && src.origin.y == 10
         && src.size.width == 10 && src.size.height == 1000,
         "a thin dirty strip maps to the matching small sub-rect of the cached image");
  }

  {
    /* A second monitor placed to the right of the first: the mapping must
     * subtract localRect's own (non-zero) origin, not use the dirty rect
     * verbatim, or the cached bitmap would be sampled from the wrong place. */
    NSRect localRect = NSMakeRect(1920, 0, 1920, 1080);
    NSRect dirty = NSIntersectionRect(localRect, NSMakeRect(1920, 0, 1920, 1080));
    NSRect src = GWDesktopBackImageSourceRect(localRect, dirty);

    PASS(NSEqualRects(src, NSMakeRect(0, 0, 1920, 1080)),
         "a fully dirty offset monitor maps onto the whole cached image, from its own origin");
  }

  {
    /* A dirty rect confined to the lower-left quadrant of an offset
     * monitor only samples that same quadrant of the cached bitmap. */
    NSRect localRect = NSMakeRect(1920, 0, 1920, 1080);
    NSRect dirty = NSIntersectionRect(localRect, NSMakeRect(1920, 0, 960, 540));
    NSRect src = GWDesktopBackImageSourceRect(localRect, dirty);

    PASS(NSEqualRects(src, NSMakeRect(0, 0, 960, 540)),
         "a quadrant of an offset monitor maps to the same quadrant of the cached image");
  }

  {
    /* Two 1920x1080 monitors side by side, the desktop laid out at 1.25:
     * each monitor's wallpaper rect covers exactly its pixels, the second
     * one starting where the first ends. */
    NSRect left = GWDesktopMonitorViewRect(NSMakeRect(0, 0, 1920, 1080),
                                           NSZeroPoint, 1.25);
    NSRect right = GWDesktopMonitorViewRect(NSMakeRect(1920, 0, 1920, 1080),
                                            NSZeroPoint, 1.25);

    PASS(NSEqualRects(left, NSMakeRect(0, 0, 1536, 864))
         && NSEqualRects(right, NSMakeRect(1536, 0, 1536, 864)),
         "each monitor's rect is its pixel frame in the desktop's points");
    PASS(NSWidth(right) * 1.25 == 1920 && NSHeight(right) * 1.25 == 1080,
         "scaled by the desktop's factor the rect is the monitor's full pixel size");
  }

  {
    /* Monitors of different resolutions: a 2560x1440 one left of a
     * 1280x1024 one, aligned at the bottom of the root window. */
    NSRect big = GWDesktopMonitorViewRect(NSMakeRect(0, 0, 2560, 1440),
                                          NSZeroPoint, 2.0);
    NSRect small = GWDesktopMonitorViewRect(NSMakeRect(2560, 416, 1280, 1024),
                                            NSZeroPoint, 2.0);

    PASS(NSEqualRects(big, NSMakeRect(0, 0, 1280, 720))
         && NSEqualRects(small, NSMakeRect(1280, 208, 640, 512)),
         "monitors of different sizes each get their own rect");
  }

  {
    NSSize image = NSMakeSize(800, 600);

    PASS(NSEqualSizes(GWDesktopBackImageSizeOnMonitor(image, 1.25, 1.25), image),
         "a centered picture keeps its size on a monitor of the desktop's scale");
    PASS(NSEqualSizes(GWDesktopBackImageSizeOnMonitor(image, 1.0, 1.25),
                      NSMakeSize(640, 480)),
         "on a 1.0 monitor of a 1.25 desktop it is 640x480 points, 800x600 pixels");
    PASS(NSEqualSizes(GWDesktopBackImageSizeOnMonitor(image, 2.0, 1.0),
                      NSMakeSize(1600, 1200)),
         "on a 2.0 monitor of a 1.0 desktop it is twice as large");
  }

  [arp release];
  return 0;
}
