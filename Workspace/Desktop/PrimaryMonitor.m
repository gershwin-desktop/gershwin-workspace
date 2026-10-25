/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-2.0-or-later
 */

/* Identical copy in gershwin-components and gershwin-workspace; see
 * PrimaryMonitor.h for why and for the rule. */

#import "PrimaryMonitor.h"

#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <X11/extensions/Xrandr.h>

NSInteger PrimaryMonitorChooseIndex(const NSRect *xRects, NSUInteger count,
                                    NSInteger primaryIndex)
{
  NSUInteger i;

  if (count == 0)
    return -1;

  if (primaryIndex >= 0 && (NSUInteger)primaryIndex < count)
    return primaryIndex;

  /* Without a primary, the monitor at the root origin is where X itself
   * starts the screen and where a single-monitor session had everything,
   * so the desktop stays put when a second monitor is added beside it. */
  for (i = 0; i < count; i++)
    {
      NSRect r = xRects[i];

      if (r.origin.x <= 0 && 0 < NSMaxX(r)
          && r.origin.y <= 0 && 0 < NSMaxY(r))
        return (NSInteger)i;
    }

  return 0;
}

NSRect PrimaryMonitorFlipRect(NSRect rect, CGFloat rootHeight)
{
  rect.origin.y = rootHeight - rect.origin.y - rect.size.height;
  return rect;
}

NSSize PrimaryMonitorRootSize(Display *dpy)
{
  Window root, ignoredRoot;
  int x, y;
  unsigned int width, height, border, depth;

  root = RootWindow(dpy, DefaultScreen(dpy));
  if (!XGetGeometry(dpy, root, &ignoredRoot, &x, &y, &width, &height,
                    &border, &depth))
    {
      fprintf(stderr, "PrimaryMonitorRootSize: cannot read the root window\n");
      abort();
    }
  return NSMakeSize(width, height);
}

BOOL PrimaryMonitorQuery(Display *dpy, NSRect *xRect, NSSize *rootSize)
{
  int screen;
  Window root;
  NSSize size;
  NSRect chosen;
  int eventBase, errorBase;

  if (dpy == NULL)
    return NO;

  screen = DefaultScreen(dpy);
  root = RootWindow(dpy, screen);
  size = PrimaryMonitorRootSize(dpy);
  chosen = NSMakeRect(0, 0, size.width, size.height);

  if (XRRQueryExtension(dpy, &eventBase, &errorBase))
    {
      /* The cached resources: the server's current configuration without
       * the output re-probe XRRGetScreenResources forces, which can stall
       * for a long time on some drivers and is not needed to read what is
       * lit right now. */
      XRRScreenResources *res = XRRGetScreenResourcesCurrent(dpy, root);

      if (res != NULL)
        {
          RROutput primary = XRRGetOutputPrimary(dpy, root);
          NSRect *rects = malloc(sizeof(NSRect) * (res->noutput > 0 ? res->noutput : 1));
          NSUInteger count = 0;
          NSInteger primaryIndex = -1;
          int i;

          if (rects == NULL)
            {
              /* Out of memory for a handful of rects: nothing sensible is
               * left to place a desktop with, and guessing the whole screen
               * would put the panels on the wrong monitor. */
              fprintf(stderr, "PrimaryMonitorQuery: out of memory\n");
              abort();
            }

          for (i = 0; i < res->noutput; i++)
            {
              XRROutputInfo *oi = XRRGetOutputInfo(dpy, res, res->outputs[i]);

              if (oi == NULL)
                continue;
              if (oi->crtc != None)
                {
                  XRRCrtcInfo *ci = XRRGetCrtcInfo(dpy, res, oi->crtc);

                  if (ci != NULL)
                    {
                      if (ci->width > 0 && ci->height > 0)
                        {
                          if (res->outputs[i] == primary)
                            primaryIndex = (NSInteger)count;
                          rects[count++] = NSMakeRect(ci->x, ci->y,
                                                      ci->width, ci->height);
                        }
                      XRRFreeCrtcInfo(ci);
                    }
                }
              XRRFreeOutputInfo(oi);
            }

          if (count > 0)
            chosen = rects[PrimaryMonitorChooseIndex(rects, count, primaryIndex)];

          free(rects);
          XRRFreeScreenResources(res);
        }
    }

  if (xRect != NULL)
    *xRect = chosen;
  if (rootSize != NULL)
    *rootSize = size;
  return YES;
}

NSRect PrimaryMonitorScreenFrame(Display *dpy)
{
  NSRect xRect;
  NSSize rootSize;

  if (!PrimaryMonitorQuery(dpy, &xRect, &rootSize))
    return NSZeroRect;
  return PrimaryMonitorFlipRect(xRect, rootSize.height);
}

/* Struts are whole pixels; a panel at a fractional scale must not reserve
 * less than it covers, so the inner side rounds outward. */
static unsigned long StrutValue(CGFloat v)
{
  return (v <= 0) ? 0 : (unsigned long)ceil(v);
}

void PrimaryMonitorStrutForPanel(NSRect barXRect, NSSize rootSize,
                                 PrimaryMonitorEdge edge,
                                 unsigned long strut[12])
{
  unsigned long startX = StrutValue(floor(NSMinX(barXRect)));
  unsigned long endX = StrutValue(NSMaxX(barXRect));
  unsigned long startY = StrutValue(floor(NSMinY(barXRect)));
  unsigned long endY = StrutValue(NSMaxY(barXRect));
  int i;

  for (i = 0; i < 12; i++)
    strut[i] = 0;

  /* The range ends are inclusive pixel indices. */
  if (endX > startX)
    endX--;
  if (endY > startY)
    endY--;

  switch (edge)
    {
      case PrimaryMonitorEdgeTop:
        strut[2] = StrutValue(NSMaxY(barXRect));
        strut[8] = startX;
        strut[9] = endX;
        break;
      case PrimaryMonitorEdgeBottom:
        strut[3] = StrutValue(rootSize.height - floor(NSMinY(barXRect)));
        strut[10] = startX;
        strut[11] = endX;
        break;
      case PrimaryMonitorEdgeLeft:
        strut[0] = StrutValue(NSMaxX(barXRect));
        strut[4] = startY;
        strut[5] = endY;
        break;
      case PrimaryMonitorEdgeRight:
        strut[1] = StrutValue(rootSize.width - floor(NSMinX(barXRect)));
        strut[6] = startY;
        strut[7] = endY;
        break;
    }
}
