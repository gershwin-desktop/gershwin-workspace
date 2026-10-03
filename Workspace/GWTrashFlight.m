/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

#import <GNUstepGUI/GSDisplayServer.h>
#import <GNUstepBase/GNUstep.h>

#import "GWTrashFlight.h"
#import "GWTrashFlightPath.h"
#import "FSNFunctions.h"

/* Roughly what "0.45 s" and "a few tens of milliseconds" ask for; kept as
 * named constants rather than literals scattered through the timer code. */
static const NSTimeInterval GWTrashFlightDuration = 0.45;
static const NSTimeInterval GWTrashFlightStaggerStep = 0.035;
/* The display cadence skill: drive from a timer at this rate, but always
 * compute position from elapsed wall-clock time, never from a frame count -
 * the timer is not guaranteed to fire exactly on schedule. */
static const NSTimeInterval GWTrashFlightTickInterval = 1.0 / 60.0;

/* One flying icon's own start point and stagger offset; every item shares
 * the same destination (the flight's trashRect) and duration. */
@interface GWTrashFlightItem : NSObject
{
@public
  NSRect startRect;
  NSImage *image;
  NSTimeInterval startDelay;
}
@end

@implementation GWTrashFlightItem
- (void)dealloc
{
  RELEASE (image);
  [super dealloc];
}
@end


@interface GWTrashFlight (Private)
- (void)_tick:(NSTimer *)aTimer;
- (void)_drawFrameWithRects:(NSArray *)rects
                      images:(NSArray *)imgs
                   unionRect:(NSRect)uRect;
- (void)_createOverlayWindowIfNeeded;
- (void)_finish;
@end


@implementation GWTrashFlight

- (id)initWithItems:(NSArray *)sourceItems
          trashRect:(NSRect)aTrashRect
         completion:(void (^)(void))aCompletion
{
  self = [super init];

  if (self)
    {
      NSMutableArray *built = [NSMutableArray arrayWithCapacity: [sourceItems count]];
      NSUInteger i, count = [sourceItems count];

      trashRect = aTrashRect;
      completion = [aCompletion copy];
      flightDuration = GWTrashFlightDuration;
      staggerStep = GWTrashFlightStaggerStep;

      for (i = 0; i < count; i++)
        {
          NSDictionary *d = [sourceItems objectAtIndex: i];
          NSValue *rv = [d objectForKey: @"rect"];
          NSImage *img = [d objectForKey: @"image"];
          GWTrashFlightItem *item;

          /* A source with no usable rect or picture cannot be flown -
             skip it rather than animate a blank patch of screen. */
          if (rv == nil || img == nil)
            continue;

          item = AUTORELEASE ([GWTrashFlightItem new]);
          item->startRect = [rv rectValue];
          ASSIGN (item->image, img);
          item->startDelay = i * staggerStep;

          [built addObject: item];
        }

      ASSIGN (items, [built makeImmutableCopyOnFail: NO]);
    }

  return self;
}

- (void)dealloc
{
  /* -_finish always runs before this point (either the timer's last tick
     reached it, or -start's immediate performSelector: did for an empty
     flight), so the timer is already invalidated and the overlay already
     hidden; these are just the owning releases. */
  [timer invalidate];
  RELEASE (timer);
  [overlay orderOut: nil];
  RELEASE (overlay);
  RELEASE (items);
  [completion release];
  [super dealloc];
}

- (void)start
{
  /* Keeps itself alive for exactly the flight's duration: the caller uses
     this the way it would a fire-and-forget NSSound (create, -start, and
     drop its own reference), and the scheduled timer's own retain of self
     as its target cannot be relied on past the moment -_tick: invalidates
     it from inside its own call - a timer that is its only owner would
     free the object out from under the rest of that same method. */
  RETAIN (self);

  if ([items count] == 0)
    {
      [self performSelector: @selector(_finish) withObject: nil afterDelay: 0.0];
      return;
    }

  startTime = [NSDate timeIntervalSinceReferenceDate];
  timer = RETAIN ([NSTimer scheduledTimerWithTimeInterval: GWTrashFlightTickInterval
                                                    target: self
                                                  selector: @selector(_tick:)
                                                  userInfo: nil
                                                   repeats: YES]);
  [self _tick: nil];
}

@end


@implementation GWTrashFlight (Private)

