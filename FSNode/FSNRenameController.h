/*
 * FSNRenameController.h - the one place that runs renaming an item in place,
 * for the icon, list and column views and the desktop.
 *
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

#ifndef FSN_RENAME_CONTROLLER_H
#define FSN_RENAME_CONTROLLER_H

#import <Foundation/Foundation.h>
#import <AppKit/NSTextField.h>

@class FSNode;
@class NSTextView;

/* A view whose items can be renamed in place. It owns the editor and puts
 * it over the name; the controller decides when editing starts and ends and
 * what the new name becomes. */
@protocol FSNRenameHost <NSObject>
/* Shows the editor over the name of "rep", holding the item's name and
 * sized for the theme's text field bezel the controller gives it, and
 * returns it; nil when that item cannot be renamed (locked, a mount
 * point). The controller makes it editable and selects in it. */
- (NSTextField *)nameEditorForRenamingRep:(id)rep;
/* Takes the editor away without renaming. */
- (void)stopRepNameEditing;
@end

@interface FSNRenameController : NSObject
{
  id _desktopApp;
  NSTimer *_pendingTimer;
  id _pendingRep;
  id<FSNRenameHost> _pendingHost;
  NSTextField *_editor;
  FSNode *_node;
  id<FSNRenameHost> _host;
  /* The last rename and the view its item is selected in again once the
     rename, or its undo or redo, has gone through. */
  NSString *_renamedSource;
  NSString *_renamedPath;
  NSString *_selectPath;
  id _renamedHost;
  id _committingHost;
  /* How the editor looked before editing; it gets that look back. */
  NSColor *_savedBackground;
  NSColor *_savedTextColor;
  BOOL _savedBordered;
  BOOL _savedBezeled;
  BOOL _savedDrawsBackground;
  NSView *_savedNextKeyView;
  NSView *_savedViewNextKeyView;
}

+ (FSNRenameController *)sharedController;

/* A click on the name of the only selected item: renaming starts after the
 * double-click interval, unless another press comes first (a double click
 * opens instead). */
- (void)scheduleRenameOfRep:(id)rep inHost:(id<FSNRenameHost>)host;
- (void)cancelScheduledRename;

/* Starts at once (Return). NO when the item cannot be renamed. */
- (BOOL)beginRenameOfRep:(id)rep inHost:(id<FSNRenameHost>)host;

- (BOOL)isEditing;
- (BOOL)isEditingInHost:(id<FSNRenameHost>)host;

/* A press anywhere else ends editing the way the reference does: with the
 * new name. Every view calls this before acting on a press. YES when an
 * editing session ended. */
- (BOOL)commitActiveEditing;

/* The editor delegate methods of every host forward here. */
- (BOOL)control:(NSControl *)control
       textView:(NSTextView *)textView
doCommandBySelector:(SEL)command;
- (void)editorDidEndEditing:(NSNotification *)notification
                       node:(FSNode *)node
                       host:(id<FSNRenameHost>)host;

/* Renames "node" to what the user typed: checks the name, asks about a
 * leading dot or a changed extension, refuses names in use, and performs
 * the rename. For editors the controller does not run itself (the path
 * bar). */
- (void)renameNode:(FSNode *)node toEditedText:(NSString *)text;

@end

#endif
