/* GWFileUndoRecord.m
 *
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-2.0-or-later
 */

#import <AppKit/AppKit.h>

#import "GWFileUndoRecord.h"
#import "FSNAlias.h"

NSString * const GWFileUndoFromKey = @"from";
NSString * const GWFileUndoToKey = @"to";
NSString * const GWFileUndoErrorDomain = @"GWFileUndoErrorDomain";
NSString * const GWFileUndoCreateDirOperation = @"WorkspaceCreateDirOperation";
NSString * const GWFileUndoRenameOperation = @"WorkspaceRenameOperation";
NSString * const GWFileUndoRecycleOutOperation = @"WorkspaceRecycleOutOperation";

/* Device and inode: a path still holding "the same item" means it holds
 * this pair, which survives renames and moves within a filesystem but not
 * a delete-and-recreate under the same name. */
static NSDictionary *identityAtPath(NSString *path)
{
  NSDictionary *attrs = [[NSFileManager defaultManager]
                          attributesOfItemAtPath: path error: NULL];
  id dev = [attrs objectForKey: NSFileSystemNumber];
  id ino = [attrs objectForKey: NSFileSystemFileNumber];

  if (attrs == nil || dev == nil || ino == nil)
    return nil;
  return [NSDictionary dictionaryWithObjectsAndKeys: dev, @"dev", ino, @"ino", nil];
}

/* lstat semantics: a dangling symbolic link still takes the name. */
static BOOL itemExistsAtPath(NSString *path)
{
  return [[NSFileManager defaultManager] attributesOfItemAtPath: path
                                                          error: NULL] != nil;
}

static NSError *undoError(NSInteger code, NSString *path)
{
  NSString *name = [path lastPathComponent];
  NSString *dir = [[path stringByDeletingLastPathComponent] lastPathComponent];
  NSString *msg;

  switch (code)
    {
    case GWFileUndoErrorNameTaken:
      msg = [NSString stringWithFormat:
        NSLocalizedString(@"An item named \"%@\" already exists in \"%@\".", @""),
        name, dir];
      break;
    case GWFileUndoErrorItemReplaced:
      msg = [NSString stringWithFormat:
        NSLocalizedString(@"\"%@\" in \"%@\" has been replaced by another item.", @""),
        name, dir];
      break;
    default:
      msg = [NSString stringWithFormat:
        NSLocalizedString(@"\"%@\" can no longer be found in \"%@\".", @""),
        name, dir];
      break;
    }

  return [NSError errorWithDomain: GWFileUndoErrorDomain
                             code: code
                         userInfo: [NSDictionary dictionaryWithObjectsAndKeys:
                                      msg, NSLocalizedDescriptionKey,
                                      path, NSFilePathErrorKey, nil]];
}

static NSDictionary *operationDict(NSString *type, NSString *source,
                                   NSString *destination, NSArray *files)
{
  /* The user asked for this by choosing Undo or Redo; asking again whether
   * to move these items would be noise. */
  return [NSDictionary dictionaryWithObjectsAndKeys:
                         type, @"operation",
                         source, @"source",
                         destination, @"destination",
                         files, @"files",
                         [NSNumber numberWithBool: NO], @"confirm", nil];
}

@implementation GWFileUndoRecord

+ (BOOL)isUndoableOperation:(NSString *)type
{
  return [type isEqual: NSWorkspaceMoveOperation]
    || [type isEqual: GWFileUndoRecycleOutOperation]
    || [type isEqual: NSWorkspaceCopyOperation]
    || [type isEqual: NSWorkspaceDuplicateOperation]
    || [type isEqual: GWFileUndoRenameOperation]
    || [type isEqual: NSWorkspaceRecycleOperation]
    || [type isEqual: FSNWorkspaceCreateAliasOperation]
    || [type isEqual: GWFileUndoCreateDirOperation];
}

+ (instancetype)recordWithOperation:(NSString *)type
                              items:(NSArray *)doneItems
{
  NSMutableArray *ids;
  NSUInteger i;
  GWFileUndoRecord *rec;

  if ([self isUndoableOperation: type] == NO || [doneItems count] == 0)
    return nil;

  ids = [NSMutableArray arrayWithCapacity: [doneItems count]];
  for (i = 0; i < [doneItems count]; i++)
    {
      NSString *to = [[doneItems objectAtIndex: i] objectForKey: GWFileUndoToKey];
      NSDictionary *ident = identityAtPath(to);

      /* An item gone already when the operation reports it done would make
       * any later undo act on a guess. */
      if (ident == nil)
        return nil;
      [ids addObject: ident];
    }

  rec = [[self alloc] init];
  rec->operation = [type copy];
  rec->items = [doneItems copy];
  rec->identities = [ids copy];
  return [rec autorelease];
}

