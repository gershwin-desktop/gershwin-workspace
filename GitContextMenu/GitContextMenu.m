/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

#import "GitContextMenu.h"
#import "AppearanceMetrics.h"
#import "FSNFunctions.h"
#import <AppKit/AppKit.h>

/* fswatcher.h is not imported here (it pulls in DBKit internals); we only need
 * the two protocol names to type the DO proxy and our client conformance. */
@protocol FSWatcherProtocol
- (oneway void)registerClient:(id)client isGlobalWatcher:(BOOL)global;
- (oneway void)unregisterClient:(id)client;
- (oneway void)client:(id)client addWatcherForPath:(NSString *)path;
- (oneway void)client:(id)client removeWatcherForPath:(NSString *)path;
@end

@protocol FSWClientProtocol <NSObject>
- (oneway void)watchedPathDidChange:(NSData *)dirinfo;
- (oneway void)globalWatchedPathDidChange:(NSDictionary *)info;
@end

/* How long to wait after the last file-system event before recomputing the
 * badge.  A burst of changes (e.g. a build) collapses into a single git run
 * 200ms after it settles, so idle and active CPU stay near zero. */
#define BADGE_DEBOUNCE_SECONDS 0.2

/* Hard ceiling on how long a git invocation may run before we terminate it.
 * Prevents a hanging git (e.g. prompting for credentials) from freezing the
 * UI. */
#define GIT_TIMEOUT 60.0

@implementation GitContextMenu

- (id)init
{
  self = [super init];
  if (self != nil)
    {
      badgeCounts = [[NSMutableDictionary alloc] init];
      badgePending = [[NSMutableSet alloc] init];
      badgeInFlight = [[NSMutableSet alloc] init];
      badgeDirty = [[NSMutableSet alloc] init];
      badgeLock = [[NSLock alloc] init];

      fswatcher = nil;
      fswatcherConnected = NO;
      fswatcherConnecting = NO;
      repoRefcounts = [[NSMutableDictionary alloc] init];
      watchedPaths = [[NSMutableDictionary alloc] init];
      dirRepoRoots = [[NSMutableDictionary alloc] init];
      watchLock = [[NSLock alloc] init];
      _pendingWatcherAdds = [[NSMutableArray alloc] init];
      _pendingWatcherRemoves = [[NSMutableArray alloc] init];
      _watcherFlushTimer = nil;

      recomputeTimers = [[NSMutableDictionary alloc] init];
      debounceLock = [[NSLock alloc] init];

      recomputeQueue = [[NSMutableArray alloc] init];
      recomputeCond = [[NSCondition alloc] init];
      recomputeWorkerRunning = NO;
      lastSelfRun = [[NSMutableDictionary alloc] init];
      lastReconcile = [[NSMutableDictionary alloc] init];
    }
  return self;
}

- (void)dealloc
{
  DESTROY (gitBadge);
  DESTROY (outputWindow);
  DESTROY (pending);
  DESTROY (taskLock);
  DESTROY (spawnedTasks);
  DESTROY (badgeCounts);
  DESTROY (badgePending);
  DESTROY (badgeInFlight);
  DESTROY (badgeDirty);
  DESTROY (badgeLock);
  DESTROY (fswatcher);
  DESTROY (repoRefcounts);
  DESTROY (watchedPaths);
  DESTROY (dirRepoRoots);
  DESTROY (watchLock);
  DESTROY (recomputeTimers);
  DESTROY (debounceLock);
  DESTROY (recomputeQueue);
  DESTROY (recomputeCond);
  DESTROY (lastSelfRun);
  DESTROY (lastReconcile);
  [super dealloc];
}

#pragma mark - Node selection helpers

/* A node is "handled" if any selected node is a directory.  We then decide,
 * per directory, whether it is a git repository (full menu) or a plain folder
 * (Init / Clone). */
- (BOOL)extensionCanHandleNodes:(NSArray *)nodes
{
  @try
    {
      return ([self directoryForNodes: nodes] != nil);
    }
  @catch (NSException *e)
    {
      return NO;
    }
}

- (NSString *)repoPathForNodes:(NSArray *)nodes
{
  @try
    {
      NSFileManager *fm = [NSFileManager defaultManager];
      NSUInteger i;

      for (i = 0; i < [nodes count]; i++)
        {
          FSNode *n = [nodes objectAtIndex: i];

          if ([n isDirectory])
            {
              NSString *p = [n path];
              if ([fm fileExistsAtPath: [p stringByAppendingPathComponent: @".git"]])
                {
                  return p;
                }
            }
        }
    }
  @catch (NSException *e)
    {
      NSLog (@"GitContextMenu: repoPathForNodes threw: %@", e);
    }

  return nil;
}

/* First selected directory, skipping the internal .git folder.  Works for both
 * repositories and plain folders (the latter for Init / Clone). */
- (NSString *)directoryForNodes:(NSArray *)nodes
{
  @try
    {
      NSUInteger i;
      for (i = 0; i < [nodes count]; i++)
        {
          FSNode *n = [nodes objectAtIndex: i];
          if ([n isDirectory] == NO)
            {
              continue;
            }
          NSString *p = [n path];
          if ([[p lastPathComponent] isEqualToString: @".git"])
            {
              continue;
            }
          return p;
        }
    }
  @catch (NSException *e)
    {
      NSLog (@"GitContextMenu: directoryForNodes threw: %@", e);
    }

  return nil;
}

#pragma mark - Menu assembly

- (void)addItemWithTitle:(NSString *)title
                   action:(SEL)action
                   toMenu:(NSMenu *)menu
                     repo:(NSString *)repo
{
  NSMenuItem *item = [[NSMenuItem alloc] initWithTitle: title
                                                action: action
                                         keyEquivalent: @""];
  [item setTarget: self];
  [item setRepresentedObject: repo];
  [menu addItem: item];
  RELEASE (item);
}

- (void)extensionAppendToContextMenu:(NSMenu *)menu
                            forNodes:(NSArray *)nodes
{
  @try
    {
      NSString *repo = [self repoPathForNodes: nodes];

      [menu addItem: [NSMenuItem separatorItem]];

      NSMenuItem *gitItem = [[NSMenuItem alloc] initWithTitle: @"Git"
                                                      action: nil
                                               keyEquivalent: @""];
      NSMenu *gitMenu = [[NSMenu alloc] initWithTitle: @"Git"];

      if (repo != nil)
        {
          [self addItemWithTitle: @"Status" action: @selector(gitStatus:)
                          toMenu: gitMenu repo: repo];
          [self addItemWithTitle: @"Diff" action: @selector(gitDiff:)
                          toMenu: gitMenu repo: repo];
          [self addItemWithTitle: @"Diff Staged" action: @selector(gitDiffStaged:)
                          toMenu: gitMenu repo: repo];
          [self addItemWithTitle: @"Log" action: @selector(gitLog:)
                          toMenu: gitMenu repo: repo];

          [gitMenu addItem: [NSMenuItem separatorItem]];

          [self addItemWithTitle: @"Stage All" action: @selector(gitStageAll:)
                          toMenu: gitMenu repo: repo];
          [self addItemWithTitle: @"Unstage All" action: @selector(gitUnstageAll:)
                          toMenu: gitMenu repo: repo];
          [self addItemWithTitle: @"Commit..." action: @selector(gitCommit:)
                          toMenu: gitMenu repo: repo];

          [gitMenu addItem: [NSMenuItem separatorItem]];

          [self addItemWithTitle: @"Pull" action: @selector(gitPull:)
                          toMenu: gitMenu repo: repo];
          [self addItemWithTitle: @"Push" action: @selector(gitPush:)
                          toMenu: gitMenu repo: repo];
          [self addItemWithTitle: @"Fetch" action: @selector(gitFetch:)
                          toMenu: gitMenu repo: repo];

          [gitMenu addItem: [NSMenuItem separatorItem]];

          /* Branch submenu. */
          NSMenuItem *branchItem = [[NSMenuItem alloc] initWithTitle: @"Branch"
                                                              action: nil
                                                       keyEquivalent: @""];
          NSMenu *branchMenu = [[NSMenu alloc] initWithTitle: @"Branch"];
          [self addItemWithTitle: @"Switch to Branch..." action: @selector(gitBranchSwitch:)
                          toMenu: branchMenu repo: repo];
          [self addItemWithTitle: @"New Branch..." action: @selector(gitBranchNew:)
                          toMenu: branchMenu repo: repo];
          [self addItemWithTitle: @"Delete Branch..." action: @selector(gitBranchDelete:)
                          toMenu: branchMenu repo: repo];
          [branchItem setSubmenu: branchMenu];
          RELEASE (branchMenu);
          [gitMenu addItem: branchItem];
          RELEASE (branchItem);

          [self addItemWithTitle: @"Stash" action: @selector(gitStash:)
                          toMenu: gitMenu repo: repo];
          [self addItemWithTitle: @"Pop Stash" action: @selector(gitStashPop:)
                          toMenu: gitMenu repo: repo];

          [gitMenu addItem: [NSMenuItem separatorItem]];

          [self addItemWithTitle: @"Remotes..." action: @selector(gitRemotes:)
                          toMenu: gitMenu repo: repo];
          [self addItemWithTitle: @"Open Remote" action: @selector(gitOpenRemote:)
                          toMenu: gitMenu repo: repo];
          [self addItemWithTitle: @"Open Terminal Here" action: @selector(gitOpenTerminal:)
                          toMenu: gitMenu repo: repo];
        }
      else
        {
          /* Plain folder: offer repository creation. */
          NSString *dir = [self directoryForNodes: nodes];
          [self addItemWithTitle: @"Initialize Repository Here"
                           action: @selector(gitInit:)
                           toMenu: gitMenu repo: dir];
          [self addItemWithTitle: @"Clone..." action: @selector(gitClone:)
                          toMenu: gitMenu repo: dir];
        }

      [gitItem setSubmenu: gitMenu];
      RELEASE (gitMenu);

      [menu addItem: gitItem];
      RELEASE (gitItem);
    }
  @catch (NSException *e)
    {
      NSLog (@"GitContextMenu: extensionAppendToContextMenu threw: %@", e);
    }
}

#pragma mark - Context-menu actions

- (void)gitStatus:(id)sender
{
  NSString *repo = [sender representedObject];
  [self runGitCommand: [NSArray arrayWithObjects: @"status", @"--short", nil]
                title: @"Git Status"
                 repo: repo];
}

- (void)gitDiff:(id)sender
{
  NSString *repo = [sender representedObject];
  [self runGitCommand: [NSArray arrayWithObjects: @"diff", nil]
                title: @"Git Diff"
                 repo: repo];
}

- (void)gitDiffStaged:(id)sender
{
  NSString *repo = [sender representedObject];
  [self runGitCommand: [NSArray arrayWithObjects: @"diff", @"--cached", nil]
                title: @"Git Diff (staged)"
                 repo: repo];
}

- (void)gitLog:(id)sender
{
  NSString *repo = [sender representedObject];
  [self runGitCommand: [NSArray arrayWithObjects: @"log", @"--graph",
                         @"--decorate", @"--oneline", @"-n", @"50", nil]
                title: @"Git Log"
                 repo: repo];
}

