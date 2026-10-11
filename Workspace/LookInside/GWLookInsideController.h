/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

/* GWLookInsideController.h - whether the Look Inside panel should be open,
 * kept apart from the window itself so the toggle rule can be red/green
 * tested without a display: closing always wins (a second Space, from
 * either the panel or the folder window, closes whatever is open, no
 * matter what is selected now), and an empty selection with nothing
 * already open does nothing.
 */

#import <Foundation/Foundation.h>

typedef enum
{
  GWLookInsideActionNone = 0,
  GWLookInsideActionOpen,
  GWLookInsideActionClose
} GWLookInsideAction;

@interface GWLookInsideController : NSObject
{
  BOOL _open;
  id _panel;
  NSArray *_paths;   /* what the open panel was opened for or last followed */
}

+ (GWLookInsideController *)sharedController;

/* Pure decision, no side effects - the part a headless test drives
 * directly. */
+ (GWLookInsideAction)actionForSpaceKeyWithSelectionCount:(NSUInteger)count
                                                  isOpen:(BOOL)isOpen;

- (BOOL)isOpen;

/* Space bar entry point.  `selection` is an array of FSNode (or anything
 * else responding to -path); returns YES if the key press was consumed
 * (the panel opened or closed), NO if there was nothing to do (no
 * selection and nothing open), so the caller can fall through to its
 * normal handling exactly as it did before Look Inside existed. */
- (BOOL)toggleLookInsideForSelection:(NSArray *)selection
                         sourceWindow:(id)sourceWindow;

/* Same toggle, for a caller that already has plain path strings (the
 * "Look Inside" menu item, which uses Workspace's own selectedPaths). */
- (BOOL)toggleLookInsideForPaths:(NSArray *)paths
                     sourceWindow:(id)sourceWindow;

/* Same, opening straight into full screen when `fullScreen` is YES (Option
 * held with Space); a close ignores it. */
- (BOOL)toggleLookInsideForPaths:(NSArray *)paths
                     sourceWindow:(id)sourceWindow
                       fullScreen:(BOOL)fullScreen;

/* Workspace's current selection changed (any folder window or the
 * Desktop).  An open panel shows the new selection, so clicking another
 * item or moving the selection with the arrow keys keeps the preview in
 * step; an emptied selection keeps the last preview rather than blanking
 * it, and a closed panel stays closed. */
- (void)selectionDidChange:(NSArray *)paths;

/* The paths of `nodes` (anything responding to -path), or nil when there
 * is no real selection.  A folder window reports its own folder as its
 * selection while nothing inside it is selected; that is "nothing
 * selected", not a request to look inside the folder itself. */
+ (NSArray *)selectionPathsOfNodes:(NSArray *)nodes baseNode:(id)baseNode;

/* The one Space bar handler for every place that has a selection (folder
 * windows and the Desktop): plain Space toggles the panel, Option-Space
 * opens it straight into full screen, any other modifier is not ours.
 * `nodes` is the selection as the caller knows it, `baseNode` the folder
 * the caller shows (nil for the Desktop).  Returns YES if the key press
 * was consumed. */
- (BOOL)handleSpaceKeyWithCommand:(BOOL)command
                            shift:(BOOL)shift
                          control:(BOOL)control
                           option:(BOOL)option
                        selection:(NSArray *)nodes
                         baseNode:(id)baseNode
                     sourceWindow:(id)sourceWindow;

/* Seam: the folder the key window shows, or nil (Desktop, no window). */
- (id)keyWindowBaseNode;

- (void)close;

/* Overridable seam: the production body (in GWLookInsideController.m)
 * looks GWLookInsidePanel up by name so this class never links the
 * window/AppKit/Inspector-bundle-heavy panel implementation just to be
 * compiled into a headless test; a test subclass overrides both methods
 * to only count calls, so the toggle state above is covered without a
 * display. */
- (void)createAndShowPanelForPaths:(NSArray *)paths
                      sourceWindow:(id)sourceWindow
                        fullScreen:(BOOL)fullScreen;
- (void)showPathsInPanel:(NSArray *)paths;
- (void)destroyPanel;

@end
