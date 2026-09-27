/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

/* GWQuickLookPanel.h
 *
 * The window Space opens over a folder window's current selection: a
 * normal titled window - not borderless - covering 80% of the screen's
 * visible frame, centered in it, showing ONLY the selected item's
 * contents through the same content viewers the Inspector's Get Info >
 * Contents pane uses (Inspector/ContentViewers, plus the TextViewer /
 * GenericView fallbacks declared in Inspector/Contents.h), with no tab
 * strip and no attribute fields.  Being an ordinary titled, closable
 * window is what makes the WindowManager play its birth/close animation
 * for it, exactly as for a folder window - see
 * gershwin-windowmanager/ANIMATIONS.md; a borderless window gets no such
 * treatment there.
 */

#import <AppKit/AppKit.h>

@interface GWQuickLookPanel : NSWindow
{
  id _sourceWindow;          /* the folder window Quick Look was opened
                               * from; arrow keys are forwarded to its
                               * first responder so the folder's own
                               * selection moves, and the shown item
                               * follows it. */
  id _currentViewer;         /* the live ContentViewersProtocol / TextViewer
                               * / GenericView instance currently shown -
                               * never owned uniquely by this panel (all
                               * three kinds are cached and reused across
                               * Quick Look invocations, like Inspector's
                               * own Contents does), kept only so
                               * -stopTasks can be sent before swapping. */
  NSView *_currentViewerView;
  NSArray *_currentPaths;
}

- (id)initWithPaths:(NSArray *)paths sourceWindow:(id)sourceWindow;

/* Swaps the displayed content without recreating the window - used for
 * arrow-key navigation while Quick Look is open. */
- (void)showPaths:(NSArray *)paths;

/* Maps the window, asking the WindowManager for the birth animation. */
- (void)showAnimated;

/* Asks the WindowManager for the close animation, then unmaps. */
- (void)closeAnimated;

@end
