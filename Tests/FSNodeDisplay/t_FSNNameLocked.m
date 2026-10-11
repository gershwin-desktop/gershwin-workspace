/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-2.0-or-later
 */

/* A file whose Finder metadata says "name locked" cannot be renamed in
 * place: no name editor opens in the icon, list or browser view.  A file
 * without the bit still can (the control group of each view).  The editor
 * shows the full name, with the extension a view may hide. */

#import <AppKit/AppKit.h>
#import "Testing.h"
#import "FSNIconsView.h"
#import "FSNIcon.h"
#import "FSNListView.h"
#import "FSNBrowser.h"
#import "FSNBrowserCell.h"
#import "FSNBrowserColumn.h"
#import "FSNode.h"
#import "FSNodeRep.h"
#import "FSNMetadataProvider.h"

@interface LockingProvider : NSObject <FSNMetadataProvider>
{
@public
  NSString *lockedPath;
  NSString *hiddenPath;
}
@end

@implementation LockingProvider
- (NSColor *)labelColorForPath:(NSString *)path { return nil; }
- (BOOL)isInvisibleAtPath:(NSString *)path { return NO; }
- (NSImage *)customIconForPath:(NSString *)path { return nil; }
- (NSPoint)iconPositionForPath:(NSString *)path { return NSMakePoint(-1, -1); }
- (void)invalidateCaches {}
- (BOOL)isNameLockedForPath:(NSString *)path { return [path isEqualToString: lockedPath]; }
- (BOOL)isExtensionHiddenForPath:(NSString *)path { return [path isEqualToString: hiddenPath]; }
@end

static BOOL
hasSubviewOfClass(NSView *view, Class cls)
{
  NSEnumerator *e = [[view subviews] objectEnumerator];
  NSView *v;

  while ((v = [e nextObject]))
    {
      if ([v isKindOfClass: cls])
        {
          return YES;
        }
    }
  return NO;
}

