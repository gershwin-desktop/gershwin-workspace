/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

#import "GitContextMenu.h"
#import <AppKit/AppKit.h>

@implementation GitContextMenu

/* A node is "handled" if any selected node is a directory containing a .git
 * subdirectory. */
- (NSString *)repoPathForNodes:(NSArray *)nodes
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

  return nil;
}

- (BOOL)extensionCanHandleNodes:(NSArray *)nodes
{
  return ([self repoPathForNodes: nodes] != nil);
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

#pragma mark - Context-menu actions

- (void)gitStatus:(id)sender
{
  NSString *repo = [sender representedObject];
  [self runGit: [NSArray arrayWithObjects: @"status", @"--short", nil]
         title: @"Git Status"
          repo: repo];
}

- (void)gitDiff:(id)sender
{
  NSString *repo = [sender representedObject];
  [self runGit: [NSArray arrayWithObjects: @"diff", nil]
         title: @"Git Diff"
          repo: repo];
}

- (void)gitLog:(id)sender
{
  NSString *repo = [sender representedObject];
  [self runGit: [NSArray arrayWithObjects: @"log", @"--oneline", @"-n", @"50", nil]
         title: @"Git Log"
          repo: repo];
}

/* Runs git synchronously in the repo and shows the combined stdout/stderr in a
 * window.  Synchronous for simplicity; git status/diff/log are fast for normal
 * repositories. */
- (void)runGit:(NSArray *)args title:(NSString *)title repo:(NSString *)repo
{
  NSTask *task = [[NSTask alloc] init];

  [task setLaunchPath: @"/usr/bin/git"];
  [task setArguments: args];
  [task setCurrentDirectoryPath: repo];

  NSPipe *pipe = [NSPipe pipe];
  [task setStandardOutput: pipe];
  [task setStandardError: pipe];

  @try
    {
      [task launch];
      [task waitUntilExit];

      NSData *data = [[pipe fileHandleForReading] readDataToEndOfFile];
      NSString *output = [[NSString alloc] initWithData: data
                                              encoding: NSUTF8StringEncoding];
      if (output == nil)
        {
          output = @"";
        }

      [self showGitOutput: output
                    title: [NSString stringWithFormat: @"%@ — %@", title,
                             [repo lastPathComponent]]];
      RELEASE (output);
    }
  @catch (NSException *e)
    {
      [self showGitOutput: [NSString stringWithFormat: @"Failed to run git: %@",
                             [e description]]
                    title: title];
    }

  RELEASE (task);
}

- (NSWindow *)outputWindow
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

  return outputWindow;
}

- (void)showGitOutput:(NSString *)output title:(NSString *)title
{
  NSWindow *win = [self outputWindow];
  [outputTextView setString: output];
  [win setTitle: title];
  [win makeKeyAndOrderFront: nil];
}

#pragma mark - Badge

/* Small green badge overlaid on git-repository folder icons. */
- (NSImage *)gitBadge
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

  return gitBadge;
}

- (NSImage *)badgeImageForNode:(FSNode *)node
{
  NSFileManager *fm = [NSFileManager defaultManager];

  if ([node isDirectory] == NO)
    {
      return nil;
    }

  NSString *p = [node path];
  if ([fm fileExistsAtPath: [p stringByAppendingPathComponent: @".git"]])
    {
      return [self gitBadge];
    }

  return nil;
}

@end
