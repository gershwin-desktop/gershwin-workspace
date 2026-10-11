/* GWFileUndoStack.m
 *
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-2.0-or-later
 */

#import "GWFileUndoStack.h"
#import "GWFileUndoRecord.h"

NSString * const GWFileUndoRoleKey = @"GWFileUndoRole";
NSString * const GWFileUndoRoleUndo = @"undo";
NSString * const GWFileUndoRoleRedo = @"redo";

/* Finder keeps one level; more costs next to nothing and every level is
 * checked against the disk before it is used. */
#define DEFAULT_LEVELS 20

@implementation GWFileUndoStack

+ (GWFileUndoStack *)sharedStack
{
  static GWFileUndoStack *shared = nil;

  if (shared == nil)
    shared = [[self alloc] init];
  return shared;
}

- (id)init
{
  self = [super init];
  if (self)
    {
      undoRecords = [NSMutableArray new];
      redoRecords = [NSMutableArray new];
      trashPath = [[NSHomeDirectory() stringByAppendingPathComponent: @".Trash"] retain];
      levels = DEFAULT_LEVELS;
    }
  return self;
}

- (void)dealloc
{
  [undoRecords release];
  [redoRecords release];
  [trashPath release];
  [super dealloc];
}

- (void)setPerformer:(id <GWFileUndoPerformer>)anObject
{
  performer = anObject;
}

- (void)setTrashPath:(NSString *)path
{
  ASSIGN (trashPath, path);
}

- (NSString *)trashPath
{
  return trashPath;
}

- (void)setLevelsOfUndo:(NSUInteger)n
{
  levels = (n > 0) ? n : 1;
  while ([undoRecords count] > levels)
    [undoRecords removeObjectAtIndex: 0];
}

- (void)pushUndoRecord:(GWFileUndoRecord *)rec
{
  [undoRecords addObject: rec];
  while ([undoRecords count] > levels)
    [undoRecords removeObjectAtIndex: 0];
}

- (void)fileOperation:(NSString *)type
   didFinishWithItems:(NSArray *)doneItems
                 role:(NSString *)role
{
  GWFileUndoRecord *rec;

  /* What undo did is the reverse of a record already on the redo stack. */
  if ([role isEqual: GWFileUndoRoleUndo])
    return;

  rec = [GWFileUndoRecord recordWithOperation: type items: doneItems];
  if (rec == nil)
    return;

  [self pushUndoRecord: rec];
  /* A new action makes what was undone before it unreachable, as in every
   * editor; repeating an undone action keeps the rest of the redo list. */
  if ([role isEqual: GWFileUndoRoleRedo] == NO)
    [redoRecords removeAllObjects];
}

- (BOOL)canUndo
{
  return [undoRecords count] > 0;
}

- (BOOL)canRedo
{
  return [redoRecords count] > 0;
}

- (GWFileUndoRecord *)undoRecord
{
  return [undoRecords lastObject];
}

- (GWFileUndoRecord *)redoRecord
{
  return [redoRecords lastObject];
}

- (NSString *)undoMenuTitle
{
  if ([self canUndo] == NO)
    return NSLocalizedString(@"Undo", @"");
  return [NSString stringWithFormat: NSLocalizedString(@"Undo %@", @""),
                   [[self undoRecord] actionName]];
}

- (NSString *)redoMenuTitle
{
  if ([self canRedo] == NO)
    return NSLocalizedString(@"Redo", @"");
  return [NSString stringWithFormat: NSLocalizedString(@"Redo %@", @""),
                   [[self redoRecord] actionName]];
}

- (void)performOperations:(NSArray *)ops role:(NSString *)role
{
  NSUInteger i;

  for (i = 0; i < [ops count]; i++)
    {
      NSMutableDictionary *op = [[ops objectAtIndex: i] mutableCopy];

      [op setObject: role forKey: GWFileUndoRoleKey];
      [performer performOperation: op];
      [op release];
    }
}

- (BOOL)undo:(NSError **)error
{
  GWFileUndoRecord *rec = [self undoRecord];
  NSArray *ops;

  if (rec == nil)
    return NO;
  ops = [rec undoOperationsWithTrashPath: trashPath error: error];
  if (ops == nil)
    return NO;

  [rec retain];
  [undoRecords removeLastObject];
  [redoRecords addObject: rec];
  [rec release];
  [self performOperations: ops role: GWFileUndoRoleUndo];
  return YES;
}

- (BOOL)redo:(NSError **)error
{
  GWFileUndoRecord *rec = [self redoRecord];
  NSArray *ops;

  if (rec == nil)
    return NO;
  ops = [rec redoOperationsWithError: error];
  if (ops == nil)
    return NO;

  /* The operation pushes a fresh record when it finishes: its results
   * have new identities (and a duplicate may get a new name). */
  [redoRecords removeLastObject];
  [self performOperations: ops role: GWFileUndoRoleRedo];
  return YES;
}

- (void)removeAllRecords
{
  [undoRecords removeAllObjects];
  [redoRecords removeAllObjects];
}

@end