- (void)gitStageAll:(id)sender
{
  NSString *repo = [sender representedObject];
  [self runGitCommand: [NSArray arrayWithObjects: @"add", @"-A", nil]
                title: @"Git Stage All"
                 repo: repo];
}

- (void)gitUnstageAll:(id)sender
{
  NSString *repo = [sender representedObject];
  [self runGitCommand: [NSArray arrayWithObjects: @"reset", nil]
                title: @"Git Unstage All"
                 repo: repo];
}

- (void)gitCommit:(id)sender
{
  /* Defer the modal dialog off the context-menu's own modal tracking loop.
   * Starting a nested runModalForWindow: from inside that loop can deadlock or
   * crash GNUstep, so we let the menu finish and run the dialog next pass. */
  NSString *repo = [sender representedObject];
  [self performSelector: @selector (deferredCommit:)
               withObject: repo
               afterDelay: 0.0];
}

- (void)deferredCommit:(NSString *)repo
{
  @try
    {
      BOOL stageAll = NO;
      NSString *msg = [self commitDialogWithStageAll: &stageAll];

      if (msg == nil)
        {
          return;   /* cancelled or empty message */
        }

      NSArray *commitArgs = [NSArray arrayWithObjects: @"commit", @"-m", msg, nil];

      if (stageAll)
        {
          /* Chain: git add -A, then git commit -m. */
          NSDictionary *then = [NSDictionary dictionaryWithObjectsAndKeys:
            commitArgs, @"args", @"Git Commit", @"title", repo, @"repo", nil];
          [self runGitCommand: [NSArray arrayWithObjects: @"add", @"-A", nil]
                        title: @"Git Stage All"
                         repo: repo
                      thenRun: then];
        }
      else
        {
          [self runGitCommand: commitArgs title: @"Git Commit" repo: repo];
        }
    }
  @catch (NSException *e)
    {
      NSLog (@"GitContextMenu: deferredCommit threw: %@", e);
    }
}

- (void)gitPull:(id)sender
{
  NSString *repo = [sender representedObject];
  [self runGitCommand: [NSArray arrayWithObjects: @"pull", nil]
                title: @"Git Pull"
                 repo: repo];
}

- (void)gitPush:(id)sender
{
  NSString *repo = [sender representedObject];
  [self runGitCommand: [NSArray arrayWithObjects: @"push", nil]
                title: @"Git Push"
                 repo: repo];
}

- (void)gitFetch:(id)sender
{
  NSString *repo = [sender representedObject];
  [self runGitCommand: [NSArray arrayWithObjects: @"fetch", nil]
                title: @"Git Fetch"
                 repo: repo];
}

- (void)gitBranchSwitch:(id)sender
{
  NSString *repo = [sender representedObject];
  [self performSelector: @selector (deferredBranchSwitch:)
               withObject: repo
               afterDelay: 0.0];
}

- (void)deferredBranchSwitch:(NSString *)repo
{
  @try
    {
      /* Prefer a dropdown of the existing branches so the user cannot mistype
       * a name.  Fall back to a free-text prompt only if we cannot enumerate
       * the branches for some reason. */
      NSString *current = nil;
      NSArray *branches = [self gitBranchesInRepo: repo currentBranch: &current];
      if (branches == nil || [branches count] == 0)
        {
          NSString *name = [self promptWithTitle: @"Switch Branch"
                                         message: @"Check out the branch:"
                                    defaultValue: @""];
          if (name == nil)
            {
              return;
            }
          [self runGitCommand: [NSArray arrayWithObjects: @"checkout", name, nil]
                        title: [NSString stringWithFormat: @"Git Checkout %@", name]
                         repo: repo];
          return;
        }
      NSInteger idx = (current != nil) ? [branches indexOfObject: current] : NSNotFound;
      if (idx == NSNotFound || idx < 0)
        {
          idx = 0;
        }
      NSString *name = [self promptBranchWithTitle: @"Switch Branch"
                                           message: @"Check out the branch:"
                                          branches: branches
                                      defaultIndex: idx];
      if (name == nil)
        {
          return;
        }
      [self runGitCommand: [NSArray arrayWithObjects: @"checkout", name, nil]
                    title: [NSString stringWithFormat: @"Git Checkout %@", name]
                     repo: repo];
    }
  @catch (NSException *e)
    {
      NSLog (@"GitContextMenu: deferredBranchSwitch threw: %@", e);
    }
}

- (void)gitBranchNew:(id)sender
{
  NSString *repo = [sender representedObject];
  [self performSelector: @selector (deferredBranchNew:)
               withObject: repo
               afterDelay: 0.0];
}

- (void)deferredBranchNew:(NSString *)repo
{
  @try
    {
      NSString *name = [self promptWithTitle: @"New Branch"
                                     message: @"Create and check out the branch:"
                                defaultValue: @""];
      if (name == nil)
        {
          return;
        }
      [self runGitCommand: [NSArray arrayWithObjects: @"checkout", @"-b", name, nil]
                    title: [NSString stringWithFormat: @"Git Create %@", name]
                     repo: repo];
    }
  @catch (NSException *e)
    {
      NSLog (@"GitContextMenu: deferredBranchNew threw: %@", e);
    }
}

- (void)gitBranchDelete:(id)sender
{
  NSString *repo = [sender representedObject];
  [self performSelector: @selector (deferredBranchDelete:)
               withObject: repo
               afterDelay: 0.0];
}

- (void)deferredBranchDelete:(NSString *)repo
{
  @try
    {
      NSString *name = [self promptWithTitle: @"Delete Branch"
                                     message: @"Delete the branch:"
                                defaultValue: @""];
      if (name == nil)
        {
          return;
        }
      [self runGitCommand: [NSArray arrayWithObjects: @"branch", @"-d", name, nil]
                    title: [NSString stringWithFormat: @"Git Delete %@", name]
                     repo: repo];
    }
  @catch (NSException *e)
    {
      NSLog (@"GitContextMenu: deferredBranchDelete threw: %@", e);
    }
}

- (void)gitStash:(id)sender
{
  NSString *repo = [sender representedObject];
  [self runGitCommand: [NSArray arrayWithObjects: @"stash", nil]
                title: @"Git Stash"
                 repo: repo];
}

- (void)gitStashPop:(id)sender
{
  NSString *repo = [sender representedObject];
  [self runGitCommand: [NSArray arrayWithObjects: @"stash", @"pop", nil]
                title: @"Git Stash Pop"
                 repo: repo];
}

- (void)gitRemotes:(id)sender
{
  NSString *repo = [sender representedObject];
  [self runGitCommand: [NSArray arrayWithObjects: @"remote", @"-v", nil]
                title: @"Git Remotes"
                 repo: repo];
}

- (void)gitOpenRemote:(id)sender
{
  NSString *repo = [sender representedObject];
  [self launchGit: [NSArray arrayWithObjects: @"remote", @"get-url", @"origin", nil]
             title: @"Git Remote URL"
              repo: repo
           thenRun: nil
        openRemote: YES];
}

- (void)gitOpenTerminal:(id)sender
{
  NSString *repo = [sender representedObject];
  @try
    {
      NSString *term = [self findTerminal];
      if (term == nil)
        {
          [self showGitOutput: @"No terminal emulator found in PATH."
                        title: @"Open Terminal"];
          return;
        }
      NSTask *task = [[NSTask alloc] init];
      [task setLaunchPath: term];
      [task setCurrentDirectoryPath: repo];
      [task launch];

      /* Keep the task retained until it terminates.  Releasing our only
       * reference while the child is still running would deallocate the
       * NSTask, and GNUstep would then crash when it tries to notify the
       * (freed) task on child exit. */
      [taskLock lock];
      if (spawnedTasks == nil)
        {
          spawnedTasks = [[NSMutableArray alloc] init];
        }
      [spawnedTasks addObject: task];
      [taskLock unlock];

      [[NSNotificationCenter defaultCenter]
        addObserver: self
           selector: @selector (gitSpawnedTaskDidTerminate:)
               name: NSTaskDidTerminateNotification
             object: task];
      RELEASE (task);
    }
  @catch (NSException *e)
    {
      [self showGitOutput: [NSString stringWithFormat:
                             @"Could not open a terminal: %@",
                             [e description]]
                        title: @"Open Terminal"];
    }
}

- (void)gitSpawnedTaskDidTerminate:(NSNotification *)note
{
  @try
    {
      NSTask *task = [note object];
      [[NSNotificationCenter defaultCenter]
        removeObserver: self
                  name: NSTaskDidTerminateNotification
                object: task];
      [taskLock lock];
      [spawnedTasks removeObject: task];
      [taskLock unlock];
    }
  @catch (NSException *e)
    {
      NSLog (@"GitContextMenu: gitSpawnedTaskDidTerminate threw: %@", e);
    }
}

- (void)gitInit:(id)sender
{
  NSString *repo = [sender representedObject];
  [self runGitCommand: [NSArray arrayWithObjects: @"init", nil]
                title: @"Git Init"
                 repo: repo];
}

- (void)gitClone:(id)sender
{
  NSString *repo = [sender representedObject];
  [self performSelector: @selector (deferredClone:)
               withObject: repo
               afterDelay: 0.0];
}

- (void)deferredClone:(NSString *)repo
{
  @try
    {
      NSString *url = [self promptWithTitle: @"Clone Repository"
                                    message: @"Repository URL to clone into this folder:"
                               defaultValue: @""];
      if (url == nil)
        {
          return;
        }
      [self runGitCommand: [NSArray arrayWithObjects: @"clone", url, nil]
                    title: [NSString stringWithFormat: @"Git Clone %@", url]
                     repo: repo];
    }
  @catch (NSException *e)
    {
      NSLog (@"GitContextMenu: deferredClone threw: %@", e);
    }
}

#pragma mark - Dialogs

/* End a custom modal dialog (see promptWithTitle:/commitDialogWithStageAll:).
 * GNUstep's NSAlert does not implement -setAccessoryView:, so we build our own
 * modal windows and drive them with -runModalForWindow:. */
- (void)stopModalOK:(id)sender
{
  [NSApp stopModalWithCode: 1];
}

- (void)stopModalCancel:(id)sender
{
  [NSApp stopModalWithCode: 0];
}

/* Synchronous (runs on the main thread, invoked from a deferred action).
 * Returns the entered string, or nil if cancelled / empty.  Layout follows
 * AppearanceMetrics.h: 24px side / 15px top / 20px bottom margins, 22px text
 * fields, 20px buttons, OK at lower-right with Cancel to its left. */
