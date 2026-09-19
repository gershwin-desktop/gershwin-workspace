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
 * and technical machinery toward the periphery), snaps every icon to a shared
 * grid - aligned on both the row lines AND the column lines, with each row
 * centred (some grid positions are left empty for symmetry) and a long label
 * reserving extra empty columns instead of widening the grid.  Rows hold one
 * kind (folders or files, never a mix) with one column span each, so the
 * spacing within a row is uniform; a label wider than the visible viewport is
 * clamped to it, since layout is vertical-scrolling only.  Moves the icons
 * (animating them smoothly from their previous positions, like Clean Up) and
 * persists the new positions through the same DS_Store path as Clean Up.
 * A GNUmakefile is treated like an application: it becomes the central subject
 * and receives a blue label.  Returns YES when positions were applied. */
- (BOOL)alignLogicallyInIconView:(FSNIconsView *)iconView;

/* The same, with the move of the icons animated or not.  An arrangement the
 * user asked for animates, so the icons can be followed from where they were;
 * one done before a window is first shown must not. */
- (BOOL)alignLogicallyInIconView:(FSNIconsView *)iconView animated:(BOOL)animate;

/* Arrange a folder that is opened for the first time: one whose window has no
 * stored geometry and whose icons have no stored positions, so that a source
 * checkout is laid out from the start as though the user had arranged it.
 * Only folders holding a .git directory qualify - the layout's grammar is
 * about source trees.  Returns YES when the icons were arranged. */
- (BOOL)arrangeUnarrangedIconView:(FSNIconsView *)iconView
                        forFolder:(NSString *)folderPath;

@end
