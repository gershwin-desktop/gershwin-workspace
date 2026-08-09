/* GWAlignLogically.h
 *
 * "View ▸ Arrange Logically" - semantic spatial arrangement for spatial views.
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>

@class FSNIconsView;

@interface GWAlignLogically : NSObject

+ (instancetype)sharedAligner;

/* One-shot semantic arrangement of a spatial icon view: classifies every icon
 * by semantic role (entry point, primary artifact, source, documentation, ...),
 * composes a spatial layout with a classic spatial grammar (README up top, the
 * main object central, source on the left, documentation on the right, tests
 * and technical machinery toward the periphery), snaps every icon to a grid
 * (dense, never more than one empty row, dense rows optionally staggered),
 * moves the icons and persists the new positions through the same DS_Store
 * path as Clean Up.  A GNUmakefile is treated like an application: it becomes
 * the central subject and receives a blue label.  Returns YES when positions
 * were applied. */
- (BOOL)alignLogicallyInIconView:(FSNIconsView *)iconView;

@end
