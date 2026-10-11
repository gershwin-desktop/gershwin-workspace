/* GWFileUndoRecord.h
 *
 * What one finished file operation did, in a form that can be reversed and
 * performed again: the paths each item had before and after, and the
 * identity (device and inode) the item had right after the operation, so
 * that undo can tell whether it would act on the very item the operation
 * produced or on something that took its name since.
 *
 * Undo and redo are expressed as ordinary Operation dictionaries, so they
 * run through the same executor as every other file operation and carry
 * the Finder metadata (extended attributes, "._" sidecar) exactly as a
 * copy or move does.  The record never guesses: when a path no longer
 * holds what it held, or a name it would use is taken, it refuses with an
 * error that names the item.
 *
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-2.0-or-later
 */

#import <Foundation/Foundation.h>

/* Item keys of -items and of the array FileOpInfo hands to the stack. */
extern NSString * const GWFileUndoFromKey;
extern NSString * const GWFileUndoToKey;

extern NSString * const GWFileUndoErrorDomain;

enum {
  GWFileUndoErrorItemGone = 1,
  GWFileUndoErrorNameTaken = 2,
  GWFileUndoErrorItemReplaced = 3
};

/* The operation name Workspace uses for "New Folder". */
extern NSString * const GWFileUndoCreateDirOperation;
extern NSString * const GWFileUndoRenameOperation;
extern NSString * const GWFileUndoRecycleOutOperation;

@interface GWFileUndoRecord : NSObject
{
  NSString *operation;
  NSArray *items;
  NSArray *identities;
}

/**
 * Whether operations of this type can be undone.  Deleting and emptying
 * the trash cannot, as in the Finder.
 */
+ (BOOL)isUndoableOperation:(NSString *)type;

/**
 * A record of an operation of type `type' that has just finished with
 * `doneItems' (dictionaries with GWFileUndoFromKey, the item's path before,
 * absent for a new folder, and GWFileUndoToKey, its path after).  The
 * identity of every resulting item is taken now.  nil when the type is not
 * undoable or nothing was done.
 */
+ (instancetype)recordWithOperation:(NSString *)type
                              items:(NSArray *)doneItems;

- (NSString *)operation;

- (NSArray *)items;

/**
 * The action as the Edit menu names it, e.g. 'Move of "x"' or
 * 'Copy of 3 Items'; localized.
 */
- (NSString *)actionName;

/**
 * The operation dictionaries that reverse this one, after checking that
 * every item is still where the operation put it (the very item, not one
 * that took its name) and that every name it goes back to is free.
 * `trashPath' receives what a creating operation made.  nil and *error
 * set when anything changed.
 */
- (NSArray *)undoOperationsWithTrashPath:(NSString *)trashPath
                                   error:(NSError **)error;

/**
 * The operation dictionaries that perform this operation again after it
 * was undone, after checking that the originals are back and the names
 * they go to are free.  nil and *error set otherwise.
 */
- (NSArray *)redoOperationsWithError:(NSError **)error;

@end
