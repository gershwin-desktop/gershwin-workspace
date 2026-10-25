/* t_GWDesktopBackImageGeometry.m - headless coverage for the geometry
 * GWDesktopView uses to render each monitor's wallpaper once into that
 * monitor's device pixels.
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

  {
    NSSize monitor = NSMakeSize(1920, 1080);

    PASS(NSEqualRects(GWDesktopBackImagePixelRect(GWDesktopBackImageFill,
                                                  NSMakeSize(800, 600), monitor),
                      NSMakeRect(0, 0, 1920, 1080)),
         "a filling picture covers every pixel of the monitor");
    PASS(NSEqualRects(GWDesktopBackImagePixelRect(GWDesktopBackImageAspect,
                                                  NSMakeSize(800, 600), monitor),
                      NSMakeRect(240, 0, 1440, 1080)),
         "a scaled picture keeps its aspect, centered, on whole pixels");
    PASS(NSEqualRects(GWDesktopBackImagePixelRect(GWDesktopBackImageCentered,
                                                  NSMakeSize(801, 601), monitor),
                      NSMakeRect(560, 240, 801, 601)),
         "a centered picture keeps its size and starts on a whole pixel");
    PASS(NSEqualRects(GWDesktopBackImagePixelRect(GWDesktopBackImageTopLeft,
                                                  NSMakeSize(100, 50), monitor),
                      NSMakeRect(0, 1030, 100, 50)),
         "the first tile sits at the top left of the monitor");
  }

  [arp release];
  return 0;
}
