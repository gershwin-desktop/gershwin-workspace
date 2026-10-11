/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-2.0-or-later
 */

#include <math.h>
#import "FSNBrowserLayout.h"

/* The separator line between two columns. */
#define GAP 1.0

/* Narrow enough for a short name next to its icon, wide enough to keep the
 * resize handle and the scroller usable. */
const CGFloat FSNBrowserMinimumColumnWidth = 100.0;

CGFloat
FSNBrowserClampedColumnWidth(CGFloat width)
{
  width = floor (width);
  return (width < FSNBrowserMinimumColumnWidth) ? FSNBrowserMinimumColumnWidth : width;
}

NSInteger
FSNBrowserLayoutColumns(const CGFloat *widths, NSInteger count,
                        NSInteger first, CGFloat width,
                        CGFloat *origins, CGFloat *shownWidths)
{
  NSInteger last;
  NSInteger i;
  CGFloat x;

  if (count <= 0)
    {
      return -1;
    }
  if (first >= count)
    {
      first = count - 1;
    }

  x = 0;
  for (i = first; i < count; i++)
    {
      origins[i] = x;
      shownWidths[i] = widths[i];
      x += widths[i] + GAP;
    }

  last = first;
  for (i = first; i < count; i++)
    {
      if (i > first && origins[i] + widths[i] > width)
        {
          break;
        }
      last = i;
    }

  x = 0;
  for (i = first - 1; i >= 0; i--)
    {
      x -= widths[i] + GAP;
      origins[i] = x;
      shownWidths[i] = widths[i];
    }

  return last;
}

NSInteger
FSNBrowserFirstColumnShowing(const CGFloat *widths, NSInteger column,
                             CGFloat width)
{
  CGFloat used = widths[column];
  NSInteger first = column;

  while (first > 0 && used + GAP + widths[first - 1] <= width)
    {
      first--;
      used += GAP + widths[first];
    }

  return first;
}
