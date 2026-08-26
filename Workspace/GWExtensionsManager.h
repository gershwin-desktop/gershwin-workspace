/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import "FSNodeRep.h"
#import "GWorkspaceExtension.h"

/* Loads .gwext bundles from Library/Bundles/ (all domains), fans context-menu
 * and node-decoration requests out to them, and bridges FSNode's
 * FSNodeRepDecorationDelegate to the loaded extensions.  Contains no
 * application-specific logic. */
@interface GWExtensionsManager : NSObject <FSNodeRepDecorationDelegate>

+ (GWExtensionsManager *)defaultManager;

- (void)loadExtensions;
- (void)appendContextMenuItems:(NSMenu *)menu forNodes:(NSArray *)nodes;

@end
