/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

#import "GitContextMenu.h"
#import "AppearanceMetrics.h"
#import <AppKit/AppKit.h>

/* Hard ceiling on how long a git invocation may run before we terminate it.
 * Prevents a hanging git (e.g. prompting for credentials) from freezing the
 * UI. */
#define GIT_TIMEOUT 60.0

@implementation GitContextMenu

- (void)dealloc
{
  DESTROY (gitBadge);
  DESTROY (outputWindow);
  DESTROY (pending);
  DESTROY (taskLock);
  DESTROY (spawnedTasks);
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

      RELEASE (cancel);
      RELEASE (ok);
      RELEASE (field);
      RELEASE (msg);
      RELEASE (win);
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

      RELEASE (cancel);
      RELEASE (ok);
      RELEASE (tv);
      RELEASE (scroll);
      RELEASE (cb);
      RELEASE (msg);
      RELEASE (win);
      return msgText;
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

      [pending removeObjectForKey: key];

      if (timer != nil)
        {
          [timer invalidate];
        }
      [timer release];
      [then release];
      [title release];
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

/* Small green badge overlaid on git-repository folder icons. */
- (NSImage *)gitBadge
{
  @try
    {
      if (gitBadge == nil)
        {
          NSImage *img = [[NSImage alloc] initWithSize: NSMakeSize (16, 16)];

          [img lockFocus];
          [[NSColor colorWithCalibratedRed: 0.15 green: 0.6 blue: 0.25 alpha: 1.0] set];
          NSBezierPath *p = [NSBezierPath bezierPathWithOvalInRect:
                             NSMakeRect (2, 2, 12, 12)];
          [p fill];
          [[NSColor whiteColor] set];
          NSRectFill (NSMakeRect (7, 7, 2, 2));
          [img unlockFocus];

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

@end
