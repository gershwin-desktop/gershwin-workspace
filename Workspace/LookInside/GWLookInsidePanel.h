/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

/* GWLookInsidePanel.h
 *
 * The window Space opens over a folder window's current selection: a
 * normal titled, closable, resizable window - not borderless - showing a
 * GWLookInsidePreviewView of the current item above a strip of controls:
 * previous/next, "n of m" and the overview of all items when several are
 * shown, full screen, and opening the item with its application.  Being an
 * ordinary titled window is what makes the WindowManager play its
 * birth/close animation for it, from and to the item's icon, exactly as for
 * a folder window - see gershwin-windowmanager/ANIMATIONS.md.
 *
 * The panel comes back at the size it had when it was last closed.
 */

#import <AppKit/AppKit.h>

@class GWLookInsidePreviewView;
@class GWLookInsideOverviewView;

@interface GWLookInsidePanel : NSWindow
{
  id _sourceWindow;          /* the folder window Look Inside was opened
                              * from; arrow keys go to its first responder
                              * so the folder's own selection moves, and the
                              * shown item follows it. */
  NSArray *_paths;
  NSUInteger _index;
  BOOL _overviewShown;
  BOOL _fullScreen;
  GWLookInsidePreviewView *_preview;
  GWLookInsideOverviewView *_overview;
  NSButton *_previousButton;
  NSButton *_nextButton;
  NSTextField *_countField;
  NSButton *_overviewButton;
  NSButton *_fullScreenButton;
  NSButton *_openButton;
}

- (id)initWithPaths:(NSArray *)paths sourceWindow:(id)sourceWindow;

/* Shows another set of items without recreating the window - the
 * selection changed while the panel is open. */
- (void)showPaths:(NSArray *)paths;

/* Maps the window, asking the WindowManager for the birth animation, and
 * goes full screen right away when asked to. */
- (void)showAnimatedInFullScreen:(BOOL)fullScreen;

/* Remembers the size, asks the WindowManager for the close animation,
 * then unmaps. */
- (void)closeAnimated;

/* The item shown now, and the actions of the control strip. */
- (NSString *)currentPath;
- (void)showNext:(id)sender;
- (void)showPrevious:(id)sender;
- (void)toggleOverview:(id)sender;
- (void)toggleFullScreen:(id)sender;
- (void)openCurrentItem:(id)sender;

@end
