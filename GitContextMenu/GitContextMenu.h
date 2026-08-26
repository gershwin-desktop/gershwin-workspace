/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import "GWorkspaceExtension.h"
#import "FSNode.h"

/* Example GWorkspace extension: adds a "Git" submenu (Status / Diff / Log) to
 * the context menu of folders that are git repositories (contain a .git
 * directory) and draws a small badge on those folders.  All git knowledge
 * lives here; nothing git-related exists in Workspace or FSNode. */
@interface GitContextMenu : NSObject <GWorkspaceExtension>
{
  NSImage *gitBadge;
  NSWindow *outputWindow;
  NSTextView *outputTextView;
}

- (NSString *)repoPathForNodes:(NSArray *)nodes;

- (void)gitStatus:(id)sender;
- (void)gitDiff:(id)sender;
- (void)gitLog:(id)sender;

- (void)runGit:(NSArray *)args title:(NSString *)title repo:(NSString *)repo;
- (void)showGitOutput:(NSString *)output title:(NSString *)title;
- (NSImage *)gitBadge;

@end
