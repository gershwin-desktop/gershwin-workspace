/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-2.0-or-later
 */

/* Where the columns of the column view go, with the widths Finder lets the
 * user set. */

#import <Foundation/Foundation.h>
#import "Testing.h"
#import "FSNBrowserLayout.h"

int
main(void)
{
  NSAutoreleasePool *arp = [NSAutoreleasePool new];
  CGFloat widths[8], origins[8], shown[8];
  NSInteger last;

  /* --- columns side by side ------------------------------------------- */
  widths[0] = widths[1] = widths[2] = widths[3] = 200;
  last = FSNBrowserLayoutColumns (widths, 4, 1, 602, origins, shown);
  PASS (last == 3, "MI-CLM-4 from column 1 on, columns 1-3 are visible");
  PASS (origins[1] == 0 && origins[2] == 201 && origins[3] == 402,
        "MI-CLM-5 visible columns are side by side with one point between");
  PASS (shown[3] == 200, "MI-CLM-6 a column keeps its width up to the right edge");
  PASS (origins[0] + shown[0] < 0, "MI-CLM-7 a column scrolled out to the left is off the view");

  /* --- widths set by the user ----------------------------------------- */
  widths[0] = 100; widths[1] = 300; widths[2] = 150; widths[3] = 150;
  last = FSNBrowserLayoutColumns (widths, 4, 0, 602, origins, shown);
  PASS (origins[1] == 101 && shown[1] == 300,
        "MI-CLM-9 a column keeps the width it was given");
  PASS (origins[2] == 402 && shown[2] == 150,
        "MI-CLM-10 the next column starts after it");
  PASS (last == 2, "MI-CLM-11 the last visible column is the last one that fits whole");
  PASS (origins[3] == 553 && shown[3] == 150,
        "MI-CLM-12 a column that does not fit whole is cut off by the edge, not squeezed");

  last = FSNBrowserLayoutColumns (widths, 4, 0, 50, origins, shown);
  PASS (last == 0, "MI-CLM-13 the first visible column counts as visible even when wider than the view");

  /* --- which column comes first so that a column shows on the right --- */
  PASS (FSNBrowserFirstColumnShowing (widths, 3, 602) == 1,
        "MI-CLM-14 to show column 3, columns 1-3 fit (300+150+150+2)");
  PASS (FSNBrowserFirstColumnShowing (widths, 3, 400) == 2,
        "MI-CLM-15 a narrower view shows fewer columns before it");
  PASS (FSNBrowserFirstColumnShowing (widths, 1, 100) == 1,
        "MI-CLM-16 a column wider than the view is shown from its own left edge");
  PASS (FSNBrowserFirstColumnShowing (widths, 1, 900) == 0,
        "MI-CLM-17 everything fits: start with the first column");

  /* --- the widths a user can give a column ---------------------------- */
  PASS (FSNBrowserClampedColumnWidth (20) == FSNBrowserMinimumColumnWidth,
        "MI-CLM-18 a column cannot be made narrower than the minimum");
  PASS (FSNBrowserClampedColumnWidth (240.4) == 240,
        "MI-CLM-19 widths are whole points");
  PASS (FSNBrowserClampedColumnWidth (0) == FSNBrowserMinimumColumnWidth,
        "MI-CLM-20 zero is no width a user can drag to");

  [arp release];
  return 0;
}
