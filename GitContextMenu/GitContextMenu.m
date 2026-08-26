/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

#import "GitContextMenu.h"
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
  [super dealloc];
}

/* A node is "handled" if any selected node is a directory containing a .git
 * subdirectory. */
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

- (BOOL)extensionCanHandleNodes:(NSArray *)nodes
{
  @try
    {
      return ([self repoPathForNodes: nodes] != nil);
    }
  @catch (NSException *e)
    {
      return NO;
    }
}

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

      if (repo == nil)
        {
          return;
        }

      NSMenuItem *gitItem = [[NSMenuItem alloc] initWithTitle: @"Git"
                                                       action: nil
                                                keyEquivalent: @""];
      NSMenu *gitMenu = [[NSMenu alloc] initWithTitle: @"Git"];

      [self addItemWithTitle: @"Status" action: @selector(gitStatus:) toMenu: gitMenu repo: repo];
      [self addItemWithTitle: @"Diff"   action: @selector(gitDiff:)   toMenu: gitMenu repo: repo];
      [self addItemWithTitle: @"Log"    action: @selector(gitLog:)    toMenu: gitMenu repo: repo];

      [gitItem setSubmenu: gitMenu];
      RELEASE (gitMenu);

      [menu addItem: [NSMenuItem separatorItem]];
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

- (void)gitLog:(id)sender
{
  NSString *repo = [sender representedObject];
  [self runGitCommand: [NSArray arrayWithObjects: @"log", @"--oneline",
                         @"-n", @"50", nil]
                title: @"Git Log"
                 repo: repo];
}

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

/* Run git and present its output.  Crucially we read the child's output
 * asynchronously: reading the pipe only after waitUntilExit deadlocks once the
 * output exceeds the pipe buffer, which hangs (and on GNUstep crashes) the
 * main thread.  Everything here is wrapped so the bundle can never take down
 * Workspace. */
- (void)runGitCommand:(NSArray *)args title:(NSString *)title repo:(NSString *)repo
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

      if (pending == nil)
        {
          pending = [[NSMutableDictionary alloc] init];
        }

      NSMutableDictionary *info = [NSMutableDictionary dictionaryWithObjectsAndKeys:
        title, @"title", task, @"task", readHandle, @"handle",
        [NSNumber numberWithBool: NO], @"done", nil];
      [pending setObject: info forKey: key];

      [[NSNotificationCenter defaultCenter]
        addObserver: self
           selector: @selector(gitReadCompleted:)
               name: NSFileHandleReadToEndOfFileCompletionNotification
             object: readHandle];

      /* Begin draining the pipe in the background before the process even
       * starts, so a large diff can never block the child. */
      [readHandle readToEndOfFileInBackgroundAndNotify];

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

- (void)gitReadCompleted:(NSNotification *)note
{
  NSFileHandle *readHandle = [note object];
  NSValue *key = [NSValue valueWithNonretainedObject: readHandle];
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

  @try
    {
      [[NSNotificationCenter defaultCenter]
        removeObserver: self
                  name: NSFileHandleReadToEndOfFileCompletionNotification
                object: readHandle];
      NSTimer *timer = [info objectForKey: @"timer"];
      if (timer != nil)
        {
          [timer invalidate];
        }

      NSTask *task = [info objectForKey: @"task"];
      NSString *title = [info objectForKey: @"title"];
      NSData *data = [[note userInfo] objectForKey: NSFileHandleNotificationDataItem];
      NSString *output = [self stringFromData: data];

      [pending removeObjectForKey: key];
      DESTROY (task);

      NSDictionary *payload = [NSDictionary dictionaryWithObjectsAndKeys:
        output, @"output", (title ? title : @"git"), @"title", nil];
      [self performSelectorOnMainThread: @selector(presentOutput:)
                              withObject: payload
                           waitUntilDone: NO];
    }
  @catch (NSException *e)
    {
      NSLog (@"GitContextMenu: gitReadCompleted threw: %@", e);
    }
}

- (void)gitTimeout:(NSTimer *)timer
{
  NSValue *key = [timer userInfo];
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

  @try
    {
      NSFileHandle *readHandle = [info objectForKey: @"handle"];
      [[NSNotificationCenter defaultCenter]
        removeObserver: self
                  name: NSFileHandleReadToEndOfFileCompletionNotification
                object: readHandle];

      NSTask *task = [info objectForKey: @"task"];
      if (task != nil && [task isRunning])
        {
          [task terminate];
        }

      NSString *title = [info objectForKey: @"title"];
      [pending removeObjectForKey: key];
      DESTROY (task);

      NSDictionary *payload = [NSDictionary dictionaryWithObjectsAndKeys:
        @"(git did not finish within the time limit)", @"output",
        (title ? title : @"git"), @"title", nil];
      [self performSelectorOnMainThread: @selector(presentOutput:)
                              withObject: payload
                           waitUntilDone: NO];
    }
  @catch (NSException *e)
    {
      NSLog (@"GitContextMenu: gitTimeout threw: %@", e);
    }
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

/* Runs on the main thread so the output window is touched only there. */
- (void)presentOutput:(NSDictionary *)payload
{
  @try
    {
      [self showGitOutput: [payload objectForKey: @"output"]
                    title: [payload objectForKey: @"title"]];
    }
  @catch (NSException *e)
    {
      NSLog (@"GitContextMenu: showGitOutput threw: %@", e);
    }
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
