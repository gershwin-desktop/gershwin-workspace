/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

/* Generic extension protocol for GWorkspace.  Bundles dropped into
 * Library/Bundles/ with a .gwext extension and a principal class conforming
 * to this protocol are loaded by GWExtensionsManager and may contribute to
 * context menus and node-icon decoration.  Deliberately contains NO
 * application-specific knowledge (no "git", etc.); each bundle decides what
 * it cares about. */

#ifndef GWORKSPACE_EXTENSION_H
#define GWORKSPACE_EXTENSION_H

#import <Foundation/Foundation.h>
#import "FSNode.h"
#import <AppKit/NSImage.h>
#import <AppKit/NSMenu.h>

@protocol GWorkspaceExtension <NSObject>

@optional

/* Called by Workspace after it assembles its own context-menu items.  Return
 * YES from -extensionCanHandleNodes: to be given a chance to append. */
- (BOOL)extensionCanHandleNodes:(NSArray *)nodes;
- (void)extensionAppendToContextMenu:(NSMenu *)menu
                           forNodes:(NSArray *)nodes;

/* Node-icon decoration.  Mirrors FSNodeRepDecorationDelegate; the extension
 * manager forwards badge requests from FSNode to extensions implementing it. */
- (NSImage *)badgeImageForNode:(FSNode *)node;

/* Count shown on a red corner badge (e.g. changed/unpushed file count).  Return
 * 0 for none.  Mirrors -badgeCountForNode: in FSNodeRepDecorationDelegate. */
- (NSInteger)badgeCountForNode:(FSNode *)node;

/* Begin/end watching the node's backing repository for external changes so the
 * count badge can refresh on demand.  Forwarded from FSNIcon via the extension
 * manager; an extension implements these to start/stop file-system monitors. */
- (void)startWatchingNode:(FSNode *)node;
- (void)stopWatchingNode:(FSNode *)node;

@end

#endif // GWORKSPACE_EXTENSION_H
