/* t_UndoOperations.m - undo and redo end to end: each operation runs
 * through the real Operation controller and FileOpInfo executor (thread
 * and Distributed Objects as in Workspace), reports to the shared undo
 * history, and Undo and Redo put the files - extended attributes and "._"
 * sidecar included - back where they were.  Headless: no progress window,
 * no confirmation panels; Operation asks for the screen, so the tool needs
 * a DISPLAY (a private Xvfb, never the desktop).
 *
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-2.0-or-later
 */
#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import "Testing.h"
#import "Operation.h"
#import "GWFileUndoRecord.h"
#import "GWFileUndoStack.h"
#import "FSNAlias.h"
#import "GWMetaXattr.h"

static NSString * const kAttrName = @"user.gw.undo-test";
static NSString *root;
static NSFileManager *fm;
static Operation *controller;
/* Where the filesystem has no extended attributes only the sidecar is
 * checked. */
static BOOL haveXattr;

static NSString *P(NSString *rel)
{
  return [root stringByAppendingPathComponent: rel];
}

static void touch(NSString *rel)
{
  [fm createFileAtPath: P(rel) contents: [rel dataUsingEncoding: NSUTF8StringEncoding]
            attributes: nil];
}

static BOOL exists(NSString *rel)
{
  return [fm attributesOfItemAtPath: P(rel) error: NULL] != nil;
}

/* Finder metadata both ways it can travel: an extended attribute on the
 * item and an AppleDouble sidecar next to it. */
static void addMetadata(NSString *rel)
{
  const char *v = "tagged";
  NSString *dir = [rel stringByDeletingLastPathComponent];
  NSString *side = [dir stringByAppendingPathComponent:
                      [@"._" stringByAppendingString: [rel lastPathComponent]]];

  if (haveXattr)
    gs_setxattr([P(rel) fileSystemRepresentation], [kAttrName UTF8String], v, strlen(v), 0);
  [fm createFileAtPath: P(side) contents: [@"sidecar" dataUsingEncoding: NSUTF8StringEncoding]
            attributes: nil];
}

static BOOL hasMetadata(NSString *rel)
{
  char buf[32];
  NSString *dir = [rel stringByDeletingLastPathComponent];
  NSString *side = [dir stringByAppendingPathComponent:
                      [@"._" stringByAppendingString: [rel lastPathComponent]]];
  ssize_t n;

  if (exists(side) == NO)
    return NO;
  if (haveXattr == NO)
    return YES;
  n = gs_getxattr([P(rel) fileSystemRepresentation], [kAttrName UTF8String],
                  buf, sizeof(buf));
  return n == 6 && memcmp(buf, "tagged", 6) == 0;
}

static BOOL waitForOperations(void)
{
  NSDate *limit = [NSDate dateWithTimeIntervalSinceNow: 30];

  /* The executor talks to FileOpInfo over Distributed Objects, served by
   * this run loop. */
  do
    {
      [[NSRunLoop currentRunLoop] runMode: NSDefaultRunLoopMode
                               beforeDate: [NSDate dateWithTimeIntervalSinceNow: 0.05]];
    }
  while ([controller operationsPending] && [limit timeIntervalSinceNow] > 0);
  return [controller operationsPending] == NO;
}

static BOOL perform(NSString *type, NSString *src, NSString *dst, NSArray *files)
{
  NSDictionary *op = [NSDictionary dictionaryWithObjectsAndKeys:
                        type, @"operation", src, @"source", dst, @"destination",
                        files, @"files", [NSNumber numberWithBool: NO], @"confirm", nil];

  [controller performOperation: op];
  return waitForOperations();
}

static BOOL undo(void)
{
  NSError *err = nil;
  BOOL ok = [[GWFileUndoStack sharedStack] undo: &err];

  if (!ok)
    NSLog(@"undo refused: %@", [err localizedDescription]);
  return ok && waitForOperations();
}

static BOOL redo(void)
{
  NSError *err = nil;
  BOOL ok = [[GWFileUndoStack sharedStack] redo: &err];

  if (!ok)
    NSLog(@"redo refused: %@", [err localizedDescription]);
  return ok && waitForOperations();
}

static NSString *undoTitle(void)
{
  return [[GWFileUndoStack sharedStack] undoMenuTitle];
}

static NSString *redoTitle(void)
{
  return [[GWFileUndoStack sharedStack] redoMenuTitle];
}