int
main(void)
{
  NSAutoreleasePool *arp = [NSAutoreleasePool new];
  NSFileManager *fm = [NSFileManager defaultManager];
  NSString *dir;
  NSString *lockedPath, *freePath;
  LockingProvider *provider = [LockingProvider new];
  FSNodeRep *rep = [FSNodeRep sharedInstance];
  FSNode *dirNode, *lockedNode, *freeNode;

  if (getenv ("DISPLAY") == NULL)
    {
      printf ("no DISPLAY, skipping\n");
      [arp release];
      return 0;
    }
  [[NSUserDefaults standardUserDefaults] setInteger: 1 forKey: @"GSFilenameExtensionDisplayMode"];
  [NSApplication sharedApplication];

  dir = [NSTemporaryDirectory () stringByAppendingPathComponent:
          [NSString stringWithFormat: @"t_FSNNameLocked_%d", (int)getpid ()]];
  [fm removeFileAtPath: dir handler: nil];
  [fm createDirectoryAtPath: dir attributes: nil];
  lockedPath = [dir stringByAppendingPathComponent: @"locked.txt"];
  freePath = [dir stringByAppendingPathComponent: @"free.txt"];
  [@"a" writeToFile: lockedPath atomically: YES];
  [@"b" writeToFile: freePath atomically: YES];
  provider->lockedPath = lockedPath;
  provider->hiddenPath = freePath;
  [rep setMetadataProvider: provider];

  dirNode = [FSNode nodeWithPath: dir];
  lockedNode = [FSNode nodeWithPath: lockedPath];
  freeNode = [FSNode nodeWithPath: freePath];

  PASS ([rep isNameLockedForPath: lockedPath], "MI-FSN-30 the provider's name lock reaches FSNodeRep");
  PASS ([lockedNode isNameLocked] && ![freeNode isNameLocked], "MI-FSN-31 and FSNode");
  PASS (![lockedNode isLocked], "MI-FSN-32 a name lock is not the file-operation lock");

  /* --- icon view ------------------------------------------------------ */
  {
    FSNIconsView *view = [[FSNIconsView alloc] init];

    [view setFrame: NSMakeRect (0, 0, 400, 300)];
    [view showContentsOfNode: dirNode];

    [view selectRepsOfPaths: [NSArray arrayWithObject: freePath]];
    PASS ([view canStartRepNameEditing], "MI-FSN-33 icon view: a free file can start editing");
    PASS (hasSubviewOfClass (view, NSClassFromString (@"FSNIconNameEditor")),
          "MI-FSN-34 icon view: its name label is there");

    [view selectRepsOfPaths: [NSArray arrayWithObject: lockedPath]];
    PASS (![view canStartRepNameEditing], "MI-FSN-35 icon view: a name-locked file cannot start editing");
    [view release];
  }

  /* --- list view ------------------------------------------------------ */
  {
    FSNListView *view = [[FSNListView alloc] initWithFrame: NSMakeRect (0, 0, 600, 300)
                                              dataSourceClass: [FSNListViewDataSource class]];
    FSNListViewDataSource *ds = (FSNListViewDataSource *)[view dataSource];
    NSUInteger i;
    NSInteger lockedRow = -1, freeRow = -1;
    NSArray *reps;
    Class editorClass = NSClassFromString (@"FSNListViewNameEditor");

    [view showContentsOfNode: dirNode];
    reps = [ds reps];
    for (i = 0; i < [reps count]; i++)
      {
        NSString *p = [[[reps objectAtIndex: i] node] path];

        if ([p isEqualToString: lockedPath]) lockedRow = i;
        if ([p isEqualToString: freePath]) freeRow = i;
      }
    PASS (lockedRow >= 0 && freeRow >= 0, "MI-FSN-36 list view: both rows are there");

    [view selectRowIndexes: [NSIndexSet indexSetWithIndex: freeRow]
               byExtendingSelection: NO];
    [ds setEditorAtRow: freeRow withMouseDownEvent: nil];
    PASS (hasSubviewOfClass (view, editorClass), "MI-FSN-37 list view: a free file opens the editor");
    {
      NSEnumerator *e = [[view subviews] objectEnumerator];
      NSView *v;

      while ((v = [e nextObject]))
        {
          if ([v isKindOfClass: editorClass])
            {
              PASS_EQUAL ([(NSTextField *)v stringValue], @"free.txt",
                          "MI-FSN-38 list view: the editor shows the full name with the hidden extension");
            }
        }
    }
    [ds stopRepNameEditing];

    [view selectRowIndexes: [NSIndexSet indexSetWithIndex: lockedRow]
               byExtendingSelection: NO];
    [ds setEditorAtRow: lockedRow withMouseDownEvent: nil];
    PASS (!hasSubviewOfClass (view, editorClass), "MI-FSN-39 list view: a name-locked file opens no editor");
    [view release];
  }

  /* --- browser -------------------------------------------------------- */
  {
    FSNBrowser *browser = [[FSNBrowser alloc] initWithBaseNode: dirNode
                                                 visibleColumns: 1
                                                       scroller: nil
                                                     cellsIcons: NO
                                                     acceptsDnd: NO
                                                  editableCells: YES
                                                selectionColumn: NO];
    FSNBrowserColumn *col;
    FSNBrowserCell *lockedCell = nil, *freeCell = nil;
    NSEnumerator *e;
    FSNBrowserCell *cell;
    Class editorClass = NSClassFromString (@"FSNCellNameEditor");

    [browser setFrame: NSMakeRect (0, 0, 400, 300)];
    [browser loadColumnZero];
    col = [browser lastLoadedColumn];
    e = [[[col cmatrix] cells] objectEnumerator];
    while ((cell = [e nextObject]))
      {
        if ([[[cell node] path] isEqualToString: lockedPath]) lockedCell = cell;
        if ([[[cell node] path] isEqualToString: freePath]) freeCell = cell;
      }
    PASS (lockedCell != nil && freeCell != nil, "MI-FSN-40 browser: both cells are there");
    PASS_EQUAL ([freeCell stringValue], @"free", "MI-FSN-41 browser: the cell drops the hidden extension");

    [browser setEditorForCell: freeCell inColumn: col];
    PASS (hasSubviewOfClass (browser, editorClass), "MI-FSN-42 browser: a free file opens the editor");
    [browser stopCellEditing];
    [browser setEditorForCell: lockedCell inColumn: col];
    PASS (!hasSubviewOfClass (browser, editorClass), "MI-FSN-43 browser: a name-locked file opens no editor");
    [browser release];
  }

  [rep setMetadataProvider: nil];
  [fm removeFileAtPath: dir handler: nil];
  [arp release];
  return 0;
}