- (void)_tick:(NSTimer *)aTimer
{
  NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
  NSTimeInterval elapsedTotal = now - startTime;
  NSMutableArray *activeRects = [NSMutableArray arrayWithCapacity: [items count]];
  NSMutableArray *activeImages = [NSMutableArray arrayWithCapacity: [items count]];
  NSRect unionRect = NSZeroRect;
  BOOL haveUnion = NO;
  BOOL allDone = YES;
  NSUInteger i, count = [items count];

  for (i = 0; i < count; i++)
    {
      GWTrashFlightItem *item = [items objectAtIndex: i];
      NSTimeInterval localElapsed = elapsedTotal - item->startDelay;
      CGFloat t;
      NSRect r;

      if (localElapsed < 0.0)
        {
          /* Staggered start: this one has not begun yet. */
          allDone = NO;
          continue;
        }

      t = localElapsed / flightDuration;
      if (t < 1.0)
        allDone = NO;
      if (t > 1.0)
        t = 1.0;

      r = GWTrashFlightRectAtTime (item->startRect, trashRect, t);
      unionRect = haveUnion ? NSUnionRect (unionRect, r) : r;
      haveUnion = YES;

      [activeRects addObject: [NSValue valueWithRect: r]];
      [activeImages addObject: item->image];
    }

  if (haveUnion)
    [self _drawFrameWithRects: activeRects images: activeImages unionRect: unionRect];
  else if (overlay != nil)
    [overlay orderOut: nil];

  if (allDone)
    {
      [timer invalidate];
      DESTROY (timer);
      [overlay orderOut: nil];
      [self _finish];
    }
}

/* Redraws the whole overlay window for this frame: one composite picture
   holding every active icon at its own current rect, shaped the way
   FSNIconDragSession.m shapes its own drag image (see FSNShapeableImage's
   doc comment and the gnustep-shaped-drag-window skill) so nothing but the
   icons themselves is ever visible.  Reshaping every frame - rather than
   building the shape once, as a drag image that never changes size can -
   is unavoidable here: the icons shrink as they approach the Trash, and a
   shape built for one size does not fit a window resized to another.  This
   stays cheap because the window only ever spans the CURRENT icons' own
   rects, not the whole path they will travel. */
- (void)_drawFrameWithRects:(NSArray *)rects
                      images:(NSArray *)imgs
                   unionRect:(NSRect)uRect
{
  NSImage *picture;
  NSImage *shaped;
  NSImageView *view;
  CGFloat scale;
  NSUInteger i, n = [rects count];

  [self _createOverlayWindowIfNeeded];

  picture = AUTORELEASE ([[NSImage alloc] initWithSize: uRect.size]);
  [picture setBackgroundColor: [NSColor clearColor]];
  [picture lockFocus];
  for (i = 0; i < n; i++)
    {
      NSRect r = [[rects objectAtIndex: i] rectValue];
      NSImage *img = [imgs objectAtIndex: i];
      NSRect local = NSMakeRect (r.origin.x - uRect.origin.x,
                                 r.origin.y - uRect.origin.y,
                                 r.size.width, r.size.height);

      [img drawInRect: local
              fromRect: NSZeroRect
             operation: NSCompositeSourceOver
              fraction: 1.0];
    }
  [picture unlockFocus];

  scale = [overlay userSpaceScaleFactor];
  shaped = FSNShapeableImage (picture, scale);

  [overlay setFrame: uRect display: NO];
  view = (NSImageView *)[overlay contentView];
  [view setFrame: NSMakeRect (0, 0, uRect.size.width, uRect.size.height)];
  [view setImage: shaped];

  /* Must happen before the first -orderFront: (a window shown unshaped even
     once goes on showing whatever was beneath it - see
     FSNIconDragSession.m), and again every time the shape changes. */
  [GSServerForWindow (overlay) restrictWindow: [overlay windowNumber]
                                      toImage: shaped];

  if ([overlay isVisible] == NO)
    [overlay orderFront: nil];
  else
    [overlay display];
}

- (void)_createOverlayWindowIfNeeded
{
  NSImageView *view;

  if (overlay != nil)
    return;

  /* Same recipe as FSNIconDragSession's own overlay: borderless, drawn
     straight to the screen, above every window, and never a target for
     clicks - the flight is purely decorative. */
  overlay = [[NSWindow alloc] initWithContentRect: NSMakeRect (0, 0, 1, 1)
                                        styleMask: NSBorderlessWindowMask
                                          backing: NSBackingStoreNonretained
                                            defer: NO];
  [overlay setReleasedWhenClosed: NO];
  [overlay setLevel: NSPopUpMenuWindowLevel];
  [overlay setBackgroundColor: [NSColor clearColor]];
  [overlay setIgnoresMouseEvents: YES];

  view = AUTORELEASE ([[NSImageView alloc] initWithFrame: NSMakeRect (0, 0, 1, 1)]);
  [view setImageFrameStyle: NSImageFrameNone];
  [overlay setContentView: view];
}

- (void)_finish
{
  if (finished)
    return;

  finished = YES;

  if (completion != NULL)
    completion ();

  RELEASE (self);   /* balances -start's retain; may deallocate self here */
}

@end
