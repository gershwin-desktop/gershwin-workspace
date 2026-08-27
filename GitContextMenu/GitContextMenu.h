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

  /* Cache of git folder change-counts, keyed by repo-root path (NSNumber, may
   * be 0 once known).  badgePending holds repo roots with a recompute scheduled
   * or in flight (so we neither double-schedule nor double-run).  badgeInFlight
   * / badgeDirty track in-flight recomputes that were invalidated again before
   * they finished.  All guarded by badgeLock.  Counts are computed off the main
   * thread by a single serial worker so at most one git process runs at a time
   * and opening a folder full of repositories never blocks the UI; when a count
   * is ready we post FSNBadgeCountDidChangeNotification so the icon can draw. */
  NSMutableDictionary *badgeCounts;
  NSMutableSet *badgePending;
  NSMutableSet *badgeInFlight;
  NSMutableSet *badgeDirty;
  NSLock *badgeLock;

  /* External-change watching via the shared "fswatcher" DO service.  When an
   * icon for a git repository becomes visible we register the repo root (and
   * every sub-directory) with fswatcher; on any change it calls back and we
   * recompute the count after a short quiescence window.  repoRefcounts maps
   * each watched repo root to how many visible icons reference it; watchedPaths
   * maps each watched directory to its reference count (several icons may show
   * the same repo) and dirRepoRoots maps it back to the repo root it belongs
   * to.  Guarded by watchLock. */
  id fswatcher;
  BOOL fswatcherConnected;
  BOOL fswatcherConnecting;
  BOOL fswatcherLaunched;
  NSInteger fswatcherAttempts;
  NSMutableDictionary *repoRefcounts;
  NSMutableDictionary *watchedPaths;
  NSMutableDictionary *dirRepoRoots;
  NSLock *watchLock;

  /* Debounce: scheduleRecomputeForRepo: arms (or re-arms) a per-repo timer; the
   * timer only fires 200ms after the last change, so a burst of file-system
   * events collapses into a single git run.  recomputeTimers maps repo root ->
   * NSTimer, guarded by debounceLock. */
  NSMutableDictionary *recomputeTimers;
  NSLock *debounceLock;

  /* Serial recompute worker: a single background thread drains recomputeQueue,
   * guaranteeing at most one git invocation at a time.  Guarded by recomputeCond. */
  NSMutableArray *recomputeQueue;
  NSCondition *recomputeCond;
  BOOL recomputeWorkerRunning;

  /* Timestamps (repo -> NSDate) of when we last ran git for a repo.  Used to
   * suppress the .git watch events that our own git status/diff commands cause
   * (they rewrite .git/index), which would otherwise feed an infinite loop. */
  NSMutableDictionary *lastSelfRun;
  /* Timestamps (watched dir -> NSDate) throttling directory re-scanning when
   * new sub-directories appear, so a burst of file events doesn't readdir
   * repeatedly. */
  NSMutableDictionary *lastReconcile;
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

/* Count badge (changed / unpushed file count). */
- (NSInteger)badgeCountForNode:(FSNode *)node;
- (void)invalidateBadgeForPath:(NSString *)repoRoot;

/* Begin/end watching a node's backing repository for external changes. */
- (NSString *)repoRootForNode:(FSNode *)node;
- (void)startWatchingNode:(FSNode *)node;
- (void)stopWatchingNode:(FSNode *)node;

/* fswatcher DO client (FSWClientProtocol). */
- (void)watchedPathDidChange:(NSData *)dirinfo;
- (void)globalWatchedPathDidChange:(NSDictionary *)info;

@end
