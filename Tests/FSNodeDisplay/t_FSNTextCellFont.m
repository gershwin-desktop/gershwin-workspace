/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-2.0-or-later
 */

/* A text cell keeps the outcome of fitting its title to a width.  Changing
 * the font changes that outcome, so -setFont: must forget it; a list view
 * that changes its text size can then keep its cells. */

#import <AppKit/AppKit.h>
#import <objc/runtime.h>
#import "Testing.h"
#import "FSNListView.h"
#import "FSNode.h"

int
main(void)
{
  NSAutoreleasePool *arp = [NSAutoreleasePool new];
  NSFileManager *fm = [NSFileManager defaultManager];
  NSString *dir = [NSTemporaryDirectory () stringByAppendingPathComponent:
                    [NSString stringWithFormat: @"t_FSNTextCellFont_%d", (int)getpid ()]];
  FSNListView *view;
  FSNListViewDataSource *ds;
  NSTableColumn *column;
  id cellBefore, cellAfter;

  [NSApplication sharedApplication];
  [fm removeFileAtPath: dir handler: nil];
  [fm createDirectoryAtPath: dir attributes: nil];
  [@"a" writeToFile: [dir stringByAppendingPathComponent: @"a.txt"] atomically: YES];

  view = [[FSNListView alloc] initWithFrame: NSMakeRect (0, 0, 600, 300)
                            dataSourceClass: [FSNListViewDataSource class]];
  ds = (FSNListViewDataSource *)[view dataSource];
  [view showContentsOfNode: [FSNode nodeWithPath: dir]];

  column = [[view tableColumns] objectAtIndex: 0];
  cellBefore = [column dataCell];
  [ds setTextSize: 18];
  cellAfter = [column dataCell];

  PASS ([[cellAfter font] pointSize] == 18, "MI-FSN-50 the column's cell uses the new text size");
  PASS (cellBefore == cellAfter, "MI-FSN-51 the cell is kept, its font is changed in place");
  {
    /* Same text-size path a second time, to shrink: the fitted title of the
     * first size must not survive. */
    Ivar iv = class_getInstanceVariable ([cellAfter class], "fittedTitle");

    object_setIvar (cellAfter, iv, @"stale fitted title");
    [ds setTextSize: 12];
    PASS (object_getIvar (cellAfter, iv) == nil, "MI-FSN-52 a font change forgets the fitted title");
  }

  [view release];
  [fm removeFileAtPath: dir handler: nil];
  [arp release];
  return 0;
}