- (NSString *)promptWithTitle:(NSString *)title
                      message:(NSString *)message
                 defaultValue:(NSString *)def
{
  @try
    {
      const CGFloat side = METRICS_CONTENT_SIDE_MARGIN;             /* 24 */
      const CGFloat top = METRICS_CONTENT_TOP_MARGIN;               /* 15 */
      const CGFloat bottom = METRICS_CONTENT_BOTTOM_MARGIN;         /* 20 */
      const CGFloat msgH = 44.0;
      const CGFloat fieldH = METRICS_TEXT_INPUT_FIELD_HEIGHT;       /* 22 */
      const CGFloat btnH = METRICS_BUTTON_HEIGHT;                   /* 20 */
      const CGFloat cw = 360.0 + 2.0 * side;                       /* 408 */
      const CGFloat ch = top + msgH + METRICS_SPACE_16
                       + fieldH + METRICS_SPACE_16 + btnH + bottom; /* 153 */

      NSWindow *win = [[NSWindow alloc]
        initWithContentRect: NSMakeRect (0, 0, cw, ch)
                  styleMask: NSTitledWindowMask
                    backing: NSBackingStoreBuffered
                      defer: NO];
      [win setTitle: title];
      NSView *cv = [win contentView];
      const CGFloat aw = cw - 2.0 * side;

      NSTextField *msg =
        [[NSTextField alloc] initWithFrame:
          NSMakeRect (side, ch - top - msgH, aw, msgH)];
      [msg setStringValue: message];
      [msg setEditable: NO];
      [msg setSelectable: NO];
      [msg setDrawsBackground: NO];
      [msg setBezeled: NO];
      [[msg cell] setWraps: YES];
      [msg setFont: METRICS_FONT_SYSTEM_REGULAR_13];
      [msg setAutoresizingMask: NSViewWidthSizable | NSViewMinYMargin];
      [cv addSubview: msg];

      NSTextField *field =
        [[NSTextField alloc] initWithFrame:
          NSMakeRect (side, ch - top - msgH - METRICS_SPACE_16 - fieldH, aw, fieldH)];
      [field setStringValue: (def ? def : @"")];
      [field setFont: METRICS_FONT_SYSTEM_REGULAR_13];
      [field setAutoresizingMask: NSViewWidthSizable | NSViewMinYMargin];
      [cv addSubview: field];

      const CGFloat btnW = METRICS_BUTTON_MIN_WIDTH;               /* 100 */

      NSButton *ok =
        [[NSButton alloc] initWithFrame:
          NSMakeRect (cw - side - btnW, bottom, btnW, btnH)];
      [ok setTitle: @"OK"];
      [ok setKeyEquivalent: @"\r"];
      [ok setTarget: self];
      [ok setAction: @selector (stopModalOK:)];
      [ok setAutoresizingMask: NSViewMinXMargin | NSViewMaxYMargin];
      [cv addSubview: ok];

      NSButton *cancel =
        [[NSButton alloc] initWithFrame:
          NSMakeRect (cw - side - 2.0 * btnW - METRICS_BUTTON_HORIZ_INTERSPACE,
                      bottom, btnW, btnH)];
      [cancel setTitle: @"Cancel"];
      [cancel setTarget: self];
      [cancel setAction: @selector (stopModalCancel:)];
      [cancel setKeyEquivalent: @"\033"];
      [cancel setAutoresizingMask: NSViewMinXMargin | NSViewMaxYMargin];
      [cv addSubview: cancel];

      [win makeKeyAndOrderFront: nil];
      NSInteger rc = [NSApp runModalForWindow: win];

      NSString *result = nil;
      if (rc == 1)
        {
          NSString *v = [field stringValue];
          if ([v length] > 0)
            {
              result = AUTORELEASE ([v copy]);
            }
        }

      /* The modal session has ended but the window is still on screen.  Pull it
       * off-screen now so it disappears regardless of whether the surrounding
       * run loop drains an autorelease pool.  Keep the window alive via
       * autorelease: runModalForWindow: leaves it on screen and the mouse event
       * that triggered Cancel is still queued and targets this window, so
       * releasing it now would free it while that event is unprocessed and
       * crash on a later access. */
      [win orderOut: nil];

      RELEASE (cancel);
      RELEASE (ok);
      RELEASE (field);
      RELEASE (msg);
      AUTORELEASE (win);
      return result;
    }
  @catch (NSException *e)
    {
      return nil;
    }
}

/* Commit dialog: an informative label, a "stage all first" checkbox, and a
 * multiline message view.  Returns the message (copied, autoreleased) or nil if
 * cancelled / empty.  Layout follows AppearanceMetrics.h (24/15/20 margins,
 * 22px fields, 20px buttons, OK lower-right with Cancel to its left). */
- (NSString *)commitDialogWithStageAll:(BOOL *)stageAllOut
{
  @try
    {
      const CGFloat side = METRICS_CONTENT_SIDE_MARGIN;             /* 24 */
      const CGFloat top = METRICS_CONTENT_TOP_MARGIN;               /* 15 */
      const CGFloat bottom = METRICS_CONTENT_BOTTOM_MARGIN;         /* 20 */
      const CGFloat msgH = 22.0;
      const CGFloat cbH = METRICS_RADIO_BUTTON_SIZE;                /* 18 */
      const CGFloat tvH = 120.0;
      const CGFloat btnH = METRICS_BUTTON_HEIGHT;                   /* 20 */
      const CGFloat cw = 400.0 + 2.0 * side;                       /* 448 */
      const CGFloat ch = top + msgH + METRICS_SPACE_16 + cbH
                       + METRICS_SPACE_16 + tvH + METRICS_SPACE_16
                       + btnH + bottom;                             /* 263 */

      NSWindow *win = [[NSWindow alloc]
        initWithContentRect: NSMakeRect (0, 0, cw, ch)
                  styleMask: NSTitledWindowMask
                    backing: NSBackingStoreBuffered
                      defer: NO];
      [win setTitle: @"Commit Changes"];
      NSView *cv = [win contentView];
      const CGFloat aw = cw - 2.0 * side;

      NSTextField *msg =
        [[NSTextField alloc] initWithFrame:
          NSMakeRect (side, ch - top - msgH, aw, msgH)];
      [msg setStringValue: @"Enter a commit message."];
      [msg setEditable: NO];
      [msg setSelectable: NO];
      [msg setDrawsBackground: NO];
      [msg setBezeled: NO];
      [msg setFont: METRICS_FONT_SYSTEM_REGULAR_13];
      [msg setAutoresizingMask: NSViewWidthSizable | NSViewMinYMargin];
      [cv addSubview: msg];

      NSButton *cb =
        [[NSButton alloc] initWithFrame:
          NSMakeRect (side, ch - top - msgH - METRICS_SPACE_16 - cbH, aw, cbH)];
      [cb setButtonType: NSSwitchButton];
      [cb setTitle: @"Stage all changes first (git add -A)"];
      [cb setState: NSOnState];
      [cb setFont: METRICS_FONT_SYSTEM_REGULAR_13];
      [cb setAutoresizingMask: NSViewWidthSizable | NSViewMinYMargin];
      [cv addSubview: cb];

      NSScrollView *scroll =
        [[NSScrollView alloc] initWithFrame:
          NSMakeRect (side, ch - top - msgH - METRICS_SPACE_16 - cbH
                      - METRICS_SPACE_16 - tvH, aw, tvH)];
      [scroll setHasVerticalScroller: YES];
      [scroll setHasHorizontalScroller: NO];
      NSTextView *tv =
        [[NSTextView alloc] initWithFrame: NSMakeRect (0, 0, aw, tvH)];
      [tv setVerticallyResizable: YES];
      [tv setMinSize: NSMakeSize (aw, tvH)];
      [tv setMaxSize: NSMakeSize (aw, 100000)];
      [tv setFont: METRICS_FONT_SYSTEM_REGULAR_13];
      [scroll setDocumentView: tv];
      [scroll setAutoresizingMask: NSViewWidthSizable | NSViewMinYMargin];
      [cv addSubview: scroll];

      const CGFloat btnW = METRICS_BUTTON_MIN_WIDTH;               /* 100 */

      NSButton *ok =
        [[NSButton alloc] initWithFrame:
          NSMakeRect (cw - side - btnW, bottom, btnW, btnH)];
      [ok setTitle: @"Commit"];
      [ok setKeyEquivalent: @"\r"];
      [ok setTarget: self];
      [ok setAction: @selector (stopModalOK:)];
      [ok setAutoresizingMask: NSViewMinXMargin | NSViewMaxYMargin];
      [cv addSubview: ok];

      NSButton *cancel =
        [[NSButton alloc] initWithFrame:
          NSMakeRect (cw - side - 2.0 * btnW - METRICS_BUTTON_HORIZ_INTERSPACE,
                      bottom, btnW, btnH)];
      [cancel setTitle: @"Cancel"];
      [cancel setTarget: self];
      [cancel setAction: @selector (stopModalCancel:)];
      [cancel setKeyEquivalent: @"\033"];
      [cancel setAutoresizingMask: NSViewMinXMargin | NSViewMaxYMargin];
      [cv addSubview: cancel];

      [win makeKeyAndOrderFront: nil];
      NSInteger rc = [NSApp runModalForWindow: win];

      BOOL stageAll = ([cb state] == NSOnState);
      NSString *msgText = nil;
      if (rc == 1)
        {
          NSString *v = [tv string];
          if ([v length] > 0)
            {
              msgText = AUTORELEASE ([v copy]);
            }
        }

      if (stageAllOut)
        {
          *stageAllOut = stageAll;
        }

      /* The modal session has ended but the window is still on screen.  Pull it
       * off-screen now so it disappears regardless of whether the surrounding
       * run loop drains an autorelease pool. */
      [win orderOut: nil];

      RELEASE (cancel);
      RELEASE (ok);
      RELEASE (tv);
      RELEASE (scroll);
      RELEASE (cb);
      RELEASE (msg);
      /* Keep the window alive until the run loop drains the queued mouse event
       * that dismissed the dialog. */
      AUTORELEASE (win);
      return msgText;
    }
  @catch (NSException *e)
    {
      return nil;
    }
}

/* Enumerate the local branches of a repository.  Returns an array of branch
 * names (no markers), or nil on failure.  If currentOut is non-NULL it is set
 * to the name of the currently checked-out branch (or nil). */
- (NSArray *)gitBranchesInRepo:(NSString *)repo
                 currentBranch:(NSString **)currentOut
{
  if (currentOut != NULL)
    {
      *currentOut = nil;
    }
  NSTask *task = [[NSTask alloc] init];
  [task setLaunchPath: @"/usr/bin/git"];
  [task setArguments: [NSArray arrayWithObjects: @"for-each-ref",
                       @"--format=%(refname:short)", @"refs/heads/", nil]];
  [task setCurrentDirectoryPath: repo];
  NSPipe *outPipe = [NSPipe pipe];
  [task setStandardOutput: outPipe];
  [task setStandardError: [NSPipe pipe]];
  @try
    {
      [task launch];
    }
  @catch (NSException *e)
    {
      RELEASE (task);
      return nil;
    }
  NSData *data = [[outPipe fileHandleForReading] readDataToEndOfFile];
  [task waitUntilExit];
  NSInteger status = [task terminationStatus];
  RELEASE (task);
  if (status != 0)
    {
      return nil;
    }
  NSString *s = [[NSString alloc] initWithData: data encoding: NSUTF8StringEncoding];
  NSArray *lines = [s componentsSeparatedByString: @"\n"];
  RELEASE (s);
  NSMutableArray *branches = [NSMutableArray array];
  for (NSString *line in lines)
    {
      NSString *b = [line stringByTrimmingCharactersInSet:
                       [NSCharacterSet whitespaceAndNewlineCharacterSet]];
      if ([b length] > 0)
        {
          [branches addObject: b];
        }
    }

  if (currentOut != NULL)
    {
      NSTask *t2 = [[NSTask alloc] init];
      [t2 setLaunchPath: @"/usr/bin/git"];
      [t2 setArguments: [NSArray arrayWithObjects: @"rev-parse",
                         @"--abbrev-ref", @"HEAD", nil]];
      [t2 setCurrentDirectoryPath: repo];
      NSPipe *o2 = [NSPipe pipe];
      [t2 setStandardOutput: o2];
      [t2 setStandardError: [NSPipe pipe]];
      @try
        {
          [t2 launch];
          NSData *d2 = [[o2 fileHandleForReading] readDataToEndOfFile];
          [t2 waitUntilExit];
          if ([t2 terminationStatus] == 0)
            {
              NSString *raw = [[NSString alloc]
                initWithData: d2 encoding: NSUTF8StringEncoding];
              NSString *cur = [raw stringByTrimmingCharactersInSet:
                [NSCharacterSet whitespaceAndNewlineCharacterSet]];
              RELEASE (raw);
              if ([cur length] > 0)
                {
                  *currentOut = AUTORELEASE ([cur copy]);
                }
            }
        }
      @catch (NSException *e)
        {
          /* leave currentOut as nil */
        }
      RELEASE (t2);
    }

  return branches;
}

