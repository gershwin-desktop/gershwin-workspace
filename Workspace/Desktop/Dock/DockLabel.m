/* DockLabel.m
 *
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

#import "DockLabel.h"
#import "Dock.h"
#import "DockIcon.h"
#import "DockStack.h"
#import "DockStyleGeometry.h"

/* Long enough that sweeping across the Dock does not flash a label for
 * every icon on the way, short enough to feel like a response. */
static const NSTimeInterval DockLabelDelay = 0.35;
/* How often the pointer is looked at while it is on the Dock: neither the
 * magnification moving an icon under a still pointer nor the pointer
 * leaving the Dock sends the Dock's window an event. */
static const NSTimeInterval DockLabelPollInterval = 0.1;

static const CGFloat DockLabelFontSize = 13.0;
static const CGFloat DockLabelPadX = 10.0;
static const CGFloat DockLabelPadY = 4.0;
static const CGFloat DockLabelRadius = 6.0;
static const CGFloat DockLabelArrow = 7.0;
static const CGFloat DockLabelGap = 8.0;
static const CGFloat DockLabelMargin = 4.0;
/* A clear border around the label: the window manager draws no drop
 * shadow around a window whose edges are transparent, and a rectangular
 * shadow would outline the empty room beside the arrow. */
static const CGFloat DockLabelClearBorder = 4.0;

/* Never key or main: the label must not take the keyboard from the
 * application the user is working in. */
@interface DockLabelWindow : NSWindow
@end

@implementation DockLabelWindow

- (BOOL)canBecomeKeyWindow
{
  return NO;
}

- (BOOL)canBecomeMainWindow
{
  return NO;
}

@end


@interface DockLabelView : NSView
{
  NSString *text;
  DockLabelLayout layout;
}

- (void)setText:(NSString *)aText layout:(DockLabelLayout)aLayout;

@end

@implementation DockLabelView

+ (NSDictionary *)textAttributes
{
  static NSDictionary *attributes = nil;

  if (attributes == nil)
    {
      NSMutableParagraphStyle *style =
        AUTORELEASE ([[NSParagraphStyle defaultParagraphStyle] mutableCopy]);

      [style setLineBreakMode: NSLineBreakByTruncatingTail];
      [style setAlignment: NSCenterTextAlignment];
      attributes = [[NSDictionary alloc] initWithObjectsAndKeys:
        [NSFont systemFontOfSize: DockLabelFontSize], NSFontAttributeName,
        [NSColor whiteColor], NSForegroundColorAttributeName,
        style, NSParagraphStyleAttributeName,
        nil];
    }
  return attributes;
}

- (void)dealloc
{
  RELEASE (text);
  [super dealloc];
}

- (BOOL)isOpaque
{
  return NO;
}

- (void)setText:(NSString *)aText layout:(DockLabelLayout)aLayout
{
  ASSIGN (text, aText);
  layout = aLayout;
  [self setNeedsDisplay: YES];
}

- (void)drawRect:(NSRect)rect
{
  NSRect body = layout.body;
  NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect: body
                                                       xRadius: DockLabelRadius
                                                       yRadius: DockLabelRadius];
  NSBezierPath *arrow = [NSBezierPath bezierPath];
  NSSize size = [text sizeWithAttributes: [DockLabelView textAttributes]];
  NSRect textRect;
  NSAffineTransform *shift = [NSAffineTransform transform];

  [shift translateXBy: DockLabelClearBorder yBy: DockLabelClearBorder];
  [shift concat];

  /* The arrow's base runs along the box's edge facing the icon, so that
   * box and arrow read as one shape. */
  [arrow moveToPoint: layout.tip];
  if (layout.base.x == layout.tip.x)
    {
      [arrow lineToPoint: NSMakePoint(layout.base.x - DockLabelArrow, layout.base.y)];
      [arrow lineToPoint: NSMakePoint(layout.base.x + DockLabelArrow, layout.base.y)];
    }
  else
    {
      [arrow lineToPoint: NSMakePoint(layout.base.x, layout.base.y - DockLabelArrow)];
      [arrow lineToPoint: NSMakePoint(layout.base.x, layout.base.y + DockLabelArrow)];
    }
  [arrow closePath];
  [path appendBezierPath: arrow];
  [path setWindingRule: NSNonZeroWindingRule];

  [[NSColor colorWithCalibratedWhite: 0.0 alpha: 0.78] set];
  [path fill];

  textRect = NSMakeRect(NSMinX(body) + DockLabelPadX,
                        NSMidY(body) - size.height / 2,
                        NSWidth(body) - 2 * DockLabelPadX,
                        size.height);
  [text drawInRect: textRect withAttributes: [DockLabelView textAttributes]];
}