- (void)dealloc
{
  [operation release];
  [items release];
  [identities release];
  [super dealloc];
}

- (NSString *)operation
{
  return operation;
}

- (NSArray *)items
{
  return items;
}

- (NSString *)fromAtIndex:(NSUInteger)i
{
  return [[items objectAtIndex: i] objectForKey: GWFileUndoFromKey];
}

- (NSString *)toAtIndex:(NSUInteger)i
{
  return [[items objectAtIndex: i] objectForKey: GWFileUndoToKey];
}

- (NSArray *)namesForKey:(NSString *)key
{
  NSMutableArray *names = [NSMutableArray arrayWithCapacity: [items count]];
  NSUInteger i;

  for (i = 0; i < [items count]; i++)
    [names addObject: [[[items objectAtIndex: i] objectForKey: key] lastPathComponent]];
  return names;
}

- (NSString *)directoryForKey:(NSString *)key
{
  return [[[items objectAtIndex: 0] objectForKey: key] stringByDeletingLastPathComponent];
}

- (BOOL)isCreation
{
  return [operation isEqual: NSWorkspaceCopyOperation]
    || [operation isEqual: NSWorkspaceDuplicateOperation]
    || [operation isEqual: FSNWorkspaceCreateAliasOperation]
    || [operation isEqual: GWFileUndoCreateDirOperation];
}

- (NSString *)actionName
{
  NSUInteger n = [items count];
  NSString *name;

  if ([operation isEqual: GWFileUndoCreateDirOperation])
    return NSLocalizedString(@"New Folder", @"");

  name = [[self fromAtIndex: 0] lastPathComponent];

  if ([operation isEqual: NSWorkspaceMoveOperation]
      || [operation isEqual: GWFileUndoRecycleOutOperation])
    return (n == 1)
      ? [NSString stringWithFormat: NSLocalizedString(@"Move of \"%@\"", @""), name]
      : [NSString stringWithFormat: NSLocalizedString(@"Move of %lu Items", @""), (unsigned long)n];
  if ([operation isEqual: NSWorkspaceCopyOperation])
    return (n == 1)
      ? [NSString stringWithFormat: NSLocalizedString(@"Copy of \"%@\"", @""), name]
      : [NSString stringWithFormat: NSLocalizedString(@"Copy of %lu Items", @""), (unsigned long)n];
  if ([operation isEqual: NSWorkspaceDuplicateOperation])
    return (n == 1)
      ? [NSString stringWithFormat: NSLocalizedString(@"Duplicate of \"%@\"", @""), name]
      : [NSString stringWithFormat: NSLocalizedString(@"Duplicate of %lu Items", @""), (unsigned long)n];
  if ([operation isEqual: NSWorkspaceRecycleOperation])
    return (n == 1)
      ? [NSString stringWithFormat: NSLocalizedString(@"Move of \"%@\" to Trash", @""), name]
      : [NSString stringWithFormat: NSLocalizedString(@"Move of %lu Items to Trash", @""), (unsigned long)n];
  if ([operation isEqual: FSNWorkspaceCreateAliasOperation])
    return (n == 1)
      ? [NSString stringWithFormat: NSLocalizedString(@"Make Alias of \"%@\"", @""), name]
      : [NSString stringWithFormat: NSLocalizedString(@"Make Alias of %lu Items", @""), (unsigned long)n];
  /* Rename always concerns one item. */
  return [NSString stringWithFormat: NSLocalizedString(@"Rename of \"%@\"", @""), name];
}

/* Each result must still be the very item the operation produced. */
- (BOOL)checkResultsUnchanged:(NSError **)error
{
  NSUInteger i;

  for (i = 0; i < [items count]; i++)
    {
      NSString *to = [self toAtIndex: i];
      NSDictionary *now = identityAtPath(to);

      if (now == nil)
        {
          if (error) *error = undoError(GWFileUndoErrorItemGone, to);
          return NO;
        }
      if ([now isEqual: [identities objectAtIndex: i]] == NO)
        {
          if (error) *error = undoError(GWFileUndoErrorItemReplaced, to);
          return NO;
        }
    }
  return YES;
}

- (BOOL)checkPathsExist:(NSString *)key error:(NSError **)error
{
  NSUInteger i;

  for (i = 0; i < [items count]; i++)
    {
      NSString *path = [[items objectAtIndex: i] objectForKey: key];

      if (itemExistsAtPath(path) == NO)
        {
          if (error) *error = undoError(GWFileUndoErrorItemGone, path);
          return NO;
        }
    }
  return YES;
}

