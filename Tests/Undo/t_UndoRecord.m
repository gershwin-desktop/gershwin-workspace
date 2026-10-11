/* t_UndoRecord.m - GWFileUndoRecord: menu names, the operations that undo
 * and redo each kind of file operation, and the refusals when something
 * changed on disk since.  Headless, no executor: the records are fed the
 * items an executor would report and the disk is set up to match.
 *
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-2.0-or-later
 */
#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import "Testing.h"
#import "GWFileUndoRecord.h"
#import "FSNAlias.h"

static NSString *root;
static NSFileManager *fm;

static NSString *P(NSString *rel)
{
  return [root stringByAppendingPathComponent: rel];
}

static void touch(NSString *rel)
{
  [fm createFileAtPath: P(rel) contents: [@"x" dataUsingEncoding: NSUTF8StringEncoding]
            attributes: nil];
}

static NSDictionary *item(NSString *from, NSString *to)
{
  if (from == nil)
    return [NSDictionary dictionaryWithObject: P(to) forKey: GWFileUndoToKey];
  return [NSDictionary dictionaryWithObjectsAndKeys: P(from), GWFileUndoFromKey,
                       P(to), GWFileUndoToKey, nil];
}

static void reset(void)
{
  [fm removeFileAtPath: root handler: nil];
  [fm createDirectoryAtPath: root attributes: nil];
  [fm createDirectoryAtPath: P(@"A") attributes: nil];
  [fm createDirectoryAtPath: P(@"B") attributes: nil];
  [fm createDirectoryAtPath: P(@"Trash") attributes: nil];
}

