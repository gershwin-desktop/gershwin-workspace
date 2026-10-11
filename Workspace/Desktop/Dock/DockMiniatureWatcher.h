/* DockMiniatureWatcher.h
 *
 * The Dock's side of the window manager's live miniature protocol (see
 * URSLiveMiniatureController.h in the window manager): it watches the root
 * window's list of windows being minimized or shown live, and answers for
 * the ones the Dock makes a tile for.
 *
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

#import <Foundation/Foundation.h>

@class DockMiniatureWatcher;

@protocol DockMiniatureWatcherDelegate
- (void)miniatureWatcherListChanged:(DockMiniatureWatcher *)watcher;
@end

@interface DockMiniatureWatcher : NSObject

/* nil when there is no X display to watch. */
- (id)initWithDelegate:(id<DockMiniatureWatcherDelegate>)delegate;
- (void)stop;

/* The windows (NSNumber) the window manager lists, in its order. */
- (NSArray *)listedWindows;

/* Writes where the window's tile is (root pixels); the first time, also
 * answers the window manager that dockWindow shows it.  The rect is only
 * written when it changed. */
- (void)placeTile:(NSRect)rect
        forWindow:(unsigned long)window
       dockWindow:(unsigned long)dockWindow;
- (void)forgetWindow:(unsigned long)window;

- (NSString *)titleOfWindow:(unsigned long)window;

@end
