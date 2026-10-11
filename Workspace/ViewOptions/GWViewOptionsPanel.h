/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 */

/* Show View Options: one panel for the front viewer window, whose changes
 * are applied to the window at once and kept for the folder in the records
 * Finder reads (.DS_Store icvp, lsvp, vstl).  It follows the front viewer
 * window while it is open. */

#import <AppKit/AppKit.h>

@class GWViewOptionsModel;
@class GWViewersManager;

@interface GWViewOptionsPanel : NSObject
{
  NSPanel *panel;
  GWViewersManager *viewersManager;
  GWViewOptionsModel *model;
  id viewer;
  NSWindow *viewerWindow;
  NSWindow *lastViewerWindow;
  BOOL loading;
  BOOL placementRestored;
  BOOL placementSaving;

  NSView *iconPane;
  NSView *listPane;
  NSView *columnPane;
  NSTextField *emptyLabel;
  NSButton *alwaysOpenButton;

  NSTextField *iconSizeLabel;
  NSSlider *iconSizeSlider;
  NSSlider *gridSpacingSlider;
  NSPopUpButton *textSizePopUp;
  NSPopUpButton *labelPositionPopUp;
  NSButton *itemInfoButton;
  NSButton *iconPreviewButton;
  NSPopUpButton *arrangePopUp;
  NSPopUpButton *backgroundPopUp;
  NSColorWell *colorWell;
  NSButton *pictureButton;
  NSImageView *pictureWell;

  NSPopUpButton *listTextSizePopUp;
  NSPopUpButton *listIconSizePopUp;
  NSMutableDictionary *columnButtons;
  NSButton *relativeDatesButton;
  NSButton *allSizesButton;

  NSPopUpButton *columnTextSizePopUp;
  NSButton *columnIconsButton;
  NSButton *columnPreviewButton;
  NSButton *columnPreviewColumnButton;
  NSPopUpButton *columnArrangePopUp;
}

+ (GWViewOptionsPanel *)sharedPanel;

/* The manager that tells which viewer a window belongs to.  Set it when
 * the application starts: the panel remembers the last front viewer from
 * then on. */
- (void)setViewersManager:(GWViewersManager *)manager;

/* Shows the panel for @p aviewer (a GWViewer or GWSpatialViewer); nil shows
 * it with nothing to edit.  Brings it to the front. */
- (void)showForViewer:(id)aviewer;

/* Shows the panel for the viewer of the main window, if there is one. */
- (void)showForMainWindow;

/* Whether a viewer window is there to edit the options of. */
- (BOOL)hasViewerToEdit;

- (NSPanel *)panel;

@end
