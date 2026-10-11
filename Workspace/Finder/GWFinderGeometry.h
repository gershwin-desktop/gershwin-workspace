/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

#ifndef GWFINDERGEOMETRY_H
#define GWFINDERGEOMETRY_H

#import <Foundation/Foundation.h>

/* The Find window's frame after its criteria box has to change from
 * currentHeight to neededHeight. Both heights are in the box's own
 * coordinates (points), while a window frame is in screen coordinates,
 * which are scaleFactor times larger (GSScaleFactor). The title bar stays
 * where it is. Foundation-only so it can be tested without the Find
 * window's nib. */
NSRect GWFinderFrameForModulesHeight(NSRect frame,
                                     CGFloat currentHeight,
                                     CGFloat neededHeight,
                                     CGFloat scaleFactor);

#endif /* GWFINDERGEOMETRY_H */
