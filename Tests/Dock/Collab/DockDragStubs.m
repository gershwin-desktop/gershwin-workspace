/* DockDragStubs.m - the Dock's collaborators for t_DockDragRemoval.
 *
 * t_DockDragRemoval compiles Dock.m in-process, so every class Dock.m names
 * has to exist in the link (see DockLaunchRefreshThreadStubs.m for why).
 * Unlike that test, this one puts icons into the Dock, drags them and takes
 * them out through the context menu, so DockIcon here is a small stand-in
 * that keeps the state the Dock reads back from its icons (kind, docked,
 * launched, name and path) in DockIcon's own ivars.  Nothing of what the
 * test asserts is decided here: whether an icon stays, where it moves and
 * what is saved are the real Dock.m's answers.  An icon whose path ends in
 * ".app" stands for an application, any other for a kept folder.
 *
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import "Workspace.h"
#import "DockIcon.h"
#import "DockStack.h"
#import "GWDockWindow.h"
#import "FSNode.h"
#import "DockDragStubs.h"

#pragma clang diagnostic ignored "-Wincomplete-implementation"
#pragma clang diagnostic ignored "-Wprotocol"
#pragma clang diagnostic ignored "-Wobjc-protocol-method-implementation"

@implementation Workspace
/* FSNIcon's +initialize asks the desktop application named in the global
 * defaults (Workspace) for itself; there is none in this test. */
+ (Workspace *)gworkspace
{
  return nil;
}
@end

@implementation DockStack
+ (void)closeForIcon:(DockIcon *)icon
{
}
@end

@implementation GWDockWindow
@end

@implementation DockIcon

- (id)initStandInWithPath:(NSString *)path docked:(BOOL)value
{
  self = [super initWithFrame: NSMakeRect(0, 0, 64, 64)];
  if (self != nil)
    {
      ASSIGN (node, [FSNode nodeWithPath: path]);
      ASSIGN (appName, [[path lastPathComponent] stringByDeletingPathExtension]);
      docked = value;
    }
  return self;
}

- (void)dealloc
{
  RELEASE (appName);
  [super dealloc];
}

- (FSNode *)node { return node; }
- (NSString *)path { return [node path]; }
- (NSString *)appName { return appName; }
- (BOOL)isWsIcon { return NO; }
- (BOOL)isTrashIcon { return NO; }
- (BOOL)isSpecialIcon { return NO; }
- (BOOL)isFolderIcon { return [[node path] hasSuffix: @".app"] == NO; }
- (BOOL)isApplicationIcon { return [[node path] hasSuffix: @".app"]; }
- (void)setDocked:(BOOL)value { docked = value; }
- (BOOL)isDocked { return docked; }
- (BOOL)isLaunched { return NO; }
- (void)setLaunched:(BOOL)value { }
- (DockStackViewStyle)stackViewStyle { return stackViewStyle; }
- (DockStackSort)stackSort { return stackSort; }
- (void)setIsDndSourceIcon:(BOOL)value { isDndSourceIcon = value; }
- (BOOL)isDndSourceIconForTest { return isDndSourceIcon; }
- (void)setIsDragMountpointOnly:(BOOL)value { }
- (void)unselect { }

@end