/* Branch picker dialog: a message plus a dropdown (NSPopUpButton) of the
 * existing branches, with OK/Cancel.  Returns the selected branch name
 * (copied, autoreleased) or nil if cancelled.  Layout follows
 * AppearanceMetrics.h. */
- (NSString *)promptBranchWithTitle:(NSString *)title
                            message:(NSString *)message
                           branches:(NSArray *)branches
                       defaultIndex:(NSInteger)defaultIndex
{
  @try
    {
      const CGFloat side = METRICS_CONTENT_SIDE_MARGIN;             /* 24 */
      const CGFloat top = METRICS_CONTENT_TOP_MARGIN;               /* 15 */
      const CGFloat bottom = METRICS_CONTENT_BOTTOM_MARGIN;         /* 20 */
      const CGFloat msgH = 44.0;
      const CGFloat popupH = 26.0;
      const CGFloat btnH = METRICS_BUTTON_HEIGHT;                   /* 20 */
      const CGFloat cw = 360.0 + 2.0 * side;                       /* 408 */
      const CGFloat ch = top + msgH + METRICS_SPACE_16
                       + popupH + METRICS_SPACE_16 + btnH + bottom;

      NSWindow *win = [[NSWindow alloc]
        initWithContentRect: NSMakeRect (0, 0, cw, ch)
                  styleMask: NSTitledWindowMask
                    backing: NSBackingStoreBuffered
                      defer: NO];
      [win setTitle: title];
      NSView *cv = [win contentView];
      const CGFloat aw = cw - 2.0 * side;

      NSTextField *msg =
        [[NSTextField alloc] initWithFrame:
          NSMakeRect (side, ch - top - msgH, aw, msgH)];
      [msg setStringValue: message];
      [msg setEditable: NO];
      [msg setSelectable: NO];
      [msg setDrawsBackground: NO];
      [msg setBezeled: NO];
      [[msg cell] setWraps: YES];
      [msg setFont: METRICS_FONT_SYSTEM_REGULAR_13];
      [msg setAutoresizingMask: NSViewWidthSizable | NSViewMinYMargin];
      [cv addSubview: msg];

      NSPopUpButton *popup =
        [[NSPopUpButton alloc] initWithFrame:
          NSMakeRect (side, bottom + btnH + METRICS_SPACE_16, aw, popupH)
                                   pullsDown: NO];
      [popup setFont: METRICS_FONT_SYSTEM_REGULAR_13];
      for (NSString *b in branches)
        {
          [popup addItemWithTitle: b];
        }
      if (defaultIndex >= 0 && defaultIndex < (NSInteger) [branches count])
        {
          [popup selectItemAtIndex: defaultIndex];
        }
      [popup setAutoresizingMask: NSViewWidthSizable | NSViewMinYMargin];
      [cv addSubview: popup];

      const CGFloat btnW = METRICS_BUTTON_MIN_WIDTH;               /* 100 */

      NSButton *ok =
        [[NSButton alloc] initWithFrame:
          NSMakeRect (cw - side - btnW, bottom, btnW, btnH)];
      [ok setTitle: @"OK"];
      [ok setKeyEquivalent: @"\r"];
      [ok setTarget: self];
      [ok setAction: @selector (stopModalOK:)];
      [ok setAutoresizingMask: NSViewMinXMargin | NSViewMaxYMargin];
      [cv addSubview: ok];

      NSButton *cancel =
        [[NSButton alloc] initWithFrame:
          NSMakeRect (cw - side - 2.0 * btnW - METRICS_BUTTON_HORIZ_INTERSPACE,
                      bottom, btnW, btnH)];
      [cancel setTitle: @"Cancel"];
      [cancel setTarget: self];
      [cancel setAction: @selector (stopModalCancel:)];
      [cancel setKeyEquivalent: @"\033"];
      [cancel setAutoresizingMask: NSViewMinXMargin | NSViewMaxYMargin];
      [cv addSubview: cancel];

      [win makeKeyAndOrderFront: nil];
      NSInteger rc = [NSApp runModalForWindow: win];

      NSString *result = nil;
      if (rc == 1)
        {
          NSString *sel = [popup titleOfSelectedItem];
          if ([sel length] > 0)
            {
              result = AUTORELEASE ([sel copy]);
            }
        }

      /* The modal session has ended but the window is still on screen.  Pull it
       * off-screen now so it disappears regardless of whether the surrounding
       * run loop drains an autorelease pool.  Keep the window alive via
       * autorelease: runModalForWindow: leaves it on screen and the mouse event
       * that triggered Cancel is still queued and targets this window, so
       * releasing it now would free it while that event is unprocessed and
       * crash on a later access. */
      [win orderOut: nil];

      RELEASE (cancel);
      RELEASE (ok);
      RELEASE (popup);
      RELEASE (msg);
      AUTORELEASE (win);
      return result;
    }
  @catch (NSException *e)
    {
      return nil;
    }
}

#pragma mark - Environment helpers

/* Locate the git binary ourselves.  NSTask needs an absolute launch path, and
 * we must not assume /usr/bin/git exists on every platform.  Failing to find
 * it must never crash - we just report it in the output window. */
- (NSString *)gitLaunchPath
{
  NSFileManager *fm = [NSFileManager defaultManager];
  NSString *pathEnv = [[[NSProcessInfo processInfo] environment] objectForKey: @"PATH"];
  NSArray *dirs = [pathEnv componentsSeparatedByString: @":"];
  NSUInteger i;

  for (i = 0; i < [dirs count]; i++)
    {
      NSString *p = [[dirs objectAtIndex: i] stringByAppendingPathComponent: @"git"];
      if ([p length] > 0 && [fm isExecutableFileAtPath: p])
        {
          return p;
        }
    }

  if ([fm isExecutableFileAtPath: @"/usr/bin/git"])
    {
      return @"/usr/bin/git";
    }
  if ([fm isExecutableFileAtPath: @"/usr/local/bin/git"])
    {
      return @"/usr/local/bin/git";
    }

  return nil;
}

/* Best-effort terminal emulator discovery.  We launch it with
 * setCurrentDirectoryPath: so it opens in the repo, avoiding per-terminal
 * flag differences. */
- (NSString *)findTerminal
{
  NSFileManager *fm = [NSFileManager defaultManager];
  NSString *pathEnv = [[[NSProcessInfo processInfo] environment] objectForKey: @"PATH"];
  NSArray *dirs = [pathEnv componentsSeparatedByString: @":"];
  NSArray *candidates = [NSArray arrayWithObjects:
    @"gnome-terminal", @"konsole", @"xfce4-terminal", @"lxterminal",
    @"mate-terminal", @"terminator", @"alacritty", @"kitty", @"foot",
    @"st", @"rxvt", @"urxvt", @"xterm", nil];
  NSUInteger i, j;

  for (i = 0; i < [candidates count]; i++)
    {
      NSString *name = [candidates objectAtIndex: i];
      for (j = 0; j < [dirs count]; j++)
        {
          NSString *p = [[dirs objectAtIndex: j] stringByAppendingPathComponent: name];
          if ([p length] > 0 && [fm isExecutableFileAtPath: p])
            {
              return p;
            }
        }
    }

  return nil;
}

/* Turn a git remote URL into something a browser can open.  Handles the
 * common scp-like (git@host:path) and ssh:// forms; leaves http(s) alone. */
- (NSString *)browserURLFromRemote:(NSString *)remote
{
  if (remote == nil)
    {
      return nil;
    }

  NSString *s = [remote stringByTrimmingCharactersInSet:
    [NSCharacterSet whitespaceAndNewlineCharacterSet]];
  if ([s hasSuffix: @"/"])
    {
      s = [s substringToIndex: [s length] - 1];
    }
  if ([s hasSuffix: @".git"])
    {
      s = [s substringToIndex: [s length] - 4];
    }

  if ([s hasPrefix: @"git@"])
    {
      /* git@host:path -> https://host/path */
      NSString *rest = [s substringFromIndex: 4];
      NSRange colon = [rest rangeOfString: @":"];
      if (colon.location != NSNotFound)
        {
          NSString *host = [rest substringToIndex: colon.location];
          NSString *path = [rest substringFromIndex: colon.location + 1];
          s = [NSString stringWithFormat: @"https://%@/%@", host, path];
        }
    }
  else if ([s hasPrefix: @"ssh://"])
    {
      NSString *rest = [s substringFromIndex: 6];
      NSRange at = [rest rangeOfString: @"@"];
      if (at.location != NSNotFound)
        {
          rest = [rest substringFromIndex: at.location + 1];
        }
      s = [NSString stringWithFormat: @"https://%@", rest];
    }

  return s;
}

#pragma mark - Async git runner

- (void)runGitCommand:(NSArray *)args title:(NSString *)title repo:(NSString *)repo
{
  [self launchGit: args title: title repo: repo thenRun: nil openRemote: NO];
}

- (void)runGitCommand:(NSArray *)args title:(NSString *)title repo:(NSString *)repo thenRun:(NSDictionary *)then
{
  [self launchGit: args title: title repo: repo thenRun: then openRemote: NO];
}

/* Run git and present its output.  Crucially we read the child's output
 * asynchronously: reading the pipe only after waitUntilExit deadlocks once the
 * output exceeds the pipe buffer, which hangs (and on GNUstep crashes) the
 * main thread.  Everything here is wrapped so the bundle can never take down
 * Workspace.  `then` (optional) chains a second command on success;
 * `openRemote` (optional) parses the output as a remote URL and opens it
 * instead of showing it. */
