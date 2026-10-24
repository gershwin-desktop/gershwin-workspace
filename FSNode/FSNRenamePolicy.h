/*
 * FSNRenamePolicy.h - when renaming an item starts, what is preselected,
 * and which new names need a question or are refused.
 *
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

#ifndef FSN_RENAME_POLICY_H
#define FSN_RENAME_POLICY_H

#import <Foundation/Foundation.h>

/* How editing ended, in the values of AppKit's NSTextMovement (kept here
 * so the policy stays free of AppKit and can be tested headless). */
enum {
  FSNRenameMovementOther = 0,
  FSNRenameMovementReturn = 0x10,
  FSNRenameMovementTab = 0x11,
  FSNRenameMovementBacktab = 0x12,
  FSNRenameMovementCancel = 0x17
};

@interface FSNRenamePolicy : NSObject

/* A click on an item's name starts renaming - once no second click has
 * followed within the double-click interval - when the item already was
 * the only selected one, the click is a single click and no modifier but
 * Option is held (FSNSelectionModel modifiers). */
+ (BOOL)clickStartsRenamingWithCount:(NSInteger)clickCount
                              onName:(BOOL)onName
                     wasOnlySelected:(BOOL)wasOnlySelected
                           modifiers:(unsigned)modifiers;

/* Return or Enter with exactly one item selected and no modifier. */
+ (BOOL)keyStartsRenaming:(unichar)key
                modifiers:(unsigned)modifiers
           selectionCount:(NSUInteger)count;

/* The part of the editor's text selected when editing starts: the name
 * without its last extension, the whole name of a plain folder, and the
 * whole text when the editor shows something else than the name (its
 * extension hidden). */
+ (NSRange)initialSelectionForText:(NSString *)text
                              name:(NSString *)name
                       plainFolder:(BOOL)plainFolder;

/* Whether the way editing ended renames (Return, Enter, Tab, a click
 * elsewhere, another window) or keeps the old name (Escape). */
+ (BOOL)textMovementCommits:(NSInteger)movement;

/* A name the file system can take and the reference accepts: not empty,
 * no slash or colon, no control characters, not "." or "..", at most 255
 * bytes. */
+ (BOOL)isValidName:(NSString *)name;

/* A new name starting with a dot hides the item: the user is asked. */
+ (BOOL)needsHiddenNameConfirmation:(NSString *)newName oldName:(NSString *)oldName;

/* Changing or removing a file's extension may change what opens it: the
 * user is asked. Plain folders have no extension to protect. */
+ (BOOL)needsExtensionConfirmation:(NSString *)newName
                           oldName:(NSString *)oldName
                       plainFolder:(BOOL)plainFolder;

/* The new name with the old extension put back ("Keep .txt"). */
+ (NSString *)name:(NSString *)newName keepingExtensionOf:(NSString *)oldName;

/* Another item already has the name; renaming an item to a different
 * spelling of its own name is allowed. */
+ (BOOL)name:(NSString *)newName
    isTakenAmong:(NSArray *)names
         oldName:(NSString *)oldName;

@end

#endif
