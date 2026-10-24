/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

/* t_GWViewerToolbarModel - the browsing window toolbar's item sets and the
 * rules for when each control can be used.  Headless. */

#import "Testing.h"
#import <AppKit/AppKit.h>
#import <Foundation/Foundation.h>

#include "../../Workspace/FileViewer/GWViewerToolbarModel.m"

static GWViewerToolbarState emptyState(void)
{
  GWViewerToolbarState s;
  memset(&s, 0, sizeof(s));
  return s;
}

int main(void)
{
  NSAutoreleasePool *arp = [NSAutoreleasePool new];
  NSArray *defaults = [GWViewerToolbarModel defaultItemIdentifiers];
  NSArray *allowed = [GWViewerToolbarModel allowedItemIdentifiers];

  START_SET("identifiers");
  {
    PASS([GWViewerToolbarIdentifier length] > 0, "the toolbar has a fixed identifier");
    NSSet *unique = [NSSet setWithArray:allowed];
    PASS([unique count] == [allowed count], "the palette lists every item once");
  }
  END_SET("identifiers");

  START_SET("default set");
  {
    NSArray *want = @[
      GWToolbarBackForwardItemIdentifier, NSToolbarFlexibleSpaceItemIdentifier,
      GWToolbarViewModeItemIdentifier, GWToolbarLookInsideItemIdentifier,
      GWToolbarActionItemIdentifier, NSToolbarFlexibleSpaceItemIdentifier,
      GWToolbarSearchItemIdentifier
    ];
    PASS_EQUAL(defaults, want,
               "Back/Forward, space, view mode, Look Inside, Action, space, Search");
  }
  END_SET("default set");

  START_SET("palette");
  {
    NSUInteger i;
    BOOL all = YES;
    NSArray *extra = @[
      GWToolbarPathItemIdentifier, GWToolbarNewFolderItemIdentifier, GWToolbarDeleteItemIdentifier,
      GWToolbarGetInfoItemIdentifier, GWToolbarEjectItemIdentifier, GWToolbarConnectItemIdentifier,
      NSToolbarCustomizeToolbarItemIdentifier, NSToolbarSeparatorItemIdentifier,
      NSToolbarSpaceItemIdentifier, NSToolbarFlexibleSpaceItemIdentifier
    ];

    for (i = 0; i < [defaults count]; i++)
      all = all && [allowed containsObject:[defaults objectAtIndex:i]];
    PASS(all, "every default item can be put back from the palette");

    all = YES;
    for (i = 0; i < [extra count]; i++)
      all = all && [allowed containsObject:[extra objectAtIndex:i]];
    PASS(all, "Path, New Folder, Delete, Get Info, Eject, Connect, Customize "
              "and the separators are offered");
  }
  END_SET("palette");

  START_SET("back and forward follow the history");
  {
    GWViewerToolbarState s = emptyState();
    PASS(![GWViewerToolbarModel isControl:GWToolbarControlBack enabledInState:s],
         "Back is disabled without history");
    PASS(![GWViewerToolbarModel isControl:GWToolbarControlForward enabledInState:s],
         "Forward is disabled without history");
    s.canGoBack = YES;
    PASS([GWViewerToolbarModel isControl:GWToolbarControlBack enabledInState:s],
         "Back is enabled with an earlier folder");
    PASS(![GWViewerToolbarModel isControl:GWToolbarControlForward enabledInState:s],
         "Forward stays disabled without a later folder");
    s.canGoForward = YES;
    PASS([GWViewerToolbarModel isControl:GWToolbarControlForward enabledInState:s],
         "Forward is enabled with a later folder");
  }
  END_SET("back and forward follow the history");

  START_SET("selection actions");
  {
    GWViewerToolbarState s = emptyState();
    PASS(![GWViewerToolbarModel isControl:GWToolbarControlGetInfo enabledInState:s],
         "Get Info needs a selection");
    PASS(![GWViewerToolbarModel isControl:GWToolbarControlDelete enabledInState:s],
         "Delete needs a selection");
    PASS(![GWViewerToolbarModel isControl:GWToolbarControlLookInside enabledInState:s],
         "Look Inside needs a selection");
    s.hasSelection = YES;
    PASS([GWViewerToolbarModel isControl:GWToolbarControlGetInfo enabledInState:s],
         "Get Info works on a selection");
    PASS([GWViewerToolbarModel isControl:GWToolbarControlDelete enabledInState:s],
         "Delete works on a selection");
    PASS([GWViewerToolbarModel isControl:GWToolbarControlLookInside enabledInState:s],
         "Look Inside works on a selection");
    s.showsTrash = YES;
    PASS(![GWViewerToolbarModel isControl:GWToolbarControlDelete enabledInState:s],
         "items already in the trash are not moved to it again");
  }
  END_SET("selection actions");

  START_SET("new folder");
  {
    GWViewerToolbarState s = emptyState();
    PASS(![GWViewerToolbarModel isControl:GWToolbarControlNewFolder enabledInState:s],
         "no new folder in a read-only folder");
    s.folderWritable = YES;
    PASS([GWViewerToolbarModel isControl:GWToolbarControlNewFolder enabledInState:s],
         "a new folder in a writable folder");
    s.showsTrash = YES;
    PASS(![GWViewerToolbarModel isControl:GWToolbarControlNewFolder enabledInState:s],
         "no new folder in the trash");
  }
  END_SET("new folder");

  START_SET("eject only for volumes");
  {
    GWViewerToolbarState s = emptyState();
    s.hasSelection = YES;
    PASS(![GWViewerToolbarModel isControl:GWToolbarControlEject enabledInState:s],
         "Eject is disabled for ordinary items");
    s.selectionHasVolume = YES;
    PASS([GWViewerToolbarModel isControl:GWToolbarControlEject enabledInState:s],
         "Eject is enabled for a selected volume");
  }
  END_SET("eject only for volumes");

  START_SET("always available");
  {
    GWViewerToolbarState s = emptyState();
    PASS([GWViewerToolbarModel isControl:GWToolbarControlViewMode enabledInState:s] &&
             [GWViewerToolbarModel isControl:GWToolbarControlAction enabledInState:s] &&
             [GWViewerToolbarModel isControl:GWToolbarControlSearch enabledInState:s] &&
             [GWViewerToolbarModel isControl:GWToolbarControlPath enabledInState:s] &&
             [GWViewerToolbarModel isControl:GWToolbarControlConnect enabledInState:s],
         "view mode, Action, Search, Path and Connect need no selection");
  }
  END_SET("always available");

  [arp release];
  return 0;
}
