/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

#import "GWOpenItemAnimation.h"
#import "FSNode.h"
#import "FSNodeRep.h"

/* How much larger than the icon it ends, and how long it takes: long enough
   to see where the item was, short enough to be over before the
   application's window appears. */
static const CGFloat GWOpenItemGrowth = 4.4;
static const NSTimeInterval GWOpenItemDuration = 0.28;
static const NSTimeInterval GWOpenItemTick = 1.0 / 60.0;

static BOOL GWOpenItemAnimationAllowed(void)
{
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
  id enabled = [defaults objectForKey: @"GSWindowAnimationEnabled"];

  if (enabled != nil && [enabled boolValue] == NO)
    return NO;
  return [defaults boolForKey: @"GSReduceMotion"] == NO;
}

@interface GWOpenItemAnimation ()
- (id)initWithFrame:(NSRect)frame icon:(NSImage *)anIcon iconRect:(NSRect)rect;
- (void)_startAfterDelay:(NSTimeInterval)delay;
- (void)_tick:(NSTimer *)aTimer;
- (void)_finish;
@end

@implementation GWOpenItemAnimation

+ (NSRect)rectForIconRect:(NSRect)rect progress:(CGFloat)progress
{
  /* ease out: fast at first, settling at the end */
  CGFloat eased = 1.0 - (1.0 - progress) * (1.0 - progress);
  CGFloat scale = 1.0 + (GWOpenItemGrowth - 1.0) * eased;
  CGFloat w = NSWidth (rect) * scale;
  CGFloat h = NSHeight (rect) * scale;

  return NSMakeRect (NSMidX (rect) - w / 2, NSMidY (rect) - h / 2, w, h);
}

+ (CGFloat)opacityAtProgress:(CGFloat)progress
{
  CGFloat p = MAX (0.0, MIN (1.0, progress));

  /* Smoothstep down to 0: it flattens out at the end, so the last frames
     drawn before the overlay goes away are already all but invisible
     (1 - p*p still showed 12% one tick before the end, then vanished). */
  return 1.0 - p * p * (3.0 - 2.0 * p);
}

+ (NSRect)rect:(NSRect)rect keptInside:(NSRect)area
{
  NSRect r = rect;

  if (NSWidth (r) >= NSWidth (area))
    {
      r.origin.x = NSMidX (area) - NSWidth (r) / 2;
    }
  else
    {
      r.origin.x = MAX (NSMinX (area), MIN (NSMinX (r), NSMaxX (area) - NSWidth (r)));
    }
  if (NSHeight (r) >= NSHeight (area))
    {
      r.origin.y = NSMidY (area) - NSHeight (r) / 2;
    }
  else
    {
      r.origin.y = MAX (NSMinY (area), MIN (NSMinY (r), NSMaxY (area) - NSHeight (r)));
    }
  return r;
}

+ (NSRect)rect:(NSRect)rect fittedToAspectOfSize:(NSSize)size
{
  CGFloat scale;
  CGFloat w;
  CGFloat h;

  if (size.width <= 0 || size.height <= 0)
    {
      return rect;
    }
  scale = MIN (NSWidth (rect) / size.width, NSHeight (rect) / size.height);
  w = size.width * scale;
  h = size.height * scale;
  return NSMakeRect (NSMidX (rect) - w / 2, NSMidY (rect) - h / 2, w, h);
}

+ (NSRect)iconRectInOverlay:(NSView *)overlay
                    forRect:(NSRect)rect
                     ofView:(NSView *)view
{
  /* Into the overlay itself, not into the view it lies over: the overlay
     draws unflipped, while the browsing viewer's content (an NSSplitView)
     is flipped, so a rect taken over from the host as it is would grow at
     the mirrored height. */
  return [overlay convertRect: rect fromView: view];
}