- (void)launchGit:(NSArray *)args title:(NSString *)title repo:(NSString *)repo thenRun:(NSDictionary *)then openRemote:(BOOL)openRemote
{
  @try
    {
      NSString *git = [self gitLaunchPath];

      if (git == nil)
        {
          [self showGitOutput: @"git was not found in PATH." title: title];
          return;
        }
      if (repo == nil || [[NSFileManager defaultManager] fileExistsAtPath: repo] == NO)
        {
          [self showGitOutput: @"The repository path is no longer valid."
                        title: title];
          return;
        }

      NSTask *task = [[NSTask alloc] init];
      [task setLaunchPath: git];
      [task setArguments: args];
      [task setCurrentDirectoryPath: repo];

      NSPipe *pipe = [NSPipe pipe];
      [task setStandardOutput: pipe];
      [task setStandardError: pipe];

      NSFileHandle *readHandle = [pipe fileHandleForReading];
      NSValue *key = [NSValue valueWithNonretainedObject: readHandle];

      if (taskLock == nil)
        {
          taskLock = [[NSLock alloc] init];
        }
      if (pending == nil)
        {
          pending = [[NSMutableDictionary alloc] init];
        }

      NSMutableDictionary *info = [NSMutableDictionary dictionaryWithObjectsAndKeys:
        title, @"title", task, @"task", readHandle, @"handle",
        [NSNumber numberWithBool: NO], @"done", nil];
      if (then != nil)
        {
          [info setObject: then forKey: @"then"];
        }
      if (repo != nil)
        {
          [info setObject: repo forKey: @"repo"];
        }
      [info setObject: [NSNumber numberWithBool: openRemote] forKey: @"openRemote"];

      /* Serialize access: gitReadCompleted: runs on a background read thread
       * and also touches pending, so every mutation must be locked. */
      [taskLock lock];
      [pending setObject: info forKey: key];
      [taskLock unlock];

      /* Drain the pipe on a dedicated background thread.  We deliberately do
       * NOT use NSFileHandleReadToEndOfFileCompletionNotification: GNUstep
       * posts that notification from a background read thread, and our old
       * code removed the observer from that same background thread.
       * NSNotificationCenter is not safe to mutate (addObserver runs on the
       * main thread in launchGit:, removeObserver on the read thread) from
       * two threads, so the second git command's addObserver raced the first
       * command's background-thread removeObserver and corrupted the center,
       * crashing on the second invocation.  A plain read thread hands its
       * result back to the main thread, so all pending/lock bookkeeping stays
       * on the main thread. */
      [NSThread detachNewThreadSelector: @selector(readGitOutputThread:)
                               toTarget: self
                             withObject: [NSDictionary dictionaryWithObjectsAndKeys:
                                           readHandle, @"handle", key, @"key", nil]];

      [task launch];

      NSTimer *timer = [NSTimer scheduledTimerWithTimeInterval: GIT_TIMEOUT
                                                        target: self
                                                      selector: @selector(gitTimeout:)
                                                      userInfo: key
                                                       repeats: NO];
      [info setObject: timer forKey: @"timer"];
    }
  @catch (NSException *e)
    {
      [self showGitOutput: [NSString stringWithFormat: @"Failed to run git: %@",
                             [e description]]
                    title: title];
    }
}

- (void)readGitOutputThread:(NSDictionary *)args
{
  /* Runs on a detached background thread.  Its only job is to block on the
   * pipe until EOF (or the watchdog terminates the task, which closes the
   * pipe), then hand the bytes back to the main thread.  It must not touch
   * pending, the lock, or NSNotificationCenter - all of that happens on the
   * main thread in gitReadThreadDone:. */
  NSAutoreleasePool *pool = [NSAutoreleasePool new];
  NSFileHandle *readHandle = [args objectForKey: @"handle"];
  NSValue *key = [args objectForKey: @"key"];
  NSData *data = nil;

  @try
    {
      data = [readHandle readDataToEndOfFile];
    }
  @catch (NSException *e)
    {
      data = nil;
    }
  if (data == nil)
    {
      data = [NSData data];
    }

  [self performSelectorOnMainThread: @selector (gitReadThreadDone:)
                         withObject: [NSDictionary dictionaryWithObjectsAndKeys:
                                       data, @"data", key, @"key", nil]
                      waitUntilDone: NO];
  [pool release];
}

- (void)gitReadThreadDone:(NSDictionary *)args
{
  /* Runs on the main thread.  Because the result is delivered here (not from
   * a background-thread NSNotificationCenter callback), all access to pending
   * and taskLock stays on the main thread - no cross-thread center mutation,
   * no re-entrancy, no corruption across multiple git commands. */
  NSData *data = [args objectForKey: @"data"];
  NSValue *key = [args objectForKey: @"key"];

  [taskLock lock];
  @try
    {
      NSMutableDictionary *info = [pending objectForKey: key];
      if (info == nil)
        {
          return;
        }
      if ([[info objectForKey: @"done"] boolValue])
        {
          return;
        }
      [info setObject: [NSNumber numberWithBool: YES] forKey: @"done"];

      /* Retain everything we still need BEFORE removing info from pending:
       * once pending releases info, the objects it holds are freed, and
       * touching them would be a use-after-free crash. */
      NSString *title = [[info objectForKey: @"title"] retain];
      BOOL openRemote = [[info objectForKey: @"openRemote"] boolValue];
      NSDictionary *then = [[info objectForKey: @"then"] retain];
      NSTimer *timer = [[info objectForKey: @"timer"] retain];
      NSTask *task = [info objectForKey: @"task"];
      NSString *repo = [[info objectForKey: @"repo"] retain];
      int status = 0;
      if (task != nil && [task isRunning] == NO)
        {
          @try { status = [task terminationStatus]; } @catch (NSException *e) { status = 0; }
        }

      NSMutableDictionary *result = [NSMutableDictionary dictionaryWithObjectsAndKeys:
        [self stringFromData: data], @"output",
        (title ? title : (NSString *)@"git"), @"title",
        [NSNumber numberWithBool: openRemote], @"openRemote",
        [NSNumber numberWithInt: status], @"status", nil];
      if (then != nil)
        {
          [result setObject: then forKey: @"then"];
        }
      if (repo != nil)
        {
          [result setObject: repo forKey: @"repo"];
        }

      [pending removeObjectForKey: key];

      if (timer != nil)
        {
          [timer invalidate];
        }
      [timer release];
      [then release];
      [title release];
      [repo release];
      /* task is released when info is removed from pending; do not touch it. */

      [self performSelectorOnMainThread: @selector (deliverGitResult:)
                             withObject: result
                          waitUntilDone: NO];
    }
  @catch (NSException *e)
    {
      NSLog (@"GitContextMenu: gitReadThreadDone threw: %@\n%@",
             [e description], [e callStackSymbols]);
    }
  @finally
    {
      [taskLock unlock];
    }
}

- (void)gitTimeout:(NSTimer *)timer
{
  /* gitTimeout: runs on the main thread (the watchdog timer).  It races
   * gitReadThreadDone: (also main thread) only via the "done" flag, which is
   * guarded by taskLock. */
  NSValue *key = [timer userInfo];

  [taskLock lock];
  NSMutableDictionary *info = [pending objectForKey: key];
  if (info == nil)
    {
      [taskLock unlock];
      return;
    }
  if ([[info objectForKey: @"done"] boolValue])
    {
      [taskLock unlock];
      return;
    }
  [info setObject: [NSNumber numberWithBool: YES] forKey: @"done"];

  /* Retain before removing info from pending (see gitReadThreadDone:). */
  NSString *title = [[info objectForKey: @"title"] retain];
  NSTask *task = [[info objectForKey: @"task"] retain];

  [pending removeObjectForKey: key];
  [taskLock unlock];

  @try
    {
      if (task != nil && [task isRunning])
        {
          [task terminate];
        }
    }
  @catch (NSException *e)
    {
      /* ignore - we are tearing the task down anyway */
    }

  [self showGitOutput: @"(git did not finish within the time limit)"
                 title: (title ? title : (NSString *)@"git")];

  [task release];
  [title release];
}

/* Runs on the main thread (invoked via performSelectorOnMainThread from
 * gitReadThreadDone:).  All UI and any follow-up tasks happen here. */
- (void)deliverGitResult:(NSDictionary *)result
{
  @try
    {
      BOOL openRemote = [[result objectForKey: @"openRemote"] boolValue];
      NSString *output = [result objectForKey: @"output"];
      NSString *title = [result objectForKey: @"title"];
      int status = [[result objectForKey: @"status"] intValue];
      NSDictionary *then = [result objectForKey: @"then"];

      if (openRemote)
        {
          [self handleRemoteOutput: output title: title];
          return;
        }

      /* Chain a follow-up command on success. */
      if (then != nil && status == 0)
        {
          [self launchGit: [then objectForKey: @"args"]
                     title: [then objectForKey: @"title"]
                      repo: [then objectForKey: @"repo"]
                   thenRun: [then objectForKey: @"then"]
                 openRemote: NO];
        }

      /* A successful git mutation just changed this repository's state, so drop
       * the cached badge count and let the debounced pipeline refresh it. */
      if (status == 0)
        {
          NSString *repo = [result objectForKey: @"repo"];
          if (repo != nil)
            {
              [self invalidateBadgeForPath: repo];
            }
        }

      [self showGitOutput: output title: title];
    }
  @catch (NSException *e)
    {
      NSLog (@"GitContextMenu: deliverGitResult threw: %@", e);
    }
}

- (void)handleRemoteOutput:(NSString *)output title:(NSString *)title
{
  @try
    {
      NSString *line = [self firstNonBlankLine: output];
      NSString *url = [self browserURLFromRemote: line];

      if (url == nil)
        {
          [self showGitOutput: output title: title];
          return;
        }

      NSURL *u = [NSURL URLWithString: url];
      if (u == nil)
        {
          [self showGitOutput: output title: title];
          return;
        }

      BOOL ok = NO;
      @try
        {
          ok = [[NSWorkspace sharedWorkspace] openURL: u];
        }
      @catch (NSException *e)
        {
          ok = NO;
        }

      if (ok == NO)
        {
          [self showGitOutput: output title: title];
        }
    }
  @catch (NSException *e)
    {
      [self showGitOutput: output title: title];
    }
}

- (NSString *)firstNonBlankLine:(NSString *)text
{
  NSArray *lines = [text componentsSeparatedByString: @"\n"];
  NSUInteger i;
  for (i = 0; i < [lines count]; i++)
    {
      NSString *l = [[lines objectAtIndex: i]
        stringByTrimmingCharactersInSet:
          [NSCharacterSet whitespaceAndNewlineCharacterSet]];
      if ([l length] > 0)
        {
          return l;
        }
    }
  return nil;
}

- (NSString *)stringFromData:(NSData *)data
{
  if (data == nil || [data length] == 0)
    {
      return @"(no output)";
    }

  NSString *s = [[NSString alloc] initWithData: data encoding: NSUTF8StringEncoding];
  if (s == nil)
    {
      /* Fall back to Latin-1 so we never hand NSTextView nil for binary-ish
       * output. */
      s = [[NSString alloc] initWithData: data encoding: NSISOLatin1StringEncoding];
    }
  if (s == nil)
    {
      s = (NSString *)@"";
    }
  return AUTORELEASE (s);
}

