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

  [arp release];
  return 0;
}
