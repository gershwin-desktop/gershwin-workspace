/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

#import "GWLookInsideController.h"
#import <GNUstepBase/GNUstep.h>

/* Only the handful of selectors this controller sends to the real
 * GWLookInsidePanel; declared here (rather than by importing
 * GWLookInsidePanel.h) so this file needs no AppKit/Inspector include
 * paths and never creates a link-time dependency on the panel - the
 * class is looked up by name in -createAndShowPanelForPaths:sourceWindow:fullScreen:
 * below, and the class object is never referenced literally. */
@interface NSObject (GWLookInsidePanelMethods)
- (id)initWithPaths:(NSArray *)paths sourceWindow:(id)sourceWindow;
- (void)showAnimatedInFullScreen:(BOOL)fullScreen;
- (void)showPaths:(NSArray *)paths;
- (void)closeAnimated;
@end

static GWLookInsideController *sharedInstance = nil;

@implementation GWLookInsideController

+ (GWLookInsideController *)sharedController
{
  if (sharedInstance == nil)
    {
      sharedInstance = [self new];
    }
  return sharedInstance;
}

+ (GWLookInsideAction)actionForSpaceKeyWithSelectionCount:(NSUInteger)count
                                                  isOpen:(BOOL)isOpen
{
  /* Closing always wins: whatever is open closes on the next Space,
   * regardless of what happens to be selected at that moment. */
  if (isOpen)
    {
      return GWLookInsideActionClose;
    }
  if (count == 0)
    {
      return GWLookInsideActionNone;
    }
  return GWLookInsideActionOpen;
}

- (void)dealloc
{
  DESTROY(_panel);
  DESTROY(_paths);
  [super dealloc];
}

- (BOOL)isOpen
{
  return _open;
}

- (BOOL)toggleLookInsideForSelection:(NSArray *)selection
                         sourceWindow:(id)sourceWindow
{
  NSArray *paths = ([selection count] > 0) ? [selection valueForKey: @"path"] : nil;

  return [self toggleLookInsideForPaths: paths sourceWindow: sourceWindow];
}

- (BOOL)toggleLookInsideForPaths:(NSArray *)paths
                     sourceWindow:(id)sourceWindow
{
  return [self toggleLookInsideForPaths: paths sourceWindow: sourceWindow fullScreen: NO];
}

- (BOOL)toggleLookInsideForPaths:(NSArray *)paths
                     sourceWindow:(id)sourceWindow
                       fullScreen:(BOOL)fullScreen
{
  GWLookInsideAction action = [[self class] actionForSpaceKeyWithSelectionCount: [paths count]
                                                                        isOpen: _open];

  switch (action)
    {
    case GWLookInsideActionOpen:
      ASSIGN(_paths, paths);
      [self createAndShowPanelForPaths: paths sourceWindow: sourceWindow fullScreen: fullScreen];
      _open = YES;
      return YES;

    case GWLookInsideActionClose:
      [self close];
      return YES;

    case GWLookInsideActionNone:
    default:
      return NO;
    }
}

- (void)selectionDidChange:(NSArray *)paths
{
  if (!_open || [paths count] == 0 || [paths isEqual: _paths])
    {
      return;
    }
  ASSIGN(_paths, paths);
  [self showPathsInPanel: paths];
}

- (void)close
{
  if (_open)
    {
      [self destroyPanel];
      DESTROY(_paths);
      _open = NO;
    }
}

- (void)createAndShowPanelForPaths:(NSArray *)paths
                      sourceWindow:(id)sourceWindow
                        fullScreen:(BOOL)fullScreen
{
  /* Looked up by name (see the category note above) so this class never
   * links the window/AppKit-heavy GWLookInsidePanel implementation; the
   * real app always has GWLookInsidePanel.m linked in, so this resolves
   * there and only there. */
  Class panelClass = NSClassFromString(@"GWLookInsidePanel");
  id panel;

  if (panelClass == Nil)
    {
      return;
    }

  panel = [[panelClass alloc] initWithPaths: paths sourceWindow: sourceWindow];
  ASSIGN(_panel, panel);
  RELEASE(panel);
  [_panel showAnimatedInFullScreen: fullScreen];
}

- (void)showPathsInPanel:(NSArray *)paths
{
  [_panel showPaths: paths];
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
