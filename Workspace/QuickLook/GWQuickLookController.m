/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

#import "GWQuickLookController.h"
#import <GNUstepBase/GNUstep.h>

/* Only the handful of selectors this controller sends to the real
 * GWQuickLookPanel; declared here (rather than by importing
 * GWQuickLookPanel.h) so this file needs no AppKit/Inspector include
 * paths and never creates a link-time dependency on the panel - the
 * class is looked up by name in -createAndShowPanelForPaths:sourceWindow:
 * below, and the class object is never referenced literally. */
@interface NSObject (GWQuickLookPanelMethods)
- (id)initWithPaths:(NSArray *)paths sourceWindow:(id)sourceWindow;
- (void)showAnimated;
- (void)closeAnimated;
@end

static GWQuickLookController *sharedInstance = nil;

@implementation GWQuickLookController

+ (GWQuickLookController *)sharedController
{
  if (sharedInstance == nil)
    {
      sharedInstance = [self new];
    }
  return sharedInstance;
}

+ (GWQuickLookAction)actionForSpaceKeyWithSelectionCount:(NSUInteger)count
                                                  isOpen:(BOOL)isOpen
{
  /* Closing always wins: whatever is open closes on the next Space,
   * regardless of what happens to be selected at that moment. */
  if (isOpen)
    {
      return GWQuickLookActionClose;
    }
  if (count == 0)
    {
      return GWQuickLookActionNone;
    }
  return GWQuickLookActionOpen;
}

- (void)dealloc
{
  DESTROY(_panel);
  [super dealloc];
}

- (BOOL)isOpen
{
  return _open;
}

- (BOOL)toggleQuickLookForSelection:(NSArray *)selection
                        sourceWindow:(id)sourceWindow
{
  NSArray *paths = ([selection count] > 0) ? [selection valueForKey: @"path"] : nil;

  return [self toggleQuickLookForPaths: paths sourceWindow: sourceWindow];
}

- (BOOL)toggleQuickLookForPaths:(NSArray *)paths
                    sourceWindow:(id)sourceWindow
{
  GWQuickLookAction action = [[self class] actionForSpaceKeyWithSelectionCount: [paths count]
                                                                        isOpen: _open];

  switch (action)
    {
    case GWQuickLookActionOpen:
      [self createAndShowPanelForPaths: paths sourceWindow: sourceWindow];
      _open = YES;
      return YES;

    case GWQuickLookActionClose:
      [self close];
      return YES;

    case GWQuickLookActionNone:
    default:
      return NO;
    }
}

- (void)close
{
  if (_open)
    {
      [self destroyPanel];
      _open = NO;
    }
}

- (void)createAndShowPanelForPaths:(NSArray *)paths sourceWindow:(id)sourceWindow
{
  /* Looked up by name (see the category note above) so this class never
   * links the window/AppKit-heavy GWQuickLookPanel implementation; the
   * real app always has GWQuickLookPanel.m linked in, so this resolves
   * there and only there. */
  Class panelClass = NSClassFromString(@"GWQuickLookPanel");
  id panel;

  if (panelClass == Nil)
    {
      return;
    }

  panel = [[panelClass alloc] initWithPaths: paths sourceWindow: sourceWindow];
  ASSIGN(_panel, panel);
  RELEASE(panel);
  [_panel showAnimated];
}

- (void)destroyPanel
{
  if (_panel != nil)
    {
      [_panel closeAnimated];
      DESTROY(_panel);
    }
}

@end
