/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 */

/* A GWTrashFlight hides the flying icon's shared name-label editor
 * (-setRep:hiddenForFlight:, keyed on editIcon) so it does not linger at the
 * icon's old position for the length of the flight (see FSNIconsView.m's
 * -setRep:hiddenForFlight: and -showNameEditor).  The file the flight was
 * animating is then removed from the view entirely (the recycle it was
 * flying towards actually completing) - at which point nothing that
 * matches on "the rep currently hidden" can find the editor to restore it.
 * The very next selection must still show the editor: -updateNameEditor
 * itself has to unconditionally un-hide it whenever it (re)positions it for
 * a new selection, not rely only on the flight's own restore path. */

#import <AppKit/AppKit.h>
#import "Testing.h"
#import "FSNIconsView.h"
#import "FSNIcon.h"
#import "FSNode.h"

int
main(void)
{
  NSAutoreleasePool *arp = [NSAutoreleasePool new];
  NSFileManager *fm = [NSFileManager defaultManager];
  NSString *dir;
  NSString *pathA, *pathB;
  FSNIconsView *view;
  FSNode *node;
  id repA, repB;
  NSTextField *editor;
  NSUInteger i;

  /* Views need a display server before AppKit will make any of them. */
  if (getenv("DISPLAY") == NULL)
    {
      printf("no DISPLAY, skipping\n");
      [arp release];
      return 0;
    }
  [NSApplication sharedApplication];

  dir = [NSTemporaryDirectory() stringByAppendingPathComponent:
          [NSString stringWithFormat: @"t_FSNIconsViewFlightLabel_%d", (int)getpid()]];
  [fm removeFileAtPath: dir handler: nil];
  [fm createDirectoryAtPath: dir attributes: nil];

  pathA = [dir stringByAppendingPathComponent: @"A.txt"];
  pathB = [dir stringByAppendingPathComponent: @"B.txt"];
  [@"a" writeToFile: pathA atomically: YES];
  [@"b" writeToFile: pathB atomically: YES];

  node = [FSNode nodeWithPath: dir];
  /* -init (not -initWithFrame:) is what assigns the fsnodeRep ivar
   * showContentsOfNode: relies on; NSView's own -initWithFrame: alone
   * leaves it nil. */
  view = [[FSNIconsView alloc] init];
  [view setFrame: NSMakeRect(0, 0, 400, 300)];
  [view showContentsOfNode: node];

  repA = [view repOfSubnodePath: pathA];
  repB = [view repOfSubnodePath: pathB];
  PASS(repA != nil && repB != nil, "both icons were created for the two files");

  /* Select A - the single selection that gives it the shared name editor. */
  [view selectRepsOfPaths: [NSArray arrayWithObject: pathA]];

  /* A GWTrashFlight hides A and its label while it flies to the Trash. */
  [view setRep: repA hiddenForFlight: YES];

  /* The recycle behind that flight completes: A's node is gone. */
  [view removeRepOfSubnodePath: pathA];

  /* The user selects B next. */
  [view selectRepsOfPaths: [NSArray arrayWithObject: pathB]];

  editor = nil;
  for (i = 0; i < [[view subviews] count]; i++)
    {
      id sv = [[view subviews] objectAtIndex: i];

      if ([sv isKindOfClass: [FSNIconNameEditor class]])
        {
          editor = sv;
          break;
        }
    }

  PASS(editor != nil, "the name editor is a subview after selecting B");
  PASS(editor != nil && [editor isHidden] == NO,
       "the name editor is shown for B, not left hidden from A's flight");

  [view release];
  [fm removeFileAtPath: dir handler: nil];
  [arp release];
  return 0;
}