int main(void)
{
  NSAutoreleasePool *arp = [NSAutoreleasePool new];
  GWFileUndoStack *stack = [GWFileUndoStack sharedStack];
  NSArray *one;

  /* Argument domain: never written to the user's defaults.  No progress
   * window; the plain theme because Eau would wait for a menu server that
   * is not on the test display. */
  {
    NSUserDefaults *defs = [NSUserDefaults standardUserDefaults];
    NSMutableDictionary *args = [[[defs volatileDomainForName: NSArgumentDomain]
                                   mutableCopy] autorelease];

    [args setObject: @"YES" forKey: @"fopstatusnotshown"];
    [args setObject: @"GNUstep" forKey: @"GSTheme"];
    [defs removeVolatileDomainForName: NSArgumentDomain];
    [defs setVolatileDomain: args forName: NSArgumentDomain];
  }
  /* Operation places its progress window on the screen, which needs the
   * window server connection that only NSApplication completes. */
  [NSApplication sharedApplication];

  fm = [NSFileManager defaultManager];
  root = [[NSTemporaryDirectory() stringByAppendingPathComponent:
            [NSString stringWithFormat: @"t_UndoOperations-%d", getpid()]] retain];
  [fm removeFileAtPath: root handler: nil];
  [fm createDirectoryAtPath: root attributes: nil];
  [fm createDirectoryAtPath: P(@"A") attributes: nil];
  [fm createDirectoryAtPath: P(@"B") attributes: nil];
  [fm createDirectoryAtPath: P(@"Trash") attributes: nil];
  haveXattr = gs_xattr_supported([root fileSystemRepresentation]) == 1;
  if (haveXattr == NO)
    NSLog(@"no extended attributes in %@: checking the sidecar only", root);

  controller = [Operation new];
  [stack setPerformer: controller];
  [stack setTrashPath: P(@"Trash")];

  START_SET("move")
    touch(@"A/m");
    addMetadata(@"A/m");
    one = [NSArray arrayWithObject: @"m"];
    NEED(PASS(perform(NSWorkspaceMoveOperation, P(@"A"), P(@"B"), one), "move finished"));
    PASS(exists(@"B/m") && hasMetadata(@"B/m"), "moved with its metadata");
    PASS_EQUAL(undoTitle(), @"Undo Move of \"m\"", "Edit menu offers Undo Move");
    PASS(undo(), "undo runs");
    PASS(exists(@"A/m") && exists(@"B/m") == NO, "the item is back where it was");
    PASS(hasMetadata(@"A/m"), "its metadata came back with it");
    PASS(exists(@"B/._m") == NO, "no sidecar left behind");
    PASS_EQUAL(redoTitle(), @"Redo Move of \"m\"", "Edit menu offers Redo Move");
    PASS([stack canUndo] == NO, "the undo itself was not recorded as an action");
    PASS(redo(), "redo runs");
    PASS(exists(@"B/m") && hasMetadata(@"B/m") && exists(@"A/m") == NO, "moved again");
    PASS_EQUAL(undoTitle(), @"Undo Move of \"m\"", "and can be undone again");
    PASS([stack canRedo] == NO, "nothing left to redo");
  END_SET("move")

  START_SET("refusal on disk")
    touch(@"A/m");
    PASS(undo() == NO, "undo refused while another item has the old name");
    PASS(exists(@"B/m") && hasMetadata(@"B/m"), "nothing was moved");
    [fm removeFileAtPath: P(@"A/m") handler: nil];
    PASS(undo() && exists(@"A/m") && hasMetadata(@"A/m"), "undo works once the name is free");
  END_SET("refusal on disk")

  START_SET("copy")
    touch(@"A/c");
    addMetadata(@"A/c");
    NEED(PASS(perform(NSWorkspaceCopyOperation, P(@"A"), P(@"B"), [NSArray arrayWithObject: @"c"]), "copy finished"));
    PASS(hasMetadata(@"B/c"), "copied with its metadata");
    PASS_EQUAL(undoTitle(), @"Undo Copy of \"c\"", "Edit menu offers Undo Copy");
    PASS(undo(), "undo runs");
    PASS(exists(@"B/c") == NO && exists(@"B/._c") == NO, "the copy is gone");
    PASS(exists(@"Trash/c") && hasMetadata(@"Trash/c"), "into the Trash, metadata and all");
    PASS(hasMetadata(@"A/c"), "the original is untouched");
    PASS(redo() && hasMetadata(@"B/c"), "redo copies again");
  END_SET("copy")

  START_SET("duplicate")
    touch(@"A/d.txt");
    NEED(PASS(perform(NSWorkspaceDuplicateOperation, P(@"A"), P(@"A"), [NSArray arrayWithObject: @"d.txt"]), "duplicate finished"));
    PASS(exists(@"A/d_copy.txt"), "duplicated");
    PASS_EQUAL(undoTitle(), @"Undo Duplicate of \"d.txt\"", "Edit menu offers Undo Duplicate");
    PASS(undo() && exists(@"A/d_copy.txt") == NO && exists(@"A/d.txt"), "undo removes the duplicate only");
    PASS(redo() && exists(@"A/d_copy.txt"), "redo duplicates again");
  END_SET("duplicate")

  START_SET("rename")
    touch(@"A/r");
    addMetadata(@"A/r");
    [controller performOperation:
      [NSDictionary dictionaryWithObjectsAndKeys: @"WorkspaceRenameOperation", @"operation",
                    P(@"A/r"), @"source", P(@"A/r2"), @"destination",
                    [NSArray arrayWithObject: @""], @"files", nil]];
    NEED(PASS(waitForOperations(), "operation finished"));
    PASS(exists(@"A/r2") && hasMetadata(@"A/r2") && exists(@"A/._r") == NO,
         "rename takes the sidecar along");
    PASS_EQUAL(undoTitle(), @"Undo Rename of \"r\"", "Edit menu offers Undo Rename");
    PASS(undo() && exists(@"A/r") && hasMetadata(@"A/r") && exists(@"A/r2") == NO
         && exists(@"A/._r2") == NO, "undo restores the old name, metadata included");
    PASS(redo() && exists(@"A/r2") && hasMetadata(@"A/r2"), "redo renames again");
  END_SET("rename")

  START_SET("move to Trash and put back")
    touch(@"A/t");
    addMetadata(@"A/t");
    touch(@"Trash/t");
    touch(@"A/u");
    NEED(PASS(perform(NSWorkspaceRecycleOperation, P(@"A"), P(@"Trash"),
                      [NSArray arrayWithObjects: @"t", @"u", nil]), "move to Trash finished"));
    PASS(exists(@"A/t") == NO && exists(@"Trash/t_copy") && exists(@"Trash/u"),
         "trashed; the Trash renamed the item whose name it already had");
    PASS_EQUAL(undoTitle(), @"Undo Move of 2 Items to Trash", "Edit menu offers the put back");
    PASS(undo(), "undo runs");
    PASS(exists(@"A/t") && hasMetadata(@"A/t") && exists(@"A/u"),
         "both are back at their original location under their own names");
    PASS(exists(@"Trash/t") && exists(@"Trash/t_copy") == NO && exists(@"Trash/u") == NO,
         "the other item in the Trash stayed");
    PASS(redo() && exists(@"A/t") == NO && exists(@"A/u") == NO, "redo trashes again");
  END_SET("move to Trash and put back")

  START_SET("make alias")
    touch(@"A/a");
    NEED(PASS(perform(FSNWorkspaceCreateAliasOperation, P(@"A"), P(@"B"), [NSArray arrayWithObject: @"a"]), "make alias finished"));
    {
      GWFileUndoRecord *rec = [stack undoRecord];
      NSString *alias = [[[rec items] lastObject] objectForKey: GWFileUndoToKey];

      PASS(alias != nil && [fm fileExistsAtPath: alias], "alias made");
      PASS_EQUAL(undoTitle(), @"Undo Make Alias of \"a\"", "Edit menu offers Undo Make Alias");
      PASS(undo() && [fm fileExistsAtPath: alias] == NO && exists(@"A/a"),
           "undo removes the alias, not the original");
    }
  END_SET("make alias")

  START_SET("make alias in the same folder keeps the original")
    {
      NSUInteger before;

      touch(@"A/same");
      before = [[fm directoryContentsAtPath: P(@"A")] count];
      NEED(PASS(perform(FSNWorkspaceCreateAliasOperation, P(@"A"), P(@"A"),
                        [NSArray arrayWithObject: @"same"]), "make alias in place finished"));
      PASS(exists(@"A/same"), "the original is still there");
      PASS([[fm directoryContentsAtPath: P(@"A")] count] == before + 1,
           "the alias was written next to it");
    }
  END_SET("make alias in the same folder keeps the original")

  START_SET("new folder")
    [controller performOperation:
      [NSDictionary dictionaryWithObjectsAndKeys: @"WorkspaceCreateDirOperation", @"operation",
                    P(@"B"), @"source", P(@"B"), @"destination",
                    [NSArray arrayWithObject: @"New Folder"], @"files", nil]];
    NEED(PASS(waitForOperations(), "operation finished"));
    PASS(exists(@"B/New Folder"), "folder made");
    PASS_EQUAL(undoTitle(), @"Undo New Folder", "Edit menu offers Undo New Folder");
    PASS(undo() && exists(@"B/New Folder") == NO, "undo removes it");
    PASS(redo() && exists(@"B/New Folder"), "redo makes it again");
  END_SET("new folder")

  [controller release];
  [fm removeFileAtPath: root handler: nil];
  [arp release];
  return 0;
}
