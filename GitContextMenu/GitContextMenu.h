/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import "GWorkspaceExtension.h"
#import "FSNode.h"

/* Example GWorkspace extension: adds a "Git" submenu with a full set of
 * repository operations (status, diff, log, stage/unstage, commit, pull/push/
 * fetch, branch switch/new/delete, stash/pop, remotes, open remote, open
 * terminal) to the context menu of folders that are git repositories (contain
 * a .git directory), and offers "Initialize Repository Here" / "Clone..." on
 * plain folders.  A small badge marks git-repository folders.  All git
 * knowledge lives here; nothing git-related exists in Workspace or FSNode. */
@interface GitContextMenu : NSObject <GWorkspaceExtension>
{
  NSImage *gitBadge;
  NSWindow *outputWindow;
  NSTextView *outputTextView;
  /* Tracks in-flight git tasks keyed by their stdout file handle (which we keep
   * alive until completion).  Lets us drain output asynchronously and enforce
   * a watchdog timeout without leaking the NSTask.  Accessed from both the
   * main thread and the background read-completion thread, so guarded by
   * taskLock. */
  NSMutableDictionary *pending;
  NSLock *taskLock;
  /* Retains externally-launched, long-lived tasks (e.g. terminal emulators)
   * until they actually terminate, so releasing our reference never
   * deallocates an NSTask that is still running. */
  NSMutableArray *spawnedTasks;
}

- (NSString *)repoPathForNodes:(NSArray *)nodes;
- (NSString *)directoryForNodes:(NSArray *)nodes;

/* Repository operations. */
- (void)gitStatus:(id)sender;
- (void)gitDiff:(id)sender;
- (void)gitDiffStaged:(id)sender;
- (void)gitLog:(id)sender;
- (void)gitStageAll:(id)sender;
- (void)gitUnstageAll:(id)sender;
- (void)gitCommit:(id)sender;
- (void)gitPull:(id)sender;
- (void)gitPush:(id)sender;
- (void)gitFetch:(id)sender;
- (void)gitBranchSwitch:(id)sender;
- (void)gitBranchNew:(id)sender;
- (void)gitBranchDelete:(id)sender;
- (void)gitStash:(id)sender;
- (void)gitStashPop:(id)sender;
- (void)gitRemotes:(id)sender;
- (void)gitOpenRemote:(id)sender;
- (void)gitOpenTerminal:(id)sender;

/* Plain-folder operations. */
- (void)gitInit:(id)sender;
- (void)gitClone:(id)sender;

- (void)runGitCommand:(NSArray *)args title:(NSString *)title repo:(NSString *)repo;
- (void)runGitCommand:(NSArray *)args title:(NSString *)title repo:(NSString *)repo thenRun:(NSDictionary *)then;
- (void)showGitOutput:(NSString *)output title:(NSString *)title;
- (NSImage *)gitBadge;

@end