- (NSWindow *)outputWindow
{
  @try
    {
      if (outputWindow == nil)
        {
          NSRect contentRect = NSMakeRect (0, 0, 600, 400);

          outputWindow = [[NSWindow alloc] initWithContentRect: contentRect
                                                      styleMask: (NSTitledWindowMask
                                                                  | NSClosableWindowMask
                                                                  | NSResizableWindowMask)
                                                        backing: NSBackingStoreBuffered
                                                          defer: NO];

          /* NSWindow is releasedWhenClosed by default; closing the output
           * window would then deallocate it while our ivars still point at it,
           * leaving a dangling pointer that the next showGitOutput would touch
           * and crash on.  windowWillClose: nils our references so a later
           * showGitOutput: rebuilds a fresh window instead of touching a
           * freed one. */
          [outputWindow setDelegate: self];

          NSScrollView *scroll = [[NSScrollView alloc] initWithFrame: contentRect];
          [scroll setHasVerticalScroller: YES];
          [scroll setHasHorizontalScroller: YES];
          [scroll setAutoresizingMask: (NSViewWidthSizable | NSViewHeightSizable)];

          NSTextView *tv = [[NSTextView alloc] initWithFrame: contentRect];
          [tv setEditable: NO];
          [tv setFont: [NSFont userFixedPitchFontOfSize: 11]];
          [scroll setDocumentView: tv];

          [outputWindow setContentView: scroll];
          outputTextView = tv;

          RELEASE (scroll);
          RELEASE (tv);
        }
    }
  @catch (NSException *e)
    {
      NSLog (@"GitContextMenu: outputWindow creation threw: %@", e);
    }

  return outputWindow;
}

- (void)windowWillClose:(NSNotification *)note
{
  /* The output window was closed.  Drop our references so a later
   * showGitOutput: rebuilds a fresh window instead of touching a
   * deallocated one (NSWindow is releasedWhenClosed by default, so the
   * window is freed once closed and the ivars would otherwise dangle). */
  if ([note object] == outputWindow)
    {
      outputWindow = nil;
      outputTextView = nil;
    }
}

- (void)showGitOutput:(NSString *)output title:(NSString *)title
{
  @try
    {
      NSWindow *win = [self outputWindow];
      if (win == nil || outputTextView == nil)
        {
          return;
        }
      [outputTextView setString: (output ? output : @"")];
      [win setTitle: (title ? title : @"git")];
      [win makeKeyAndOrderFront: nil];
    }
  @catch (NSException *e)
    {
      NSLog (@"GitContextMenu: showGitOutput threw: %@", e);
    }
}

#pragma mark - Badge

/* The git logo overlaid (semi-transparent) on git-repository folder icons.
 * Loaded once from the bundle's gitLogo.png and cached in the gitBadge ivar;
 * callers draw it scaled to the icon (see FSNGitBadgedImage in FSNode). */
- (NSImage *)gitBadge
{
  @try
    {
      if (gitBadge == nil)
        {
          NSString *path = [[NSBundle bundleForClass: [self class]]
                              pathForResource: @"gitLogo" ofType: @"png"];
          NSImage *img = nil;
          if (path != nil)
            {
              img = [[NSImage alloc] initWithContentsOfFile: path];
            }
          if (img == nil)
            {
              /* Fallback: a small green disc so git folders are still marked
               * even if the bundled logo resource is missing. */
              img = [[NSImage alloc] initWithSize: NSMakeSize (16, 16)];
              [img lockFocus];
              [[NSColor colorWithCalibratedRed: 0.15 green: 0.6 blue: 0.25
                                       alpha: 1.0] set];
              NSBezierPath *p = [NSBezierPath bezierPathWithOvalInRect:
                                 NSMakeRect (2, 2, 12, 12)];
              [p fill];
              [img unlockFocus];
            }
          gitBadge = img;
        }
    }
  @catch (NSException *e)
    {
      NSLog (@"GitContextMenu: gitBadge threw: %@", e);
    }

  return gitBadge;
}

- (NSImage *)badgeImageForNode:(FSNode *)node
{
  @try
    {
      if (node == nil || [node isDirectory] == NO)
        {
          return nil;
        }

      NSString *p = [node path];
      if ([[NSFileManager defaultManager]
            fileExistsAtPath: [p stringByAppendingPathComponent: @".git"]])
        {
          return [self gitBadge];
        }
    }
  @catch (NSException *e)
    {
      NSLog (@"GitContextMenu: badgeImageForNode threw: %@", e);
    }

  return nil;
}

#pragma mark - Count badge

/* Run git synchronously in `repo` and return its standard output, or nil on any
 * failure (non-zero exit, launch error, exception).  The result is autoreleased
 * (alloc + autorelease, never reassigned then released) so callers can use it
 * directly without over-releasing. */
- (NSString *)gitOutputForArgs:(NSArray *)args repo:(NSString *)repo
{
  @try
    {
      if (repo == nil)
        {
          return nil;
        }
      NSTask *task = [[NSTask alloc] init];
      [task setLaunchPath: @"/usr/bin/git"];
      [task setArguments: args];
      [task setCurrentDirectoryPath: repo];
      NSPipe *outPipe = [NSPipe pipe];
      [task setStandardOutput: outPipe];
      [task setStandardError: [NSPipe pipe]];
      @try
        {
          [task launch];
        }
      @catch (NSException *e)
        {
          RELEASE (task);
          return nil;
        }
      NSData *data = [[outPipe fileHandleForReading] readDataToEndOfFile];
      [task waitUntilExit];
      NSInteger status = [task terminationStatus];
      RELEASE (task);
      if (status != 0)
        {
          return nil;
        }
      return [[[NSString alloc] initWithData: data encoding: NSUTF8StringEncoding]
               autorelease];
    }
  @catch (NSException *e)
    {
      return nil;
    }
}

/* Splat a git `--name-only` listing (one path per line) into `set`.  git quotes
 * paths that contain shell-special characters (spaces, etc.), wrapping them in
 * double quotes; we only need a stable per-file key for the count, so strip the
 * surrounding quotes.  Unquoted paths never begin with a quote. */
- (void)addPathsFromGitOutput:(NSString *)output toSet:(NSMutableSet *)set
{
  NSArray *lines = [output componentsSeparatedByString: @"\n"];
  for (NSString *line in lines)
    {
      NSString *path = [line stringByTrimmingCharactersInSet:
        [NSCharacterSet whitespaceAndNewlineCharacterSet]];
      if ([path length] == 0)
        {
          continue;
        }
      if ([path hasPrefix: @"\""] && [path hasSuffix: @"\""] && [path length] >= 2)
        {
          path = [path substringWithRange: NSMakeRange (1, [path length] - 2)];
        }
      [set addObject: path];
    }
}

/* The number drawn on the red corner badge: every file that is not git-ignored
 * and that is either not yet committed (working-tree change or untracked) or
 * committed but not pushed to its upstream.  Computed as the union of two git
 * listings (so a file is counted once even if it is both changed and part of an
 * unpushed commit): `git diff --name-only @{upstream}` already covers the union
 * of uncommitted and unpushed changes when an upstream exists (falling back to
 * `git diff --name-only HEAD` when there is none), plus `git ls-files
 * --others --exclude-standard` for untracked files (already .gitignore-
 * excluded).  Runs off the main thread (see the serial recompute worker). */
- (NSInteger)computeBadgeCountForPath:(NSString *)p
{
  @try
    {
      if (p == nil
          || [[NSFileManager defaultManager]
               fileExistsAtPath: [p stringByAppendingPathComponent: @".git"]] == NO)
        {
          return 0;
        }

      NSMutableSet *files = [NSMutableSet set];

      NSString *upstream =
        [self gitOutputForArgs:
                [NSArray arrayWithObjects: @"rev-parse", @"-q", @"--verify",
                                           @"@{upstream}", nil]
                          repo: p];
      NSString *changed = nil;
      if (upstream != nil && [upstream length] > 0)
        {
          changed =
            [self gitOutputForArgs:
                    [NSArray arrayWithObjects: @"diff", @"--name-only",
                                           @"@{upstream}", nil]
                              repo: p];
        }
      else
        {
          changed =
            [self gitOutputForArgs:
                    [NSArray arrayWithObjects: @"diff", @"--name-only", @"HEAD", nil]
                              repo: p];
        }
      if (changed != nil)
        {
          [self addPathsFromGitOutput: changed toSet: files];
        }

      NSString *untracked =
        [self gitOutputForArgs:
                [NSArray arrayWithObjects: @"ls-files", @"--others",
                                           @"--exclude-standard", nil]
                          repo: p];
      if (untracked != nil)
        {
          [self addPathsFromGitOutput: untracked toSet: files];
        }

      return (NSInteger) [files count];
    }
  @catch (NSException *e)
    {
      return 0;
    }
}

/* Non-blocking count accessor used by the icon layer.  Returns the cached count
 * when known, 0 for a known-clean repository, or -1 while a background
 * computation is scheduled or in flight (the caller shows nothing yet and waits
 * for FSNBadgeCountDidChangeNotification).  The first request schedules the git
 * work through the debounced, serial recompute pipeline so the UI never blocks
 * and at most one git process runs at a time. */
- (NSInteger)badgeCountForNode:(FSNode *)node
{
  @try
    {
      if (node == nil || [node isDirectory] == NO)
        {
          return 0;
        }
      NSString *p = [node path];
      if ([[NSFileManager defaultManager]
            fileExistsAtPath: [p stringByAppendingPathComponent: @".git"]] == NO)
        {
          return 0;
        }

      [badgeLock lock];
      NSNumber *known = [badgeCounts objectForKey: p];
      if (known != nil)
        {
          NSInteger v = [known integerValue];
          [badgeLock unlock];
          return v;
        }
      if ([badgePending containsObject: p])
        {
          [badgeLock unlock];
          return -1;
        }
      [badgeLock unlock];

      /* Schedule (debounced) rather than run immediately: this also covers the
       * initial population of a freshly opened folder, where many icons ask at
       * once and collapse into one git run per repo after the quiet window. */
      [self scheduleRecomputeForRepo: p];
      return -1;
    }
  @catch (NSException *e)
    {
      return 0;
    }
}

#pragma mark - Debounced, serialized recompute pipeline

/* Arms (or re-arms) a per-repo timer.  The timer fires only 200ms after the
 * last call, so a flurry of file-system events collapses into a single git run.
 * Must be called on the main thread (it schedules an NSTimer). */
- (void)scheduleRecomputeForRepo:(NSString *)repoRoot
{
  if ([NSThread isMainThread] == NO)
    {
      [self performSelectorOnMainThread: @selector (scheduleRecomputeForRepo:)
                             withObject: repoRoot
                          waitUntilDone: NO];
      return;
    }
  if (repoRoot == nil)
    {
      return;
    }

  [badgeLock lock];
  NSTimer *t = [recomputeTimers objectForKey: repoRoot];
  if (t != nil)
    {
      [t invalidate];
    }
  if ([badgePending containsObject: repoRoot] == NO)
    {
      [badgePending addObject: repoRoot];
    }
  NSTimer *nt = [NSTimer scheduledTimerWithTimeInterval: BADGE_DEBOUNCE_SECONDS
                                                  target: self
                                                selector: @selector (recomputeTimerFired:)
                                                userInfo: repoRoot
                                                 repeats: NO];
  [recomputeTimers setObject: nt forKey: repoRoot];
  [badgeLock unlock];
}

/* Timer callback: hand the repo to the serial worker (or, if a recompute is
 * already running for it, mark it dirty so it re-runs once the current one
 * finishes). */
