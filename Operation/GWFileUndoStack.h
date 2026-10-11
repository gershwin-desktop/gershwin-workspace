/* GWFileUndoStack.h
 *
 * The undo and redo history of file operations behind Edit > Undo and
 * Edit > Redo.  Every undoable operation that finishes (see
 * GWFileUndoRecord) is pushed by FileOpInfo; undo and redo hand the
 * reversing or repeating operations to the performer, which in Workspace
 * is the Operation controller, so they show the usual progress and post
 * the usual change notifications.
 *
 * Operations started by undo or redo carry GWFileUndoRoleKey in their
 * dictionary.  When such an operation finishes, it must not be taken as a
 * new user action: an undo leaves the history alone, a redo pushes its
 * fresh record without clearing what is left to redo.
 *
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-2.0-or-later
 */

#import <Foundation/Foundation.h>

@class GWFileUndoRecord;

/* Key in an operation dictionary; its value is one of the roles below. */
extern NSString * const GWFileUndoRoleKey;
extern NSString * const GWFileUndoRoleUndo;
extern NSString * const GWFileUndoRoleRedo;

@protocol GWFileUndoPerformer
- (void)performOperation:(NSDictionary *)opdict;
@end

@interface GWFileUndoStack : NSObject
{
  NSMutableArray *undoRecords;
  NSMutableArray *redoRecords;
  NSString *trashPath;
  id <GWFileUndoPerformer> performer;
  NSUInteger levels;
}

+ (GWFileUndoStack *)sharedStack;

/** Not retained; Workspace's Operation controller outlives the stack's use. */
- (void)setPerformer:(id <GWFileUndoPerformer>)anObject;

/** Where undoing a copy, duplicate, alias or new folder puts the result. */
- (void)setTrashPath:(NSString *)path;
- (NSString *)trashPath;

/** How many operations are kept; the oldest is dropped beyond that. */
- (void)setLevelsOfUndo:(NSUInteger)n;

/**
 * Called when an operation ended with `doneItems' (see
 * +[GWFileUndoRecord recordWithOperation:items:]).  `role' is the
 * GWFileUndoRoleKey of its dictionary, nil for a user action.
 */
- (void)fileOperation:(NSString *)type
   didFinishWithItems:(NSArray *)doneItems
                 role:(NSString *)role;

- (BOOL)canUndo;
- (BOOL)canRedo;

- (GWFileUndoRecord *)undoRecord;
- (GWFileUndoRecord *)redoRecord;

/** "Undo Move of "x"", or plain "Undo" when there is nothing to undo. */
- (NSString *)undoMenuTitle;
- (NSString *)redoMenuTitle;

/**
 * Reverse the newest operation.  When something it would touch changed,
 * nothing is done, the record stays, and NO is returned with *error
 * saying what changed.
 */
- (BOOL)undo:(NSError **)error;

- (BOOL)redo:(NSError **)error;

/** Forget everything (tests). */
- (void)removeAllRecords;

@end
