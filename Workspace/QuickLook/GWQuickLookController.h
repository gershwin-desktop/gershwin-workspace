/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

/* GWQuickLookController.h - whether the Quick Look panel should be open,
 * kept apart from the window itself so the toggle rule can be red/green
 * tested without a display: closing always wins (a second Space, from
 * either the panel or the folder window, closes whatever is open, no
 * matter what is selected now), and an empty selection with nothing
 * already open does nothing.
 */

#import <Foundation/Foundation.h>

typedef enum
{
  GWQuickLookActionNone = 0,
  GWQuickLookActionOpen,
  GWQuickLookActionClose
} GWQuickLookAction;

@interface GWQuickLookController : NSObject
{
  BOOL _open;
  id _panel;
}

+ (GWQuickLookController *)sharedController;

/* Pure decision, no side effects - the part a headless test drives
 * directly. */
+ (GWQuickLookAction)actionForSpaceKeyWithSelectionCount:(NSUInteger)count
                                                  isOpen:(BOOL)isOpen;

- (BOOL)isOpen;

/* Space bar entry point.  `selection` is an array of FSNode (or anything
 * else responding to -path); returns YES if the key press was consumed
 * (the panel opened or closed), NO if there was nothing to do (no
 * selection and nothing open), so the caller can fall through to its
 * normal handling exactly as it did before Quick Look existed. */
- (BOOL)toggleQuickLookForSelection:(NSArray *)selection
                        sourceWindow:(id)sourceWindow;

/* Same toggle, for a caller that already has plain path strings (the
 * "Quick Look" menu item, which uses Workspace's own selectedPaths). */
- (BOOL)toggleQuickLookForPaths:(NSArray *)paths
                    sourceWindow:(id)sourceWindow;

- (void)close;

/* Overridable seam: the production body (in GWQuickLookController.m)
 * looks GWQuickLookPanel up by name so this class never links the
 * window/AppKit/Inspector-bundle-heavy panel implementation just to be
 * compiled into a headless test; a test subclass overrides both methods
 * to only count calls, so the toggle state above is covered without a
 * display. */
- (void)createAndShowPanelForPaths:(NSArray *)paths sourceWindow:(id)sourceWindow;
- (void)destroyPanel;

@end
