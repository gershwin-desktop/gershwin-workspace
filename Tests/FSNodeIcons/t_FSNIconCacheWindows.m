/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 */

/* The icons FSNodeRep keeps must not add X windows without bound.  libs-gui
 * caches every drawn NSImage in a hidden GSCacheW window that lives as long
 * as the image, so a Workspace that had shown many folders held more than a
 * thousand unmapped top-level windows, which the X server and the
 * compositor walk and track. */

#import <AppKit/AppKit.h>
#import "Testing.h"
#import "FSNodeRep.h"

static NSUInteger
cacheWindowCount(void)
{
  NSUInteger n = 0;

  for (NSWindow *w in GSAllWindows())
    {
      if ([NSStringFromClass([w class]) isEqual: @"GSCacheW"])
        {
          n++;
        }
    }
  return n;
}

static NSImage *
bitmapIcon(int side, CGFloat gray)
{
  NSBitmapImageRep *rep = [[NSBitmapImageRep alloc]
    initWithBitmapDataPlanes: NULL pixelsWide: side pixelsHigh: side
               bitsPerSample: 8 samplesPerPixel: 4 hasAlpha: YES isPlanar: NO
              colorSpaceName: NSCalibratedRGBColorSpace
                 bytesPerRow: 0 bitsPerPixel: 32];
  unsigned char *p = [rep bitmapData];
  NSImage *img = [[NSImage alloc] initWithSize: NSMakeSize(side, side)];
  int i;

  for (i = 0; i < side * side; i++)
    {
      p[i * 4] = p[i * 4 + 1] = p[i * 4 + 2] = (unsigned char)(gray * 255);
      p[i * 4 + 3] = 255;
    }
  [img addRepresentation: rep];
  [rep release];
  return [img autorelease];
}

int
main(void)
{
  NSAutoreleasePool *arp = [NSAutoreleasePool new];
  FSNodeRep *rep;
  NSWindow *win;
  NSUInteger before;
  NSUInteger after;
  NSString *lastKey;
  int i;
  const int N = 3 * FSNIconCacheCapacity;

  [NSApplication sharedApplication];
  rep = [FSNodeRep sharedInstance];
  win = [[NSWindow alloc] initWithContentRect: NSMakeRect(0, 0, 200, 200)
                                    styleMask: NSBorderlessWindowMask
                                      backing: NSBackingStoreBuffered
                                        defer: NO];

  /* Warm-up: the first draw sets up whatever libs-gui and the backend keep
   * once per process. */
  [[win contentView] lockFocus];
  [[rep cachedIconOfSize: 24 forKey: @"warmup" addBaseIcon: bitmapIcon(64, 0.2)]
    drawAtPoint: NSZeroPoint fromRect: NSZeroRect
      operation: NSCompositeSourceOver fraction: 1.0];
  [[win contentView] unlockFocus];

  before = cacheWindowCount();
  for (i = 0; i < N; i++)
    {
      NSAutoreleasePool *p = [NSAutoreleasePool new];
      NSString *key = [NSString stringWithFormat: @"/t_FSNIconCacheWindows/%d", i];
      NSImage *base = [rep cachedIconOfSize: 48 forKey: key
                                addBaseIcon: bitmapIcon(64, (i % 10) / 10.0)];
      NSImage *small = [rep cachedIconOfSize: 16 forKey: key];

      [[win contentView] lockFocus];
      [base drawAtPoint: NSZeroPoint fromRect: NSZeroRect
              operation: NSCompositeSourceOver fraction: 1.0];
      [small drawAtPoint: NSMakePoint(60, 0) fromRect: NSZeroRect
               operation: NSCompositeSourceOver fraction: 1.0];
      [[win contentView] unlockFocus];
      [p release];
    }
  after = cacheWindowCount();
  PASS(after <= before + 2 * FSNIconCacheCapacity,
       "drawing %d different cached icons in two sizes keeps at most two cache windows per cache entry (%lu before, %lu after, capacity %d)",
       N, (unsigned long)before, (unsigned long)after, (int)FSNIconCacheCapacity);
  lastKey = [NSString stringWithFormat: @"/t_FSNIconCacheWindows/%d", N - 1];
  PASS([rep cachedIconOfSize: 48 forKey: lastKey] != nil,
       "the icon used last is still in the cache");
  PASS([rep cachedIconOfSize: 48 forKey: @"/t_FSNIconCacheWindows/0"] == nil,
       "the icon used longest ago has been dropped");

  [win release];
  [arp release];
  return 0;
}
