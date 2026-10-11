/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-2.0-or-later
 */

/* Where the columns of a column view go.  Kept apart from FSNBrowser so the
 * arithmetic can be checked without a window. */

#ifndef FSN_BROWSER_LAYOUT_H
#define FSN_BROWSER_LAYOUT_H

#import <Foundation/Foundation.h>

/* The narrowest column a user can drag to. */
extern const CGFloat FSNBrowserMinimumColumnWidth;

/* A width a user may give a column: whole points, not below the minimum. */
CGFloat FSNBrowserClampedColumnWidth(CGFloat width);

/* Lays out count columns of the given widths so that column first starts at
 * the left edge of a view width wide; columns before it lie to the left of
 * the view, one point apart like the others.  Writes each column's origin
 * and shown width and returns the last column that is visible whole (first
 * at least, when first < count).  A column that does not fit whole is cut
 * off by the right edge, never squeezed. */
NSInteger FSNBrowserLayoutColumns(const CGFloat *widths, NSInteger count,
                                  NSInteger first, CGFloat width,
                                  CGFloat *origins, CGFloat *shownWidths);

/* The first column to show so that column is visible whole at the right with
 * as many columns before it as fit; column itself when it alone is wider
 * than the view. */
NSInteger FSNBrowserFirstColumnShowing(const CGFloat *widths, NSInteger column,
                                       CGFloat width);

#endif /* FSN_BROWSER_LAYOUT_H */
