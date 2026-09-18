/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-2.0-or-later
 */

/* Spring-loaded folders: a folder the pointer rests on during a file drag
 * opens after a short delay, so the drag can go on into it and further down.
 *
 * Every kind of drag reports to the same loader - GNUstep's drag through the
 * destinations' dragging callbacks and the windows' drag events, the
 * free-position move through its own loop - so the timing, which windows were
 * opened for the drag and when they close again follow one set of rules. */

#ifndef FSN_SPRING_LOADER_H
#define FSN_SPRING_LOADER_H

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>

@class FSNode;
@class FSNSpringLoader;

/* A folder about to spring open flashes first, the way a button flashes when
 * it is pressed.  The destination draws that by showing or hiding the
 * highlight it uses while a drag is over the folder. */
@protocol FSNSpringFlashing <NSObject>
- (void)setSpringHighlightVisible:(BOOL)visible;
@end

/* What springing a folder open means is up to the application: a new window,
 * a browsing window moved to the folder, or a window that was open already.
 * Whatever it did is handed back as a token, and undoing the token must put
 * things back the way they were - but never close a window that was open
 * before the drag. */
/* Something that is not a folder can spring open too - an application
 * whose windows come to the front so the drag can go on into one of them.
 * Such a view says itself whether it can, and does it; nothing it does is
 * undone when the drag moves on. */
@protocol FSNSpringOpening <NSObject>
- (BOOL)springOpensItself;
- (void)springOpen;
@end

@protocol FSNSpringLoaderDelegate <NSObject>
/* The view is where the folder was found: a window need not spring open the
 * folder it already shows. */
- (BOOL)springLoader:(FSNSpringLoader *)loader
         mayOpenNode:(FSNode *)node
              inView:(NSView *)view;
- (id)springLoader:(FSNSpringLoader *)loader
          openNode:(FSNode *)node
          fromView:(NSView *)view;
- (void)springLoader:(FSNSpringLoader *)loader undo:(id)token;
- (NSWindow *)springLoader:(FSNSpringLoader *)loader windowForToken:(id)token;
@end

@interface FSNSpringLoader : NSObject
{
  id <FSNSpringLoaderDelegate> delegate;

  FSNode *armedNode;
  NSView *armedView;
  id <FSNSpringFlashing> flasher;
  NSTimeInterval armedAt;
  NSTimeInterval flashStartedAt;
  BOOL firedForArmedNode;

  NSMutableArray *chain;
  NSTimeInterval lastActivity;
  NSTimer *watchdog;
}

+ (FSNSpringLoader *)sharedLoader;

- (void)setDelegate:(id <FSNSpringLoaderDelegate>)aDelegate;

/* Whether springing is switched on, and how long the pointer has to rest on
 * a folder before it opens.  Both are read from the user defaults each time,
 * so a change in the preferences applies to the next drag. */
- (BOOL)isEnabled;
- (NSTimeInterval)delay;

/* The file paths a drag carries, or nil when it carries none: only file
 * drags spring folders open. */
+ (NSArray *)draggedPathsOfDraggingInfo:(id <NSDraggingInfo>)info;

/* The pointer of a file drag is on a folder in view.  Called for as long as
 * it stays there - GNUstep repeats the drag update while the pointer rests -
 * and that repetition is what times the delay and the flash. */
- (void)pointerRestsOnNode:(FSNode *)node
                    inView:(NSView *)view
                   flasher:(id <FSNSpringFlashing>)aFlasher
              draggedPaths:(NSArray *)paths;

/* The pointer left whatever folder view was reporting. */
- (void)pointerLeftView:(NSView *)view;

/* Window-level drag tracking.  A window passes every event it handles; the
 * loader picks out the drag events and learns from them which window the
 * pointer is in and where a drop landed. */
- (void)noteEvent:(NSEvent *)event inWindow:(NSWindow *)window;

/* The same facts for a drag that does not go through GNUstep's drag
 * machinery, the free-position move. */
- (void)dragIsOverWindow:(NSWindow *)window;
- (void)dragDroppedInWindow:(NSWindow *)window;
- (void)dragEnded;

@end

#endif
