/* t_DockLaunchRefreshThreadStubs.m - link-only stand-ins for the Dock's
 * collaborator classes that t_DockLaunchRefreshThread.m never actually
 * messages.
 *
 * Compiling Dock.m in-process (see t_DockLaunchRefreshThread.m) pulls in
 * every class it names anywhere in the file - createWorkspaceIcon,
 * iconMenuAction and the rest reference Workspace, DockIcon, DockStack and
 * GWDockWindow - even though this test only ever reaches -performLaunchRefresh
 * Selector:target:withObject: and -stopLaunchRefreshThread on a bare
 * `[Dock alloc]`.  The Objective-C runtime resolves every class reference in
 * a binary at load time regardless of whether the referencing code path
 * ever runs, so those four classes must exist somewhere in the link or the
 * test tool fails with "symbol lookup error" before main() is reached.
 * Workspace alone is a 5800-line application delegate that would drag in
 * Preferences, ISOWrite, Network, Finder, Inspector, Operation and History -
 * effectively the whole app - just to satisfy a symbol this test never
 * calls. These four empty implementations exist ONLY to give those class
 * symbols a definition; none of their real behavior is reimplemented here
 * (that would be the "mirror test" this suite's skill warns against), and
 * none of it needs to be, since the test never sends them a message.
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

#pragma clang diagnostic ignored "-Wincomplete-implementation"
#pragma clang diagnostic ignored "-Wprotocol"
#pragma clang diagnostic ignored "-Wobjc-protocol-method-implementation"

@implementation Workspace
@end

@implementation DockIcon
@end

@implementation DockStack
@end

@implementation GWDockWindow
@end