- (void)recomputeTimerFired:(NSTimer *)timer
{
  NSString *repoRoot = [timer userInfo];

  [badgeLock lock];
  [recomputeTimers removeObjectForKey: repoRoot];
  BOOL inFlight = [badgeInFlight containsObject: repoRoot];
  if (inFlight)
    {
      [badgeDirty addObject: repoRoot];
      [badgeLock unlock];
      return;
    }
  [badgeLock unlock];

  [self enqueueRecompute: repoRoot];
}

/* Queue a recompute and make sure the single worker thread is draining the
 * queue.  Enqueuing marks the repo in-flight so concurrent schedule calls
 * during the run mark it dirty instead of double-running. */
- (void)enqueueRecompute:(NSString *)repoRoot
{
  [badgeLock lock];
  [badgeInFlight addObject: repoRoot];
  [badgeLock unlock];

  [recomputeCond lock];
  [recomputeQueue addObject: repoRoot];
  [recomputeCond signal];
  [recomputeCond unlock];

  [recomputeCond lock];
  BOOL running = recomputeWorkerRunning;
  [recomputeCond unlock];
  if (running == NO)
    {
      [recomputeCond lock];
      if (recomputeWorkerRunning == NO)
        {
          recomputeWorkerRunning = YES;
          [recomputeCond unlock];
          [NSThread detachNewThreadSelector: @selector (recomputeWorker)
                                   toTarget: self
                                 withObject: nil];
        }
      else
        {
          [recomputeCond unlock];
        }
    }
}

/* Single background thread: pops one repo at a time and computes it, so git
 * subprocesses never run in parallel.  A local pool is required because the
 * thread has no default pool. */
- (void)recomputeWorker
{
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

  while (1)
    {
      NSString *repoRoot = nil;

      [recomputeCond lock];
      while ([recomputeQueue count] == 0)
        {
          [recomputeCond wait];
        }
      repoRoot = [[recomputeQueue objectAtIndex: 0] retain];
      [recomputeQueue removeObjectAtIndex: 0];
      [recomputeCond unlock];

      NSAutoreleasePool *inner = [[NSAutoreleasePool alloc] init];
      [self computeAndNotify: repoRoot];
      [inner release];
      [repoRoot release];
    }

  [pool release];
}

/* Runs on the worker thread: computes the count, caches it, and notifies the
 * main thread only if the value changed (avoiding needless redraws).  If the
 * repo was invalidated again while we were computing, it re-schedules itself. */
- (void)computeAndNotify:(NSString *)repoRoot
{
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  @try
    {
      /* Record that we are about to run git for this repo.  Our own git
       * status/diff rewrites .git/index, which the .git watch will report back;
       * stamping now lets watchedPathDidChange: ignore those self-induced
       * events and avoid an infinite recompute loop. */
      [badgeLock lock];
      [lastSelfRun setObject: [NSDate date] forKey: repoRoot];
      [badgeLock unlock];

      NSInteger c = [self computeBadgeCountForPath: repoRoot];

      [badgeLock lock];
      NSNumber *old = [badgeCounts objectForKey: repoRoot];
      NSInteger oldV = (old != nil) ? [old integerValue] : NSIntegerMin;
      [badgeCounts setObject: [NSNumber numberWithInteger: c] forKey: repoRoot];
      BOOL dirty = [badgeDirty containsObject: repoRoot];
      if (dirty)
        {
          [badgeDirty removeObject: repoRoot];
        }
      [badgeInFlight removeObject: repoRoot];
      [badgePending removeObject: repoRoot];
      [badgeLock unlock];

      if (dirty)
        {
          [self scheduleRecomputeForRepo: repoRoot];
        }

      if (c != oldV)
        {
          [self performSelectorOnMainThread: @selector (postBadgeNotificationForPath:)
                                   withObject: repoRoot
                                waitUntilDone: NO];
        }
    }
  @catch (NSException *e)
    {
      [badgeLock lock];
      [badgeInFlight removeObject: repoRoot];
      [badgePending removeObject: repoRoot];
      [badgeDirty removeObject: repoRoot];
      [badgeLock unlock];
    }
  [pool release];
}

/* Tier-1 invalidation: a git operation we performed just changed repo state.
 * Drop the cached count and let the debounced pipeline recompute it.  The icon
 * keeps showing the previous number until the fresh value arrives. */
- (void)invalidateBadgeForPath:(NSString *)repoRoot
{
  if (repoRoot == nil)
    {
      return;
    }
  [badgeLock lock];
  [badgeCounts removeObjectForKey: repoRoot];
  [badgeLock unlock];
  [self scheduleRecomputeForRepo: repoRoot];
}

- (void)postBadgeNotificationForPath:(NSString *)p
{
  [[NSNotificationCenter defaultCenter]
    postNotificationName: FSNBadgeCountDidChangeNotification
                  object: p];
}

#pragma mark - fswatcher client (external-change watching)

/* Find the nearest ancestor directory that is a git repository, or nil. */
- (NSString *)repoRootForNode:(FSNode *)node
{
  @try
    {
      if (node == nil || [node isDirectory] == NO)
        {
          return nil;
        }
      NSFileManager *fm = [NSFileManager defaultManager];
      NSString *p = [node path];

      while (p != nil && [p isEqual: @""] == NO)
        {
          if ([fm fileExistsAtPath:
                [p stringByAppendingPathComponent: @".git"]])
            {
              return p;
            }
          NSString *parent = [p stringByDeletingLastPathComponent];
          if ([parent isEqual: p])
            {
              break;
            }
          p = parent;
        }
    }
  @catch (NSException *e)
    {
      NSLog (@"GitContextMenu: repoRootForNode threw: %@", e);
    }
  return nil;
}

/* Called by FSNIcon when an icon for a git repo becomes visible.  Refcounts
 * across multiple icons; the first reference actually starts watching (the
 * watch is added now if fswatcher is already connected, or once the background
 * connect finishes - see connectFSWatcher / addWatchersForAllRoots). */
- (void)startWatchingNode:(FSNode *)node
{
  NSString *root = [self repoRootForNode: node];
  if (root == nil)
    {
      return;
    }

  [self ensureWatcher];

  [watchLock lock];
  NSNumber *refsNum = [repoRefcounts objectForKey: root];
  NSUInteger refs = refsNum ? [refsNum unsignedIntegerValue] : 0;
  BOOL first = (refs == 0);
  [repoRefcounts setObject: [NSNumber numberWithUnsignedInteger: refs + 1]
                     forKey: root];
  [watchLock unlock];

  if (first)
    {
      [self addWatchersForRepoRoot: root];
    }
}

/* Called by FSNIcon when an icon is reused or deallocated.  The last reference
 * stops watching the repo (removing all per-directory watches). */
- (void)stopWatchingNode:(FSNode *)node
{
  NSString *root = [self repoRootForNode: node];
  if (root == nil)
    {
      return;
    }

  [watchLock lock];
  NSNumber *refsNum = [repoRefcounts objectForKey: root];
  NSUInteger refs = refsNum ? [refsNum unsignedIntegerValue] : 0;
  if (refs <= 1)
    {
      [repoRefcounts removeObjectForKey: root];
      [watchLock unlock];
      [self removeWatchersForRepoRoot: root];
    }
  else
    {
      [repoRefcounts setObject: [NSNumber numberWithUnsignedInteger: refs - 1]
                        forKey: root];
      [watchLock unlock];
    }
}

/* Connect to the shared fswatcher DO service (launching it if necessary) on a
 * background thread so the UI never blocks.  Once connected we register as a
 * non-global client and add watches for any repositories already referenced.
 * If the service is unavailable, Tier-2 watching is simply disabled and Tier-1
 * (in-Workspace actions) still works. */
- (void)ensureWatcher
{
  [watchLock lock];
  BOOL connected = fswatcherConnected;
  BOOL connecting = fswatcherConnecting;
  [watchLock unlock];
  if (connected || connecting)
    {
      return;
    }

  [watchLock lock];
  fswatcherConnecting = YES;
  [watchLock unlock];

  /* All fswatcher DO use (proxy creation, registerClient, incoming callbacks)
   * must happen on the main thread: GNUstep NSDistantObject proxies are
   * thread-affine, and the connection's run loop is the main run loop, so only
   * there are change callbacks delivered.  We never block the main thread: if
   * the service is not up yet we launch it and poll again shortly. */
  [self connectFSWatcher];
}

/* One non-blocking attempt to connect to fswatcher, retried via a short delayed
 * perform until the service is reachable or we give up.  Runs on the main
 * thread so the proxy stays thread-affine and callbacks arrive. */
- (void)connectFSWatcher
{
  id fsw =
    [NSConnection rootProxyForConnectionWithRegisteredName: @"fswatcher"
                                                      host: nil];
  if (fsw == nil)
    {
      [watchLock lock];
      BOOL launched = fswatcherLaunched;
      NSInteger attempts = fswatcherAttempts;
      fswatcherAttempts = attempts + 1;
      [watchLock unlock];

       if (launched == NO)
         {
           /* Prefer the SYSTEM-domain fswatcher (this repo's build, installed
              to /System/Library/Tools) over whatever launchPathForTool:
              resolves first - on *BSD that is the build carrying our kqueue
              backend. Falls back to the generic lookup if absent. */
           NSString *tool = @"/System/Library/Tools/fswatcher";
           if ([[NSFileManager defaultManager] fileExistsAtPath: tool] == NO)
             {
               tool = [NSTask launchPathForTool: @"fswatcher"];
             }
           if (tool != nil)
            {
              NSTask *task = [[NSTask alloc] init];
              [task setLaunchPath: tool];
              [task launch];
              if (spawnedTasks != nil)
                {
                  [spawnedTasks addObject: task];
                }
              RELEASE (task);
            }
          [watchLock lock];
          fswatcherLaunched = YES;
          [watchLock unlock];
        }

      if (fswatcherAttempts <= 20)
        {
          [self performSelector: @selector (connectFSWatcher)
                       withObject: nil
                       afterDelay: 0.15];
        }
      else
        {
          [watchLock lock];
          fswatcherConnecting = NO;
          [watchLock unlock];
        }
      return;
    }

  @try
    {
      [fsw setProtocolForProxy: @protocol (FSWatcherProtocol)];
      [fsw registerClient: (id <FSWClientProtocol>)self
           isGlobalWatcher: NO];

      [[NSNotificationCenter defaultCenter]
        addObserver: self
           selector: @selector (fswatcherConnectionDidDie:)
               name: NSConnectionDidDieNotification
             object: [fsw connectionForProxy]];

      [watchLock lock];
      [fswatcher release];
      fswatcher = [fsw retain];
      fswatcherConnected = YES;
      [watchLock unlock];

      /* Add watches for any repositories referenced before we connected.  This
       * must run on the main thread: every fswatcher proxy call is
       * thread-affine, and the watch-enumeration DO calls would otherwise throw.
       * It is a one-time cost per repository when it first becomes visible. */
      [self addWatchersForAllRoots];
    }
  @catch (NSException *e)
    {
      NSLog (@"GitContextMenu: fswatcher setup failed: %@", e);
      [watchLock lock];
      fswatcherConnected = NO;
      [watchLock unlock];
    }

  [watchLock lock];
  fswatcherConnecting = NO;
  [watchLock unlock];
}

/* Add fswatcher watches for every repository currently referenced.  Called once
 * the connection is up (and again after a reconnect). */
