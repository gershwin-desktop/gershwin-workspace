/* t_UndoStack.m - GWFileUndoStack: what a finished operation does to the
 * history depending on whether the user, undo or redo started it, the menu
 * titles, the level limit, and that a refused undo leaves everything as it
 * was.  The performer only collects the operations it is handed.
 *
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-2.0-or-later
 */
#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import "Testing.h"
#import "GWFileUndoRecord.h"
#import "GWFileUndoStack.h"

@interface Collector : NSObject <GWFileUndoPerformer>
{
@public
  NSMutableArray *ops;
}
@end

@implementation Collector
- (id)init
{
  self = [super init];
  ops = [NSMutableArray new];
  return self;
}
- (void)dealloc
{
  [ops release];
  [super dealloc];
}
- (void)performOperation:(NSDictionary *)opdict
{
  [ops addObject: opdict];
}
@end

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

static NSArray *moved(NSString *name)
{
  return [NSArray arrayWithObject:
    [NSDictionary dictionaryWithObjectsAndKeys:
       P([@"A" stringByAppendingPathComponent: name]), GWFileUndoFromKey,
       P([@"B" stringByAppendingPathComponent: name]), GWFileUndoToKey, nil]];
}

int main(void)
{
  NSAutoreleasePool *arp = [NSAutoreleasePool new];
  GWFileUndoStack *stack;
  Collector *perf;
  NSError *err;
  NSDictionary *op;

  fm = [NSFileManager defaultManager];
  root = [[NSTemporaryDirectory() stringByAppendingPathComponent:
            [NSString stringWithFormat: @"t_UndoStack-%d", getpid()]] retain];
  [fm removeFileAtPath: root handler: nil];
  [fm createDirectoryAtPath: root attributes: nil];
  [fm createDirectoryAtPath: P(@"A") attributes: nil];
  [fm createDirectoryAtPath: P(@"B") attributes: nil];
  [fm createDirectoryAtPath: P(@"Trash") attributes: nil];
  touch(@"B/f");
  touch(@"B/g");

  stack = [[GWFileUndoStack alloc] init];
  perf = [[Collector alloc] init];
  [stack setPerformer: perf];
  [stack setTrashPath: P(@"Trash")];

  START_SET("empty history")
    PASS([stack canUndo] == NO && [stack canRedo] == NO, "nothing to undo or redo");
    PASS_EQUAL([stack undoMenuTitle], @"Undo", "plain Undo title");
    PASS_EQUAL([stack redoMenuTitle], @"Redo", "plain Redo title");
    PASS([stack undo: NULL] == NO && [perf->ops count] == 0, "undo does nothing");
  END_SET("empty history")

  START_SET("user actions")
    [stack fileOperation: NSWorkspaceMoveOperation didFinishWithItems: moved(@"f") role: nil];
    PASS([stack canUndo], "a finished move can be undone");
    PASS_EQUAL([stack undoMenuTitle], @"Undo Move of \"f\"", "the menu names the action");
    [stack fileOperation: NSWorkspaceDestroyOperation didFinishWithItems: moved(@"g") role: nil];
    PASS_EQUAL([stack undoMenuTitle], @"Undo Move of \"f\"",
               "a delete does not replace what can be undone");
    [stack fileOperation: NSWorkspaceMoveOperation didFinishWithItems: moved(@"g") role: nil];
    PASS_EQUAL([stack undoMenuTitle], @"Undo Move of \"g\"", "the newest action comes first");
  END_SET("user actions")

  START_SET("undo")
    err = nil;
    PASS([stack undo: &err] && err == nil, "undo starts");
    PASS([perf->ops count] == 1, "one operation handed to the performer");
    op = [perf->ops lastObject];
    PASS_EQUAL([op objectForKey: GWFileUndoRoleKey], GWFileUndoRoleUndo,
               "marked as started by undo");
    PASS_EQUAL([op objectForKey: @"files"], [NSArray arrayWithObject: @"g"], "the newest move");
    PASS_EQUAL([stack undoMenuTitle], @"Undo Move of \"f\"", "the older action is next");
    PASS_EQUAL([stack redoMenuTitle], @"Redo Move of \"g\"", "the undone action can be redone");

    /* The undo operation itself finishes: not a new action. */
    [fm movePath: P(@"B/g") toPath: P(@"A/g") handler: nil];
    [stack fileOperation: NSWorkspaceMoveOperation
      didFinishWithItems: [NSArray arrayWithObject:
                             [NSDictionary dictionaryWithObjectsAndKeys:
                                P(@"B/g"), GWFileUndoFromKey, P(@"A/g"), GWFileUndoToKey, nil]]
                    role: GWFileUndoRoleUndo];
    PASS_EQUAL([stack undoMenuTitle], @"Undo Move of \"f\"",
               "what undo did is not recorded as an action");
    PASS([stack canRedo], "and does not clear redo");
  END_SET("undo")

  START_SET("redo")
    err = nil;
    PASS([stack redo: &err], "redo starts");
    op = [perf->ops lastObject];
    PASS_EQUAL([op objectForKey: GWFileUndoRoleKey], GWFileUndoRoleRedo, "marked as started by redo");
    PASS_EQUAL([op objectForKey: @"operation"], NSWorkspaceMoveOperation, "the move again");
    PASS([stack canRedo] == NO, "nothing left to redo");
    [fm movePath: P(@"A/g") toPath: P(@"B/g") handler: nil];
    [stack fileOperation: NSWorkspaceMoveOperation didFinishWithItems: moved(@"g")
                    role: GWFileUndoRoleRedo];
    PASS_EQUAL([stack undoMenuTitle], @"Undo Move of \"g\"", "the redone move can be undone again");
  END_SET("redo")

  START_SET("a new action clears redo, a redo does not")
    [stack undo: NULL];
    [fm movePath: P(@"B/g") toPath: P(@"A/g") handler: nil];
    [stack undo: NULL];
    [fm movePath: P(@"B/f") toPath: P(@"A/f") handler: nil];
    PASS_EQUAL([stack redoMenuTitle], @"Redo Move of \"f\"", "two undone moves");
    [stack redo: NULL];
    [fm movePath: P(@"A/f") toPath: P(@"B/f") handler: nil];
    [stack fileOperation: NSWorkspaceMoveOperation didFinishWithItems: moved(@"f")
                    role: GWFileUndoRoleRedo];
    PASS_EQUAL([stack redoMenuTitle], @"Redo Move of \"g\"", "a redo keeps the rest of redo");
    [fm movePath: P(@"B/f") toPath: P(@"A/f") handler: nil];
    touch(@"B/h");
    [stack fileOperation: NSWorkspaceCopyOperation
      didFinishWithItems: [NSArray arrayWithObject:
                             [NSDictionary dictionaryWithObjectsAndKeys:
                                P(@"A/h"), GWFileUndoFromKey, P(@"B/h"), GWFileUndoToKey, nil]]
                    role: nil];
    PASS([stack canRedo] == NO, "a new action clears redo");
    PASS_EQUAL([stack undoMenuTitle], @"Undo Copy of \"h\"", "and is next to undo");
  END_SET("a new action clears redo, a redo does not")

  START_SET("refusal")
    NSUInteger before = [perf->ops count];
    NSString *title = [stack undoMenuTitle];

    [fm removeFileAtPath: P(@"B/h") handler: nil];
    err = nil;
    PASS([stack undo: &err] == NO && err != nil, "undo refused when the copy is gone");
    PASS([perf->ops count] == before, "nothing handed to the performer");
    PASS_EQUAL([stack undoMenuTitle], title, "the record stays for a later try");
    PASS([stack canRedo] == NO, "nothing moved to redo");
  END_SET("refusal")

  START_SET("levels")
    NSUInteger i;

    [stack removeAllRecords];
    [stack setLevelsOfUndo: 2];
    touch(@"B/1");
    touch(@"B/2");
    touch(@"B/3");
    for (i = 1; i <= 3; i++)
      [stack fileOperation: NSWorkspaceMoveOperation
        didFinishWithItems: moved([NSString stringWithFormat: @"%lu", (unsigned long)i])
                      role: nil];
    PASS([stack undo: NULL] && [stack undo: NULL] && [stack canUndo] == NO,
         "only the newest two are kept");
  END_SET("levels")

  [stack release];
  [perf release];
  [fm removeFileAtPath: root handler: nil];
  [arp release];
  return 0;
}