+ (void)playImage:(NSImage *)image
           ofNode:(FSNode *)node
         inWindow:(NSWindow *)window
     atScreenRect:(NSRect)screenRect
       afterDelay:(NSTimeInterval)delay
{
  NSView *host = [[window contentView] superview];
  NSRect rectInOverlay;
  NSImage *anIcon = image;
  GWOpenItemAnimation *overlay;

  if (node == nil || host == nil || NSIsEmptyRect (screenRect)
      || GWOpenItemAnimationAllowed () == NO)
    {
      return;
    }

  /* Laid over the window's content from the view that holds it, not added
     to the content view: in a browsing viewer that is an NSSplitView, which
     takes every subview for a pane and would draw a divider after it. */
  overlay = [[self alloc] initWithFrame: [host bounds]
                                   icon: nil
                               iconRect: NSZeroRect];
  [host addSubview: overlay];
  rectInOverlay = [self iconRectInOverlay: overlay
                                  forRect: [window convertRectFromScreen: screenRect]
                                   ofView: nil];
  if (anIcon == nil)
    {
      anIcon = [[FSNodeRep sharedInstance]
                 iconOfSize: (int) MIN (NSWidth (rectInOverlay), NSHeight (rectInOverlay))
                    forNode: node];
    }
  if (anIcon == nil)
    {
      [overlay removeFromSuperview];
      RELEASE (overlay);
      return;
    }
  /* The rect is the picture's own already; fitting again only guards
     against a rect from a rep that knows no picture (its whole bounds). */
  rectInOverlay = [self rect: rectInOverlay fittedToAspectOfSize: [anIcon size]];
  /* Grown near a monitor's edge the picture would be cut off by it (or by
     the window); it moves back onto the monitor instead, at full size.  The
     desktop window spans every monitor, so the window alone is not enough. */
  overlay->area = [overlay bounds];
  {
    NSPoint center = NSMakePoint (NSMidX (screenRect), NSMidY (screenRect));
    NSEnumerator *e = [[NSScreen screens] objectEnumerator];
    NSScreen *screen;

    while ((screen = [e nextObject]) != nil)
      {
        if (NSPointInRect (center, [screen frame]))
          {
            NSRect monitor = [overlay convertRect: [window convertRectFromScreen: [screen frame]]
                                         fromView: nil];

            if (NSIsEmptyRect (NSIntersectionRect (overlay->area, monitor)) == NO)
              {
                overlay->area = NSIntersectionRect (overlay->area, monitor);
              }
            break;
          }
      }
  }
  ASSIGN (overlay->icon, anIcon);
  overlay->iconRect = rectInOverlay;
  overlay->lastDrawnRect = rectInOverlay;
  [overlay _startAfterDelay: delay];
  RELEASE (overlay);   /* the superview and the timer keep it */
}

- (id)initWithFrame:(NSRect)frame icon:(NSImage *)anIcon iconRect:(NSRect)rect
{
  self = [super initWithFrame: frame];
  if (self)
    {
      ASSIGN (icon, anIcon);
      iconRect = rect;
      lastDrawnRect = rect;
      [self setAutoresizingMask: NSViewWidthSizable | NSViewHeightSizable];
    }
  return self;
}

- (void)dealloc
{
  [timer invalidate];
  RELEASE (timer);
  RELEASE (icon);
  [super dealloc];
}

- (BOOL)isOpaque
{
  return NO;
}

/* Purely decorative: clicks go to whatever is beneath. */
- (NSView *)hitTest:(NSPoint)aPoint
{
  return nil;
}

- (void)_startAfterDelay:(NSTimeInterval)delay
{
  /* The clock starts at the first tick, not here: the open that plays it
     may hold the run loop a while longer (a sheet sliding away after
     "Trust and Run", a launch), and a clock started now would be over
     before a single frame was drawn. */
  startTime = 0;
  ASSIGN (timer, [NSTimer scheduledTimerWithTimeInterval: GWOpenItemTick
                                                  target: self
                                                selector: @selector(_tick:)
                                                userInfo: nil
                                                 repeats: YES]);
  if (delay > 0)
    {
      [timer setFireDate: [NSDate dateWithTimeIntervalSinceNow: delay]];
    }
  [self setNeedsDisplayInRect: NSInsetRect (iconRect, -2, -2)];
}

+ (CGFloat)progressAtTime:(NSTimeInterval)now startedAt:(NSTimeInterval)start
{
  if (start <= 0)
    {
      return 0.0;
    }
  return MAX (0.0, MIN (1.0, (now - start) / GWOpenItemDuration));
}

- (CGFloat)_progress
{
  return [GWOpenItemAnimation progressAtTime: [NSDate timeIntervalSinceReferenceDate]
                                   startedAt: startTime];
}

- (void)_tick:(NSTimer *)aTimer
{
  CGFloat progress;

  if (startTime <= 0)
    {
      startTime = [NSDate timeIntervalSinceReferenceDate];
    }
  progress = [self _progress];
  NSRect now = [GWOpenItemAnimation rect: [GWOpenItemAnimation rectForIconRect: iconRect
                                                                     progress: progress]
                               keptInside: area];

  /* repaint where the icon was and where it is now */
  [self setNeedsDisplayInRect: NSInsetRect (NSUnionRect (lastDrawnRect, now), -2, -2)];
  lastDrawnRect = now;
  if (progress >= 1.0)
    [self _finish];
}

- (void)drawRect:(NSRect)rect
{
  CGFloat progress = [self _progress];

  if (progress >= 1.0)
    return;
  [icon drawInRect: [GWOpenItemAnimation rect: [GWOpenItemAnimation rectForIconRect: iconRect
                                                                           progress: progress]
                                     keptInside: area]
          fromRect: NSZeroRect
         operation: NSCompositeSourceOver
          fraction: [GWOpenItemAnimation opacityAtProgress: progress]];
}

- (void)_finish
{
  [timer invalidate];
  DESTROY (timer);
  [[self superview] setNeedsDisplayInRect: NSInsetRect ([self convertRect: lastDrawnRect
                                                                    toView: [self superview]], -2, -2)];
  [self removeFromSuperview];   /* may deallocate self */
}

@end