@end


@implementation DockLabel
{
  NSWindow *dockWindow;
  DockLabelWindow *window;
  DockLabelView *view;
  /* The icon the pointer is on, retained so that an icon taken out of the
   * Dock while its label is up cannot leave a dangling pointer here. */
  DockIcon *icon;
  /* After a press, the icon whose label stays away until the pointer has
   * left it: the click was meant for the icon, not for its name. */
  DockIcon *suppressed;
  NSTimer *showTimer;
  NSTimer *pollTimer;
  NSRect shownRect;
}

+ (DockLabel *)sharedLabel
{
  static DockLabel *shared = nil;

  if (shared == nil)
    shared = [DockLabel new];
  return shared;
}

+ (void)noteEvent:(NSEvent *)event inWindow:(NSWindow *)aWindow
{
  DockLabel *label = [self sharedLabel];

  label->dockWindow = aWindow;

  switch ([event type])
    {
      case NSMouseMoved:
        [label pointerOverIcon: [label iconAtWindowPoint: [event locationInWindow]]];
        break;

      case NSLeftMouseDown:
      case NSRightMouseDown:
      case NSOtherMouseDown:
      case NSLeftMouseDragged:
      case NSRightMouseDragged:
      case NSOtherMouseDragged:
        ASSIGN (label->suppressed,
                [label iconAtWindowPoint: [event locationInWindow]]);
        [label hideAndForget: YES];
        break;

      default:
        break;
    }
}

+ (void)hide
{
  DockLabel *label = [self sharedLabel];

  [label hideAndForget: YES];
  [label stopPolling];
}

- (void)dealloc
{
  [showTimer invalidate];
  [pollTimer invalidate];
  RELEASE (icon);
  RELEASE (suppressed);
  RELEASE (view);
  RELEASE (window);
  [super dealloc];
}

- (DockIcon *)iconAtWindowPoint:(NSPoint)p
{
  NSView *hit = [[[dockWindow contentView] superview] hitTest: p];

  while (hit != nil && [hit isKindOfClass: [DockIcon class]] == NO)
    hit = [hit superview];
  return (DockIcon *)hit;
}

- (void)startPolling
{
  NSRunLoop *loop = [NSRunLoop currentRunLoop];

  if (pollTimer != nil)
    return;
  pollTimer = [NSTimer timerWithTimeInterval: DockLabelPollInterval
                                      target: self
                                    selector: @selector(poll:)
                                    userInfo: nil
                                     repeats: YES];
  /* Also while a drag or a menu is tracked, so that the label goes away
   * when one starts. */
  [loop addTimer: pollTimer forMode: NSDefaultRunLoopMode];
  [loop addTimer: pollTimer forMode: NSEventTrackingRunLoopMode];
}

- (void)stopPolling
{
  [pollTimer invalidate];
  pollTimer = nil;
}

- (void)poll:(NSTimer *)timer
{
  NSPoint p = [NSEvent mouseLocation];
  NSRect frame = [dockWindow frame];

  if (dockWindow == nil || [dockWindow isVisible] == NO
      || NSPointInRect(p, frame) == NO)
    {
      DESTROY (suppressed);
      [self hideAndForget: YES];
      [self stopPolling];
      return;
    }

  [self pointerOverIcon:
          [self iconAtWindowPoint: NSMakePoint(p.x - NSMinX(frame),
                                               p.y - NSMinY(frame))]];
}

- (BOOL)mayShow
{
  Dock *dock = (Dock *)[dockWindow contentView];

  /* A stack is about the icon's contents, a drag about where it goes; a
   * name over either is in the way. */
  return [DockStack isShown] == NO
         && ([dock respondsToSelector: @selector(isDragInProgress)] == NO
             || [dock isDragInProgress] == NO)
         && [NSEvent pressedMouseButtons] == 0;
}