/* The folder an item goes into must still be there, and the name free. */
- (BOOL)checkPathsFree:(NSString *)key error:(NSError **)error
{
  NSUInteger i;

  for (i = 0; i < [items count]; i++)
    {
      NSString *path = [[items objectAtIndex: i] objectForKey: key];
      NSString *dir = [path stringByDeletingLastPathComponent];
      BOOL isDir = NO;

      if ([[NSFileManager defaultManager] fileExistsAtPath: dir
                                               isDirectory: &isDir] == NO
          || isDir == NO)
        {
          if (error) *error = undoError(GWFileUndoErrorItemGone, dir);
          return NO;
        }
      if (itemExistsAtPath(path))
        {
          if (error) *error = undoError(GWFileUndoErrorNameTaken, path);
          return NO;
        }
    }
  return YES;
}

/* Put back from the Trash: items that kept their name go back in one
 * batch; one that the Trash had to rename (a same-named item was already
 * there) gets its old name back with a rename across folders. */
- (NSArray *)putBackOperations
{
  NSMutableArray *ops = [NSMutableArray array];
  NSMutableArray *sameNames = [NSMutableArray array];
  NSUInteger i;

  for (i = 0; i < [items count]; i++)
    {
      NSString *from = [self fromAtIndex: i];
      NSString *to = [self toAtIndex: i];

      if ([[from lastPathComponent] isEqual: [to lastPathComponent]])
        [sameNames addObject: [to lastPathComponent]];
      else
        [ops addObject: operationDict(GWFileUndoRenameOperation, to, from,
                                      [NSArray arrayWithObject: @""])];
    }
  if ([sameNames count])
    [ops insertObject: operationDict(GWFileUndoRecycleOutOperation,
                                     [self directoryForKey: GWFileUndoToKey],
                                     [self directoryForKey: GWFileUndoFromKey],
                                     sameNames)
              atIndex: 0];
  return ops;
}

- (NSArray *)undoOperationsWithTrashPath:(NSString *)trashPath
                                   error:(NSError **)error
{
  if ([self checkResultsUnchanged: error] == NO)
    return nil;

  if ([self isCreation])
    {
      return [NSArray arrayWithObject:
                operationDict(NSWorkspaceRecycleOperation,
                              [self directoryForKey: GWFileUndoToKey],
                              trashPath,
                              [self namesForKey: GWFileUndoToKey])];
    }

  if ([self checkPathsFree: GWFileUndoFromKey error: error] == NO)
    return nil;

  if ([operation isEqual: GWFileUndoRenameOperation])
    return [NSArray arrayWithObject:
              operationDict(GWFileUndoRenameOperation,
                            [self toAtIndex: 0], [self fromAtIndex: 0],
                            [NSArray arrayWithObject: @""])];

  if ([operation isEqual: NSWorkspaceRecycleOperation])
    return [self putBackOperations];

  /* Move, including a move out of the Trash. */
  return [NSArray arrayWithObject:
            operationDict(NSWorkspaceMoveOperation,
                          [self directoryForKey: GWFileUndoToKey],
                          [self directoryForKey: GWFileUndoFromKey],
                          [self namesForKey: GWFileUndoToKey])];
}

- (NSArray *)redoOperationsWithError:(NSError **)error
{
  NSString *srcDir;
  NSString *dstDir;
  NSDictionary *op;

  if ([operation isEqual: GWFileUndoCreateDirOperation])
    {
      if ([self checkPathsFree: GWFileUndoToKey error: error] == NO)
        return nil;
      dstDir = [self directoryForKey: GWFileUndoToKey];
      return [NSArray arrayWithObject:
                operationDict(operation, dstDir, dstDir,
                              [self namesForKey: GWFileUndoToKey])];
    }

  if ([self checkPathsExist: GWFileUndoFromKey error: error] == NO)
    return nil;

  /* A duplicate, an alias and the Trash pick a free name themselves. */
  if ([operation isEqual: NSWorkspaceMoveOperation]
      || [operation isEqual: GWFileUndoRecycleOutOperation]
      || [operation isEqual: NSWorkspaceCopyOperation]
      || [operation isEqual: GWFileUndoRenameOperation])
    {
      if ([self checkPathsFree: GWFileUndoToKey error: error] == NO)
        return nil;
    }

  if ([operation isEqual: GWFileUndoRenameOperation])
    return [NSArray arrayWithObject:
              operationDict(operation, [self fromAtIndex: 0], [self toAtIndex: 0],
                            [NSArray arrayWithObject: @""])];

  srcDir = [self directoryForKey: GWFileUndoFromKey];
  dstDir = [self directoryForKey: GWFileUndoToKey];
  op = operationDict(operation, srcDir, dstDir,
                     [self namesForKey: GWFileUndoFromKey]);
  return [NSArray arrayWithObject: op];
}

@end
