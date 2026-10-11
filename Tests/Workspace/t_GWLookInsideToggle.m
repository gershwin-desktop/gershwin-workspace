/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

/* t_GWLookInsideToggle.m - Space opens the Look Inside panel for the current
 * selection and closes it again on a second press (from either the panel
 * or the folder window, regardless of what is selected by then); an empty
 * selection with nothing already open does nothing.  Window creation is
 * stubbed (GWLookInsideStubController below overrides the two seam
 * methods) so this runs headless, no display needed - see
 * GWLookInsideController.h on why the base class itself never links the
 * AppKit/Inspector-bundle-heavy GWLookInsidePanel. */

#import <Foundation/Foundation.h>
#import "Testing.h"
#include "../../Workspace/LookInside/GWLookInsideController.m"

@interface GWLookInsideStubController : GWLookInsideController
{
@public
  int opens;
  int closes;
}
@end

@implementation GWLookInsideStubController

- (void)createAndShowPanelForPaths:(NSArray *)paths sourceWindow:(id)sourceWindow
{
  opens++;
}

- (void)destroyPanel
{
  closes++;
}

@end

int main(void)
{
  NSAutoreleasePool *arp = [NSAutoreleasePool new];

  /* --- the pure decision, isolated from any window --- */
  {
    PASS([GWLookInsideController actionForSpaceKeyWithSelectionCount: 0 isOpen: NO]
           == GWLookInsideActionNone,
      "no selection, nothing open: does nothing");
    PASS([GWLookInsideController actionForSpaceKeyWithSelectionCount: 1 isOpen: NO]
           == GWLookInsideActionOpen,
      "a selection, nothing open: opens");
    PASS([GWLookInsideController actionForSpaceKeyWithSelectionCount: 0 isOpen: YES]
           == GWLookInsideActionClose,
      "already open, selection now empty: still closes");
    PASS([GWLookInsideController actionForSpaceKeyWithSelectionCount: 3 isOpen: YES]
           == GWLookInsideActionClose,
      "already open, a different selection: closes rather than switching");
  }

  /* --- the stateful toggle, window creation stubbed --- */
  {
    GWLookInsideStubController *ctrl = [GWLookInsideStubController new];
    NSArray *paths = [NSArray arrayWithObject: @"/tmp/some-file"];
    BOOL handled;

    PASS(![ctrl isOpen], "starts closed");

    handled = [ctrl toggleLookInsideForPaths: nil sourceWindow: nil];
    PASS(handled == NO, "Space with no selection reports unhandled");
    PASS(![ctrl isOpen], "...and stays closed");
    PASS(ctrl->opens == 0, "...without ever asking for a panel");

    handled = [ctrl toggleLookInsideForPaths: paths sourceWindow: nil];
    PASS(handled == YES, "Space with a selection is handled");
    PASS([ctrl isOpen], "...and opens");
    PASS(ctrl->opens == 1, "...creating exactly one panel");

    handled = [ctrl toggleLookInsideForPaths: paths sourceWindow: nil];
    PASS(handled == YES, "second Space is handled");
    PASS(![ctrl isOpen], "...and closes");
    PASS(ctrl->closes == 1, "...tearing down the one panel");

    handled = [ctrl toggleLookInsideForPaths: paths sourceWindow: nil];
    PASS(handled == YES, "third Space (a fresh open) is handled");
    PASS([ctrl isOpen], "...and opens again");
    PASS(ctrl->opens == 2, "...creating a second panel");

    [ctrl close];
    PASS(![ctrl isOpen], "-close always leaves it closed");
    PASS(ctrl->closes == 2, "...tearing down the second panel");

    RELEASE(ctrl);
  }

  [arp release];
  return 0;
}