- (void)pointerOverIcon:(DockIcon *)anIcon
{
  /* While the pointer is anywhere on the Dock, even between icons: the
   * magnification can move an icon under it without an event. */
  [self startPolling];

  if (anIcon == nil)
    {
      DESTROY (suppressed);
      [self hideAndForget: YES];
      return;
    }

  if (anIcon == suppressed)
    return;
  DESTROY (suppressed);

  if ([self mayShow] == NO)
    {
      [self hideAndForget: NO];
      return;
    }

  if (anIcon != icon)
    {
      ASSIGN (icon, anIcon);
      [showTimer invalidate];
      showTimer = nil;
    }

  if ([window isVisible])
    {
      /* Moving on to the next icon changes the label at once rather than
       * making the user wait again, and the label follows an icon that
       * the magnification moves and grows under a still pointer. */
      [self showNow];
      return;
    }

  if (showTimer == nil)
    showTimer = [NSTimer scheduledTimerWithTimeInterval: DockLabelDelay
                                                 target: self
                                               selector: @selector(showTimerFired:)
                                               userInfo: nil
                                                repeats: NO];
}

- (void)showTimerFired:(NSTimer *)timer
{
  showTimer = nil;
  if ([self mayShow])
    [self showNow];
}

- (void)createWindow
{
  window = [[DockLabelWindow alloc] initWithContentRect: NSMakeRect(0, 0, 10, 10)
                                              styleMask: NSBorderlessWindowMask
                                                backing: NSBackingStoreBuffered
                                                  defer: NO];
  [window setReleasedWhenClosed: NO];
  [window setExcludedFromWindowsMenu: YES];
  /* Above the Dock, like its stacks. */
  [window setLevel: NSPopUpMenuWindowLevel];
  [window setOpaque: NO];
  [window setBackgroundColor: [NSColor clearColor]];
  [window setHasShadow: NO];
  /* Clicks go through to whatever is under it. */
  [window setIgnoresMouseEvents: YES];

  view = [[DockLabelView alloc] initWithFrame: NSMakeRect(0, 0, 10, 10)];
  [window setContentView: view];
}

- (void)showNow
{
  NSString *text = [icon labelText];
  Dock *dock = (Dock *)[icon dock];
  NSWindow *iconWindow = [icon window];
  CGFloat sf;
  NSRect iconRect, screen, frame;
  NSSize size;
  DockLabelLayout layout;

  if ([text length] == 0 || iconWindow == nil || dock == nil)
    {
      [self hideAndForget: NO];
      return;
    }

  /* Screen and window frames are device pixels; the label is laid out
   * in points, like everything it is drawn with. */
  sf = [iconWindow userSpaceScaleFactor];
  if (sf <= 0.0)
    sf = 1.0;
  iconRect = [iconWindow convertRectToScreen:
                           [icon convertRect: [icon imageRect] toView: nil]];
  if (window != nil && [window isVisible] && NSEqualRects(iconRect, shownRect))
    return;
  shownRect = iconRect;
  screen = [[iconWindow screen] frame];

  size = [text sizeWithAttributes: [DockLabelView textAttributes]];
  size.width = ceil(size.width) + 2 * DockLabelPadX;
  size.height = ceil(size.height) + 2 * DockLabelPadY;

  layout = DockLabelPlace(NSMakeRect(NSMinX(iconRect) / sf, NSMinY(iconRect) / sf,
                                     NSWidth(iconRect) / sf, NSHeight(iconRect) / sf),
                          size, [dock edge],
                          NSMakeRect(NSMinX(screen) / sf, NSMinY(screen) / sf,
                                     NSWidth(screen) / sf, NSHeight(screen) / sf),
                          DockLabelGap, DockLabelArrow, DockLabelRadius,
                          DockLabelMargin);

  if (window == nil)
    [self createWindow];

  /* A borderless window's frame is its content, in pixels. */
  frame = NSInsetRect(layout.frame, -DockLabelClearBorder, -DockLabelClearBorder);
  frame = NSMakeRect(round(NSMinX(frame) * sf), round(NSMinY(frame) * sf),
                     round(NSWidth(frame) * sf), round(NSHeight(frame) * sf));
  [window setFrame: frame display: NO];
  [view setText: text layout: layout];
  [window orderFront: nil];
  /* Shown from inside the Dock's event handling, a new window is mapped
   * but not drawn until something else redraws it. */
  [window display];
}

- (void)hideAndForget:(BOOL)forget
{
  [showTimer invalidate];
  showTimer = nil;
  shownRect = NSZeroRect;
  if ([window isVisible])
    [window orderOut: nil];
  if (forget)
    DESTROY (icon);
}

@end
