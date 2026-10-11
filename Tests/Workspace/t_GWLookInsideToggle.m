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

@interface GWTestNode : NSObject
{
@public
  NSString *path;
}
- (NSString *)path;
@end

@implementation GWTestNode
- (NSString *)path
{
  return path;
}
@end

static GWTestNode *testNode(NSString *p)
{
  GWTestNode *n = [[GWTestNode new] autorelease];

  n->path = p;
  return n;
}

@interface GWLookInsideStubController : GWLookInsideController
{
@public
  id keyBase;
  int opens;
  int closes;
  int updates;
  BOOL lastFullScreen;
  NSArray *lastShown;
}
@end

@implementation GWLookInsideStubController

- (void)createAndShowPanelForPaths:(NSArray *)paths
                      sourceWindow:(id)sourceWindow
                        fullScreen:(BOOL)fullScreen
{
  opens++;
  lastFullScreen = fullScreen;
}

- (id)keyWindowBaseNode
{
  return keyBase;
}

- (void)showPathsInPanel:(NSArray *)paths
{
  updates++;
  lastShown = paths;
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

  /* --- MI-LI-19: Option-Space opens straight into full screen --- */
  {
    GWLookInsideStubController *ctrl = [GWLookInsideStubController new];
    NSArray *paths = [NSArray arrayWithObject: @"/tmp/some-file"];

    [ctrl toggleLookInsideForPaths: paths sourceWindow: nil fullScreen: YES];
    PASS([ctrl isOpen] && ctrl->lastFullScreen, "MI-LI-19 opens in full screen when asked");
    [ctrl close];
    [ctrl toggleLookInsideForPaths: paths sourceWindow: nil];
    PASS([ctrl isOpen] && !ctrl->lastFullScreen, "MI-LI-19 Space alone opens the panel");
    RELEASE(ctrl);
  }

  /* --- MI-LI-20: the open panel follows the selection --- */
  {
    GWLookInsideStubController *ctrl = [GWLookInsideStubController new];
    NSArray *first = [NSArray arrayWithObject: @"/tmp/a"];
    NSArray *second = [NSArray arrayWithObjects: @"/tmp/b", @"/tmp/c", nil];

    [ctrl selectionDidChange: second];
    PASS(ctrl->updates == 0 && ![ctrl isOpen],
      "MI-LI-20 a selection change while closed opens nothing");

    [ctrl toggleLookInsideForPaths: first sourceWindow: nil];
    [ctrl selectionDidChange: first];
    PASS(ctrl->updates == 0, "MI-LI-20 the same selection again does not rebuild the preview");

    [ctrl selectionDidChange: second];
    PASS(ctrl->updates == 1 && [ctrl->lastShown isEqual: second],
      "MI-LI-20 a new selection is shown in the open panel");

    [ctrl selectionDidChange: [NSArray array]];
    PASS(ctrl->updates == 1, "MI-LI-20 an emptied selection keeps the last preview");

    [ctrl close];
    [ctrl toggleLookInsideForPaths: first sourceWindow: nil];
    [ctrl selectionDidChange: second];
    PASS(ctrl->updates == 2, "MI-LI-20 a reopened panel follows the selection too");
    RELEASE(ctrl);
  }

  /* --- an empty click in a folder window does not select the folder --- */
  {
    GWLookInsideStubController *ctrl = [GWLookInsideStubController new];
    GWTestNode *folder = testNode(@"/tmp/folder");
    GWTestNode *item = testNode(@"/tmp/folder/item");
    NSArray *first = [NSArray arrayWithObject: @"/tmp/folder/item"];

    ctrl->keyBase = folder;
    [ctrl toggleLookInsideForPaths: first sourceWindow: nil];
    [ctrl selectionDidChange: [NSArray arrayWithObject: @"/tmp/folder"]];
    PASS(ctrl->updates == 0,
      "click on empty space keeps the last item, not the folder (Finder)");
    [ctrl selectionDidChange: [NSArray arrayWithObject: @"/tmp/other"]];
    PASS(ctrl->updates == 1, "...but another item is still followed");
    ctrl->keyBase = testNode(@"/tmp");
    [ctrl selectionDidChange: [NSArray arrayWithObject: @"/tmp/folder"]];
    PASS(ctrl->updates == 2,
      "...and the folder itself, selected in its parent window, is shown");
    [ctrl close];

    PASS([GWLookInsideController selectionPathsOfNodes: [NSArray arrayWithObject: folder]
                                              baseNode: folder] == nil,
      "the base folder as selection is no selection");
    PASS([[GWLookInsideController selectionPathsOfNodes: [NSArray arrayWithObject: item]
                                               baseNode: folder]
            isEqual: first],
      "a real item gives its path");
    PASS([[GWLookInsideController selectionPathsOfNodes: [NSArray arrayWithObject: folder]
                                               baseNode: nil]
            isEqual: [NSArray arrayWithObject: @"/tmp/folder"]],
      "without a base folder (Desktop) every node counts");

    /* One Space handler for folder windows and the Desktop. */
    PASS([ctrl handleSpaceKeyWithCommand: NO shift: NO control: NO option: YES
                               selection: [NSArray arrayWithObject: item]
                                baseNode: nil sourceWindow: nil]
           && [ctrl isOpen] && ctrl->lastFullScreen,
      "Option-Space opens full screen through the shared handler");
    [ctrl close];
    PASS(![ctrl handleSpaceKeyWithCommand: YES shift: NO control: NO option: NO
                                selection: [NSArray arrayWithObject: item]
                                 baseNode: nil sourceWindow: nil]
         && ![ctrl isOpen],
      "Cmd-Space is not ours");
    PASS(![ctrl handleSpaceKeyWithCommand: NO shift: NO control: NO option: NO
                                selection: [NSArray arrayWithObject: folder]
                                 baseNode: folder sourceWindow: nil],
      "Space on a folder window with nothing selected does nothing");
    RELEASE(ctrl);
  }

  [arp release];
  return 0;
}
