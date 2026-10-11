/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>

@class FinderInfoModel;

/**
 * The Inspector's "Finder Info" pane: the controls of Finder's Get Info
 * window for the metadata Workspace shares with the Mac Finder.  Built in
 * code; edits are held in a FinderInfoModel until Apply.
 */
@interface FinderInfoPanel : NSObject <NSTextFieldDelegate, NSTextViewDelegate>
{
  NSView *_view;
  id _inspector;
  NSString *_currentPath;
  FinderInfoModel *_model;
  BOOL _dirty;

  NSImageView *_iconWell;
  NSTextField *_nameField;
  NSTextField *_noticeField;
  NSButton *_hideExtensionButton;
  NSButton *_lockedButton;
  NSButton *_nameLockedButton;
  NSButton *_stationeryButton;
  NSButton *_invisibleButton;
  NSTextField *_labelCaption;
  NSPopUpButton *_labelPopUp;
  NSTextField *_typeCaption;
  NSTextField *_typeField;
  NSTextField *_creatorCaption;
  NSTextField *_creatorField;
  NSTextField *_iconCaption;
  NSButton *_pasteIconButton;
  NSButton *_clearIconButton;
  NSTextField *_commentCaption;
  NSScrollView *_commentScroll;
  NSTextView *_commentView;
  NSButton *_revertButton;
  NSButton *_applyButton;
}

- (instancetype)initForInspector:(id)insp;
- (NSView *)inspView;
- (NSString *)winname;
- (void)activateForPaths:(NSArray *)paths;
- (void)watchedPathDidChange:(NSDictionary *)info;

/** Pane geometry, separate from the views so the layout can be unit tested. */
- (void)layoutInSize:(NSSize)size;

@end
