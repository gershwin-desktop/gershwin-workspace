/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

/* t_FinderChangePaths.m
 *
 * Proves the boundary check that fixes fileSystemDidChange:'s LSFolders
 * match loop in Workspace/Finder/Finder.m: a destroy/recycle operation
 * carries no "destination" key when there is none (performFileOperation:
 * in WorkspaceApplication.m omits it for a nil destination), so dstpaths
 * ends up shorter than srcpaths, and indexing dstpaths by the same j used
 * for srcpaths raised NSRangeException while a Live Search Folder was open.
 *
 * Finder itself cannot be instantiated headless (its -init loads a Gorm nib
 * and builds a full window/toolbar UI), and linking Finder.m as an object
 * pulls in its whole sibling class graph - so the boundary check was
 * extracted into its own Foundation-only source pair,
 * Workspace/Finder/GWChangePaths.h/.m, which this test links and calls
 * directly: the real shipped function, not a copy of its logic. */
#import <Foundation/Foundation.h>
#import "Testing.h"
#import "GWChangePaths.h"

int main(void)
{
  NSAutoreleasePool *arp = [NSAutoreleasePool new];

  /* Fixture: a destroy operation on three files with no destination - what
   * WorkspaceApplication.m sends when destroying/recycling without one. */
  NSMutableArray *srcpaths = [NSMutableArray arrayWithObjects:
    @"/tmp/a", @"/tmp/b", @"/tmp/c", nil];
  NSMutableArray *dstpaths = [NSMutableArray array];
  NSUInteger j;
  BOOL raised = NO;
  NSString *last = @"unset";

  NS_DURING
    {
      for (j = 0; j < [srcpaths count]; j++)
        {
          last = GWChangePathsDestinationAtIndex(dstpaths, j);
        }
    }
  NS_HANDLER
    {
      raised = YES;
    }
  NS_ENDHANDLER

  PASS(raised == NO,
    "GWChangePathsDestinationAtIndex never raises for a destroy op whose dstpaths is shorter than srcpaths");
  PASS(last == nil,
    "GWChangePathsDestinationAtIndex returns nil once j reaches dstpaths' own (empty) count");

  [arp release];
  return 0;
}
