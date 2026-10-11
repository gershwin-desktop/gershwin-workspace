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
static const CGFloat GWOpenItemGrowth = 2.2;
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
- (void)_start;
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

  return 1.0 - p * p;
}

+ (NSRect)iconPartOfRect:(NSRect)rect
{
  if (NSWidth (rect) <= NSHeight (rect) * 1.5)
    return rect;
  return NSMakeRect (NSMinX (rect), NSMinY (rect), NSHeight (rect), NSHeight (rect));
}

+ (void)playForNode:(FSNode *)node
           inWindow:(NSWindow *)window
       atScreenRect:(NSRect)screenRect
{
  NSView *content = [window contentView];
  NSRect rectInWindow;
  NSRect rectInContent;
  NSImage *anIcon;
  GWOpenItemAnimation *overlay;

  if (node == nil || content == nil || NSIsEmptyRect (screenRect)
      || GWOpenItemAnimationAllowed () == NO)
    return;

  rectInWindow = [window convertRectFromScreen: screenRect];
  rectInContent = [self iconPartOfRect: [content convertRect: rectInWindow fromView: nil]];
  anIcon = [[FSNodeRep sharedInstance]
             iconOfSize: (int) MIN (NSWidth (rectInContent), NSHeight (rectInContent))
                forNode: node];
  if (anIcon == nil)
    return;

  overlay = [[self alloc] initWithFrame: [content bounds]
                                   icon: anIcon
                               iconRect: rectInContent];
  /* last subview: drawn over the icons and everything else in the window */
  [content addSubview: overlay];
  [overlay _start];
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

- (void)_start
{
  startTime = [NSDate timeIntervalSinceReferenceDate];
  ASSIGN (timer, [NSTimer scheduledTimerWithTimeInterval: GWOpenItemTick
                                                  target: self
                                                selector: @selector(_tick:)
                                                userInfo: nil
                                                 repeats: YES]);
  [self setNeedsDisplayInRect: NSInsetRect (iconRect, -2, -2)];
}

- (CGFloat)_progress
{
  return MIN (1.0, ([NSDate timeIntervalSinceReferenceDate] - startTime) / GWOpenItemDuration);
}

- (void)_tick:(NSTimer *)aTimer
{
  CGFloat progress = [self _progress];
  NSRect now = [GWOpenItemAnimation rectForIconRect: iconRect progress: progress];

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
  [icon drawInRect: [GWOpenItemAnimation rectForIconRect: iconRect progress: progress]
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