int main(void)
{
  NSAutoreleasePool *arp = [NSAutoreleasePool new];
  NSString *trash;
  GWFileUndoRecord *rec;
  NSArray *ops;
  NSDictionary *op;
  NSError *err;

  fm = [NSFileManager defaultManager];
  root = [[NSTemporaryDirectory() stringByAppendingPathComponent:
            [NSString stringWithFormat: @"t_UndoRecord-%d", getpid()]] retain];
  trash = P(@"Trash");

  START_SET("which operations are undoable")
    PASS([GWFileUndoRecord isUndoableOperation: NSWorkspaceMoveOperation], "move");
    PASS([GWFileUndoRecord isUndoableOperation: NSWorkspaceCopyOperation], "copy");
    PASS([GWFileUndoRecord isUndoableOperation: NSWorkspaceDuplicateOperation], "duplicate");
    PASS([GWFileUndoRecord isUndoableOperation: NSWorkspaceRecycleOperation], "move to Trash");
    PASS([GWFileUndoRecord isUndoableOperation: GWFileUndoRenameOperation], "rename");
    PASS([GWFileUndoRecord isUndoableOperation: FSNWorkspaceCreateAliasOperation], "make alias");
    PASS([GWFileUndoRecord isUndoableOperation: GWFileUndoCreateDirOperation], "new folder");
    PASS([GWFileUndoRecord isUndoableOperation: NSWorkspaceDestroyOperation] == NO,
         "deleting cannot be undone");
    PASS([GWFileUndoRecord isUndoableOperation: @"WorkspaceemptyTrashOperation"] == NO,
         "emptying the Trash cannot be undone");
    reset();
    touch(@"B/f");
    PASS([GWFileUndoRecord recordWithOperation: NSWorkspaceMoveOperation
                                         items: [NSArray array]] == nil,
         "an operation that did nothing leaves no record");
    PASS([GWFileUndoRecord recordWithOperation: NSWorkspaceDestroyOperation
                                         items: [NSArray arrayWithObject: item(@"A/f", @"B/f")]] == nil,
         "a delete leaves no record");
  END_SET("which operations are undoable")

  START_SET("menu names")
    reset();
    touch(@"B/f");
    touch(@"B/g");
    rec = [GWFileUndoRecord recordWithOperation: NSWorkspaceMoveOperation
                                          items: [NSArray arrayWithObject: item(@"A/f", @"B/f")]];
    PASS_EQUAL([rec actionName], @"Move of \"f\"", "one moved item is named");
    rec = [GWFileUndoRecord recordWithOperation: NSWorkspaceMoveOperation
                                          items: [NSArray arrayWithObjects: item(@"A/f", @"B/f"),
                                                          item(@"A/g", @"B/g"), nil]];
    PASS_EQUAL([rec actionName], @"Move of 2 Items", "several moved items are counted");
    rec = [GWFileUndoRecord recordWithOperation: NSWorkspaceCopyOperation
                                          items: [NSArray arrayWithObject: item(@"A/f", @"B/f")]];
    PASS_EQUAL([rec actionName], @"Copy of \"f\"", "copy");
    rec = [GWFileUndoRecord recordWithOperation: NSWorkspaceDuplicateOperation
                                          items: [NSArray arrayWithObject: item(@"B/x", @"B/f")]];
    PASS_EQUAL([rec actionName], @"Duplicate of \"x\"", "duplicate names the original");
    rec = [GWFileUndoRecord recordWithOperation: GWFileUndoRenameOperation
                                          items: [NSArray arrayWithObject: item(@"B/old", @"B/f")]];
    PASS_EQUAL([rec actionName], @"Rename of \"old\"", "rename names the old name");
    rec = [GWFileUndoRecord recordWithOperation: NSWorkspaceRecycleOperation
                                          items: [NSArray arrayWithObject: item(@"A/x", @"B/f")]];
    PASS_EQUAL([rec actionName], @"Move of \"x\" to Trash", "move to Trash names the original");
    rec = [GWFileUndoRecord recordWithOperation: FSNWorkspaceCreateAliasOperation
                                          items: [NSArray arrayWithObject: item(@"A/x", @"B/f")]];
    PASS_EQUAL([rec actionName], @"Make Alias of \"x\"", "make alias");
    rec = [GWFileUndoRecord recordWithOperation: GWFileUndoCreateDirOperation
                                          items: [NSArray arrayWithObject: item(nil, @"B/f")]];
    PASS_EQUAL([rec actionName], @"New Folder", "new folder");
  END_SET("menu names")

  START_SET("undo and redo of a move")
    reset();
    touch(@"B/f");
    rec = [GWFileUndoRecord recordWithOperation: NSWorkspaceMoveOperation
                                          items: [NSArray arrayWithObject: item(@"A/f", @"B/f")]];
    err = nil;
    ops = [rec undoOperationsWithTrashPath: trash error: &err];
    PASS(ops != nil && [ops count] == 1 && err == nil, "a move can be undone");
    op = [ops lastObject];
    PASS_EQUAL([op objectForKey: @"operation"], NSWorkspaceMoveOperation, "by a move");
    PASS_EQUAL([op objectForKey: @"source"], P(@"B"), "out of the folder it went to");
    PASS_EQUAL([op objectForKey: @"destination"], P(@"A"), "back into the folder it came from");
    PASS_EQUAL([op objectForKey: @"files"], [NSArray arrayWithObject: @"f"], "the item by name");
    PASS_EQUAL([op objectForKey: @"confirm"], [NSNumber numberWithBool: NO],
               "without asking again");

    /* As if undone. */
    [fm movePath: P(@"B/f") toPath: P(@"A/f") handler: nil];
    ops = [rec redoOperationsWithError: &err];
    op = [ops lastObject];
    PASS(ops != nil && [ops count] == 1, "the move can be redone");
    PASS_EQUAL([op objectForKey: @"source"], P(@"A"), "redo moves from the original folder");
    PASS_EQUAL([op objectForKey: @"destination"], P(@"B"), "to the same destination");
  END_SET("undo and redo of a move")

  START_SET("refusals for a move")
    reset();
    touch(@"B/f");
    rec = [GWFileUndoRecord recordWithOperation: NSWorkspaceMoveOperation
                                          items: [NSArray arrayWithObject: item(@"A/f", @"B/f")]];
    [fm movePath: P(@"B/f") toPath: P(@"keep") handler: nil];
    err = nil;
    PASS([rec undoOperationsWithTrashPath: trash error: &err] == nil
         && [err code] == GWFileUndoErrorItemGone, "refused when the item is gone");
    PASS([[err localizedDescription] rangeOfString: @"\"f\""].location != NSNotFound,
         "the refusal names the item");

    /* Made while the old one still exists, so it cannot reuse its inode. */
    touch(@"B/f2");
    [fm movePath: P(@"B/f2") toPath: P(@"B/f") handler: nil];
    err = nil;
    PASS([rec undoOperationsWithTrashPath: trash error: &err] == nil
         && [err code] == GWFileUndoErrorItemReplaced,
         "refused when another item took the name since");

    reset();
    touch(@"B/f");
    rec = [GWFileUndoRecord recordWithOperation: NSWorkspaceMoveOperation
                                          items: [NSArray arrayWithObject: item(@"A/f", @"B/f")]];
    touch(@"A/f");
    err = nil;
    PASS([rec undoOperationsWithTrashPath: trash error: &err] == nil
         && [err code] == GWFileUndoErrorNameTaken,
         "refused when the old name is taken");
    PASS([fm fileExistsAtPath: P(@"A/f")] && [fm fileExistsAtPath: P(@"B/f")],
         "a refusal changes nothing");

    [fm removeFileAtPath: P(@"A/f") handler: nil];
    [fm removeFileAtPath: P(@"A") handler: nil];
    err = nil;
    PASS([rec undoOperationsWithTrashPath: trash error: &err] == nil
         && [err code] == GWFileUndoErrorItemGone
         && [[[err userInfo] objectForKey: NSFilePathErrorKey] isEqual: P(@"A")],
         "refused when the folder it came from is gone");

    reset();
    touch(@"B/f");
    rec = [GWFileUndoRecord recordWithOperation: NSWorkspaceMoveOperation
                                          items: [NSArray arrayWithObject: item(@"A/f", @"B/f")]];
    [fm movePath: P(@"B/f") toPath: P(@"A/f") handler: nil];
    touch(@"B/f");
    err = nil;
    PASS([rec redoOperationsWithError: &err] == nil
         && [err code] == GWFileUndoErrorNameTaken,
         "redo refused when the destination name is taken");
    [fm removeFileAtPath: P(@"A/f") handler: nil];
    [fm removeFileAtPath: P(@"B/f") handler: nil];
    err = nil;
    PASS([rec redoOperationsWithError: &err] == nil
         && [err code] == GWFileUndoErrorItemGone,
         "redo refused when the original is gone");

    reset();
    [fm createSymbolicLinkAtPath: P(@"B/f") pathContent: P(@"nowhere")];
    rec = [GWFileUndoRecord recordWithOperation: NSWorkspaceMoveOperation
                                          items: [NSArray arrayWithObject: item(@"A/f", @"B/f")]];
    PASS(rec != nil, "a dangling symbolic link is an item too");
    [fm createSymbolicLinkAtPath: P(@"A/f") pathContent: P(@"nowhere")];
    err = nil;
    PASS([rec undoOperationsWithTrashPath: trash error: &err] == nil
         && [err code] == GWFileUndoErrorNameTaken,
         "a dangling symbolic link takes the name");
  END_SET("refusals for a move")

  START_SET("creations are undone into the Trash")
    reset();
    touch(@"B/f");
    touch(@"B/g");
    rec = [GWFileUndoRecord recordWithOperation: NSWorkspaceCopyOperation
                                          items: [NSArray arrayWithObjects: item(@"A/f", @"B/f"),
                                                          item(@"A/g", @"B/g"), nil]];
    ops = [rec undoOperationsWithTrashPath: trash error: &err];
    op = [ops lastObject];
    PASS([ops count] == 1, "one operation");
    PASS_EQUAL([op objectForKey: @"operation"], NSWorkspaceRecycleOperation, "moves to the Trash");
    PASS_EQUAL([op objectForKey: @"source"], P(@"B"), "the copies");
    PASS_EQUAL([op objectForKey: @"destination"], trash, "into the Trash");
    {
      NSArray *want = [NSArray arrayWithObjects: @"f", @"g", nil];
      PASS_EQUAL([op objectForKey: @"files"], want, "every copy");
    }
    [fm removeFileAtPath: P(@"B/g") handler: nil];
    err = nil;
    PASS([rec undoOperationsWithTrashPath: trash error: &err] == nil
         && [err code] == GWFileUndoErrorItemGone,
         "refused when one copy is gone");

    reset();
    touch(@"B/x_copy");
    rec = [GWFileUndoRecord recordWithOperation: NSWorkspaceDuplicateOperation
                                          items: [NSArray arrayWithObject: item(@"B/x", @"B/x_copy")]];
    ops = [rec undoOperationsWithTrashPath: trash error: &err];
    PASS_EQUAL([[ops lastObject] objectForKey: @"files"], [NSArray arrayWithObject: @"x_copy"],
               "a duplicate is trashed by its new name");
    touch(@"B/x");
    ops = [rec redoOperationsWithError: &err];
    op = [ops lastObject];
    PASS_EQUAL([op objectForKey: @"operation"], NSWorkspaceDuplicateOperation, "redo duplicates again");
    PASS([[op objectForKey: @"source"] isEqual: P(@"B")]
         && [[op objectForKey: @"destination"] isEqual: P(@"B")], "in the same folder");
    PASS_EQUAL([op objectForKey: @"files"], [NSArray arrayWithObject: @"x"], "the original");

    reset();
    [fm createDirectoryAtPath: P(@"B/New Folder") attributes: nil];
    rec = [GWFileUndoRecord recordWithOperation: GWFileUndoCreateDirOperation
                                          items: [NSArray arrayWithObject: item(nil, @"B/New Folder")]];
    ops = [rec undoOperationsWithTrashPath: trash error: &err];
    PASS_EQUAL([[ops lastObject] objectForKey: @"operation"], NSWorkspaceRecycleOperation,
               "a new folder is undone into the Trash");
    [fm movePath: P(@"B/New Folder") toPath: P(@"Trash/New Folder") handler: nil];
    ops = [rec redoOperationsWithError: &err];
    op = [ops lastObject];
    PASS_EQUAL([op objectForKey: @"operation"], GWFileUndoCreateDirOperation, "redo creates it again");
    PASS_EQUAL([op objectForKey: @"files"], [NSArray arrayWithObject: @"New Folder"], "by its name");
    touch(@"B/New Folder");
    err = nil;
    PASS([rec redoOperationsWithError: &err] == nil && [err code] == GWFileUndoErrorNameTaken,
         "redo refused when the name is taken");
  END_SET("creations are undone into the Trash")

  START_SET("rename")
    reset();
    touch(@"B/new");
    rec = [GWFileUndoRecord recordWithOperation: GWFileUndoRenameOperation
                                          items: [NSArray arrayWithObject: item(@"B/old", @"B/new")]];
    ops = [rec undoOperationsWithTrashPath: trash error: &err];
    op = [ops lastObject];
    PASS_EQUAL([op objectForKey: @"operation"], GWFileUndoRenameOperation, "undone by a rename");
    PASS([[op objectForKey: @"source"] isEqual: P(@"B/new")]
         && [[op objectForKey: @"destination"] isEqual: P(@"B/old")], "back to the old name");
    touch(@"B/old");
    err = nil;
    PASS([rec undoOperationsWithTrashPath: trash error: &err] == nil
         && [err code] == GWFileUndoErrorNameTaken, "refused when the old name was taken");
  END_SET("rename")

  START_SET("put back from the Trash")
    reset();
    touch(@"Trash/f");
    touch(@"Trash/g_copy");
    rec = [GWFileUndoRecord recordWithOperation: NSWorkspaceRecycleOperation
                                          items: [NSArray arrayWithObjects: item(@"A/f", @"Trash/f"),
                                                          item(@"A/g", @"Trash/g_copy"), nil]];
    ops = [rec undoOperationsWithTrashPath: trash error: &err];
    PASS([ops count] == 2, "two operations when the Trash renamed one item");
    op = [ops objectAtIndex: 0];
    PASS_EQUAL([op objectForKey: @"operation"], GWFileUndoRecycleOutOperation,
               "items that kept their name go back out of the Trash");
    PASS([[op objectForKey: @"source"] isEqual: trash]
         && [[op objectForKey: @"destination"] isEqual: P(@"A")], "to where they were");
    PASS_EQUAL([op objectForKey: @"files"], [NSArray arrayWithObject: @"f"], "by name");
    op = [ops objectAtIndex: 1];
    PASS_EQUAL([op objectForKey: @"operation"], GWFileUndoRenameOperation,
               "a renamed item gets its old name back");
    PASS([[op objectForKey: @"source"] isEqual: P(@"Trash/g_copy")]
         && [[op objectForKey: @"destination"] isEqual: P(@"A/g")], "in its old folder");

    touch(@"A/g");
    err = nil;
    PASS([rec undoOperationsWithTrashPath: trash error: &err] == nil
         && [err code] == GWFileUndoErrorNameTaken,
         "put back refused when the original name is taken");

    [fm removeFileAtPath: P(@"A/g") handler: nil];
    [fm movePath: P(@"Trash/f") toPath: P(@"A/f") handler: nil];
    [fm movePath: P(@"Trash/g_copy") toPath: P(@"A/g") handler: nil];
    ops = [rec redoOperationsWithError: &err];
    op = [ops lastObject];
    PASS_EQUAL([op objectForKey: @"operation"], NSWorkspaceRecycleOperation, "redo trashes again");
    PASS([[op objectForKey: @"source"] isEqual: P(@"A")]
         && [[op objectForKey: @"destination"] isEqual: trash], "from the original folder");
    {
      NSArray *want = [NSArray arrayWithObjects: @"f", @"g", nil];
      PASS_EQUAL([op objectForKey: @"files"], want, "by the original names");
    }
  END_SET("put back from the Trash")

  [fm removeFileAtPath: root handler: nil];
  [arp release];
  return 0;
}