- (void)addWatchersForAllRoots
{
  [watchLock lock];
  NSArray *roots = [repoRefcounts allKeys];
  [watchLock unlock];
  for (NSString *r in roots)
    {
      [self addWatchersForRepoRoot: r];
    }
}

- (void)fswatcherConnectionDidDie:(NSNotification *)note
{
  [watchLock lock];
  fswatcherConnected = NO;
  fswatcherLaunched = NO;
  [fswatcher release];
  fswatcher = nil;
  /* The service (and its watches) is gone; drop our view of them.  repoRefcounts
   * is kept so ensureWatcher can re-add watches on the next reconnect. */
  [watchedPaths removeAllObjects];
  [dirRepoRoots removeAllObjects];
  [watchLock unlock];
}

/* Watch the repo root (.git itself, for index/ref changes) plus every directory
 * of the working tree (so unstaged edits and new untracked files anywhere are
 * caught).  .git's own contents are not descended into. */
- (void)addWatchersForRepoRoot:(NSString *)root
{
  NSFileManager *fm = [NSFileManager defaultManager];
  NSString *gitDir = [root stringByAppendingPathComponent: @".git"];

  if ([fm fileExistsAtPath: gitDir])
    {
      [self addRepoWatch: gitDir repoRoot: root];
    }

  /* Also watch the repository root itself: changes/creations of files directly
   * in the root (e.g. the typical working-tree edits) are reported by the root
   * directory watch, not by any subdirectory watch. */
  [self addRepoWatch: root repoRoot: root];

  NSDirectoryEnumerator *en = [fm enumeratorAtPath: root];
  NSString *rel;
  while ((rel = [en nextObject]) != nil)
    {
      NSArray *comps = [rel pathComponents];
      if ([comps containsObject: @".git"])
        {
          [en skipDescendants];
          continue;
        }
      NSString *abs = [root stringByAppendingPathComponent: rel];
      NSDictionary *attrs = [en fileAttributes];
      if ([[attrs fileType] isEqual: NSFileTypeDirectory])
        {
          [self addRepoWatch: abs repoRoot: root];
        }
    }
}

- (void)removeWatchersForRepoRoot:(NSString *)root
{
  NSMutableArray *toRemove = [NSMutableArray array];
  [watchLock lock];
  for (NSString *dir in [watchedPaths allKeys])
    {
      if ([[dirRepoRoots objectForKey: dir] isEqual: root])
        {
          [toRemove addObject: dir];
        }
    }
  [watchLock unlock];
  for (NSString *dir in toRemove)
    {
      [self removeRepoWatch: dir];
    }
}

/* Reference-counted per-directory watch.  The actual fswatcher add happens only
 * on the 0 -> 1 transition; dirRepoRoots records which repo a watched dir
 * belongs to so file-system events can be mapped back to a repo root. */
- (void)addRepoWatch:(NSString *)dir repoRoot:(NSString *)root
{
  [watchLock lock];
  /* If the connection is not up yet, skip: connectFSWatcher re-adds all roots
   * once it succeeds.  We must not record the watch as active without a real
   * fswatcher add, or events would never arrive. */
  if (fswatcher == nil)
    {
      [watchLock unlock];
      return;
    }
  NSNumber *refsNum = [watchedPaths objectForKey: dir];
  NSUInteger refs = refsNum ? [refsNum unsignedIntegerValue] : 0;
  if (refs == 0)
    {
      /* Defer the actual fswatcher send to the next run-loop pass.  A
       * synchronous call here would pump the run loop (NSConnectionReplyMode)
       * while watchLock is still held, letting a nested icon lifecycle
       * re-enter -[GitContextMenu ensureWatcher] and deadlock the main thread
       * on the non-recursive watchLock (seen when opening a folder that
       * triggers a desktop reload, e.g. ~/Downloads).  NSDefaultRunLoopMode
       * performers do not fire during a NSConnectionReplyMode reply wait, so
       * this can never nest.  Batched into a single one-shot timer so we
       * never flood the run loop with 80 000+ individual timers. */
      [_pendingWatcherAdds addObject: [NSArray arrayWithObjects: fswatcher, dir, nil]];
      if (_watcherFlushTimer == nil)
        {
          _watcherFlushTimer = [NSTimer scheduledTimerWithTimeInterval: 0
                                                               target: self
                                                             selector: @selector (_flushPendingWatcherOps)
                                                             userInfo: nil
                                                              repeats: NO];
        }
    }
  [watchedPaths setObject: [NSNumber numberWithUnsignedInteger: refs + 1]
                    forKey: dir];
  [dirRepoRoots setObject: root forKey: dir];
  [watchLock unlock];
}

- (void)removeRepoWatch:(NSString *)dir
{
  [watchLock lock];
  NSNumber *refsNum = [watchedPaths objectForKey: dir];
  NSUInteger refs = refsNum ? [refsNum unsignedIntegerValue] : 0;
  if (refs <= 1)
    {
      if (fswatcher != nil)
        {
          [_pendingWatcherRemoves addObject: [NSArray arrayWithObjects: fswatcher, dir, nil]];
          if (_watcherFlushTimer == nil)
            {
              _watcherFlushTimer = [NSTimer scheduledTimerWithTimeInterval: 0
                                                                   target: self
                                                                 selector: @selector (_flushPendingWatcherOps)
                                                                 userInfo: nil
                                                                  repeats: NO];
            }
        }
      [watchedPaths removeObjectForKey: dir];
      [dirRepoRoots removeObjectForKey: dir];
    }
  else
    {
      [watchedPaths setObject: [NSNumber numberWithUnsignedInteger: refs - 1]
                       forKey: dir];
    }
  [watchLock unlock];
}

/* Flush all pending watcher adds/removes in a single batch.  Each entry in the
 * pending arrays is an NSArray of (proxy, path).  Runs outside watchLock so the
 * sync DO calls can pump the run loop without nesting re-entrant watch acquisitions.
 * One-shot timer; automatically cancelled after firing. */
- (void)_flushPendingWatcherOps
{
  NSArray *adds, *removes;
  [watchLock lock];
  adds = [_pendingWatcherAdds copy];
  removes = [_pendingWatcherRemoves copy];
  [_pendingWatcherAdds removeAllObjects];
  [_pendingWatcherRemoves removeAllObjects];
  _watcherFlushTimer = nil;
  [watchLock unlock];

  for (NSArray *args in adds)
    {
      @try
        {
          id proxy = [args objectAtIndex: 0];
          NSString *dir = [args objectAtIndex: 1];
          [(id <FSWatcherProtocol>)proxy client: (id <FSWClientProtocol>)self
                               addWatcherForPath: dir];
        }
      @catch (NSException *e)
        {
          NSLog (@"GitContextMenu: deferred addWatcherForPath failed: %@", e);
        }
    }
  for (NSArray *args in removes)
    {
      @try
        {
          id proxy = [args objectAtIndex: 0];
          NSString *dir = [args objectAtIndex: 1];
          [(id <FSWatcherProtocol>)proxy client: (id <FSWClientProtocol>)self
                               removeWatcherForPath: dir];
        }
      @catch (NSException *e)
        {
          NSLog (@"GitContextMenu: deferred removeWatcherForPath failed: %@", e);
        }
    }
}

/* When a watched directory changes, re-scan its immediate children so that
 * sub-directories created (or removed) afterwards are watched too.  This keeps
 * the watch set in sync with the working tree without a full re-walk on every
 * event.  Newly added directories pick up their own deeper sub-directories via
 * the events they then generate. */
- (void)reconcileWatchesForDir:(NSString *)dir repoRoot:(NSString *)root
{
  if (dir == nil || root == nil)
    {
      return;
    }

  /* Throttle: collapse a burst of events on the same directory into one
   * reconcile per quiescence window, so we don't readdir on every single file
   * change inside it. */
  [watchLock lock];
  NSDate *last = [lastReconcile objectForKey: dir];
  if (last != nil && (-[last timeIntervalSinceNow]) < BADGE_DEBOUNCE_SECONDS)
    {
      [watchLock unlock];
      return;
    }
  [lastReconcile setObject: [NSDate date] forKey: dir];
  [watchLock unlock];

  NSFileManager *fm = [NSFileManager defaultManager];
  NSArray *children = [fm contentsOfDirectoryAtPath: dir error: nil];
  if (children == nil)
    {
      return;
    }

  NSMutableSet *existing = [NSMutableSet set];

  for (NSString *name in children)
    {
      NSString *abs = [dir stringByAppendingPathComponent: name];
      /* Never descend into or watch .git. */
      if ([[abs pathComponents] containsObject: @".git"])
        {
          continue;
        }
      BOOL isdir = NO;
      if ([fm fileExistsAtPath: abs isDirectory: &isdir] && isdir)
        {
          [existing addObject: abs];
          BOOL alreadyWatched = NO;
          [watchLock lock];
          alreadyWatched = ([watchedPaths objectForKey: abs] != nil);
          [watchLock unlock];
          if (alreadyWatched == NO)
            {
              [self addRepoWatch: abs repoRoot: root];
            }
        }
    }

  /* Drop watches for immediate sub-directories of dir that disappeared. */
  [watchLock lock];
  NSArray *watched = [watchedPaths allKeys];
  [watchLock unlock];

  NSString *prefix = [dir stringByAppendingString: @"/"];
  for (NSString *wd in watched)
    {
      if ([wd hasPrefix: prefix] == NO)
        {
          continue;
        }
      NSString *rel = [wd substringFromIndex: [prefix length]];
      if ([rel rangeOfString: @"/"].location != NSNotFound)
        {
          continue;   /* only immediate children, not deeper descendants */
        }
      if ([existing containsObject: wd] == NO)
        {
          [self removeRepoWatch: wd];
        }
    }
}

/* fswatcher callback: the changed path is one of our watched directories.  Map
 * it back to its repo root and recompute after the quiescence window. */
- (void)watchedPathDidChange:(NSData *)dirinfo
{
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  @try
    {
      NSDictionary *info = [NSUnarchiver unarchiveObjectWithData: dirinfo];
      NSString *path = [info objectForKey: @"path"];
      if (path == nil)
        {
          [pool release];
          return;
        }
      NSString *root = nil;
      [watchLock lock];
      root = [[dirRepoRoots objectForKey: path] retain];
      [watchLock unlock];
      if (root != nil)
        {
          /* Ignore .git events that our own recompute produced (git rewrites
           * .git/index).  Genuine external commits fall outside this small
           * window and still trigger a refresh. */
          if ([path rangeOfString: @"/.git"].location != NSNotFound
              || [path hasSuffix: @"/.git"])
            {
              [badgeLock lock];
              NSDate *last = [lastSelfRun objectForKey: root];
              [badgeLock unlock];
              if (last != nil
                  && (-[last timeIntervalSinceNow]) < 2.0)
                {
                  [root release];
                  [pool release];
                  return;
                }
            }
          [self scheduleRecomputeForRepo: root];
          [self reconcileWatchesForDir: path repoRoot: root];
          [root release];
        }
    }
  @catch (NSException *e)
    {
      /* ignore malformed callbacks */
    }
  [pool release];
}

/* We register as a non-global client, so this is never invoked; present only to
 * satisfy the protocol. */
- (void)globalWatchedPathDidChange:(NSDictionary *)info
{
}

@end
