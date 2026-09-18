/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-2.0-or-later
 */

#import <GNUstepGUI/GSDisplayServer.h>

#import "FSNIconDragSession.h"
#import "FSNSpringLoader.h"
#import "FSNIcon.h"
#import "FSNode.h"

/* The stacking order costs a round trip to the X server, and motion arrives
 * far faster than windows are raised or opened. */
static const NSTimeInterval FSNWindowOrderLifetime = 0.25;

static NSInteger FSNIconDragSequence = 0;

/* The alpha, in 256ths, up to which the X backend leaves a pixel out of a
 * window's shape (ALPHA_THRESHOLD in libs-back's XGServerWindow.m). */
static const CGFloat FSNShapeAlphaThreshold = 158;


@interface FSNIconDragSession (Private)
- (void)buildImage;
- (void)showOverlayAtScreenPoint:(NSPoint)p;
- (void)hideOverlay;
- (void)setIconsHidden:(BOOL)hidden;
- (NSView *)dropViewInWindow:(NSWindow *)window atPoint:(NSPoint)point;
- (void)leaveTarget;
@end


@implementation FSNIconDragSession

- (id)initWithIcons:(NSArray *)draggedIcons
             source:(id)sourceIcon
           inWindow:(NSWindow *)window
          grabPoint:(NSPoint)grabPoint
{
  self = [super init];

  if (self)
    {
      NSMutableArray *p = [NSMutableArray arrayWithCapacity: [draggedIcons count]];
      NSRect group = NSZeroRect;
      NSUInteger i;

      /* Taken now, while the pointer and the icons are where the gesture
       * began: by the time the icons leave their view, the last position
       * they were drawn at can be a frame behind the pointer. */
      for (i = 0; i < [draggedIcons count]; i++)
        {
          NSView *icon = [draggedIcons objectAtIndex: i];
          NSRect r = [icon convertRect: [icon bounds] toView: nil];

          group = (i == 0) ? r : NSUnionRect(group, r);
        }
      grabOffset = NSMakePoint(grabPoint.x - group.origin.x,
                               grabPoint.y - group.origin.y);

      ASSIGN (icons, draggedIcons);
      ASSIGN (source, sourceIcon);
      ASSIGN (sourceWindow, window);

      for (i = 0; i < [draggedIcons count]; i++)
        [p addObject: [[[draggedIcons objectAtIndex: i] node] path]];
      ASSIGN (paths, p);

      sequence = ++FSNIconDragSequence;
    }

  return self;
}

- (void)dealloc
{
  /* No dragging messages from here: the views would be handed an object
   * that is going away. */
  RELEASE (targetView);
  RELEASE (targetWindow);
  [overlay close];
  RELEASE (overlay);
  RELEASE (image);
  RELEASE (windowOrder);
  RELEASE (paths);
  RELEASE (icons);
  RELEASE (source);
  RELEASE (sourceWindow);
  [super dealloc];
}

- (NSArray *)paths
{
  return paths;
}

- (NSWindow *)windowAtScreenPoint:(NSPoint)p
{
  NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
  NSUInteger i;

  if (windowOrder == nil || (now - windowOrderTime) >= FSNWindowOrderLifetime)
    {
      ASSIGN (windowOrder, [NSApp orderedWindows]);
      windowOrderTime = now;
    }

  for (i = 0; i < [windowOrder count]; i++)
    {
      NSWindow *w = [windowOrder objectAtIndex: i];

      if (w == overlay || [w isVisible] == NO || [w isMiniaturized])
        continue;
      if (NSPointInRect(p, [w frame]))
        return w;
    }

  return nil;
}

- (BOOL)isAway
{
  return away;
}

- (void)dragAwayOverWindow:(NSWindow *)window atScreenPoint:(NSPoint)p
{
  NSView *view = nil;

  if (away == NO)
    {
      if (pboard == nil)
        {
          /* The views underneath read the dragged files from the drag
           * pasteboard, as they do for any drag. */
          ASSIGN (pboard, [NSPasteboard pasteboardWithName: NSDragPboard]);
          [pboard declareTypes: [NSArray arrayWithObject: NSFilenamesPboardType]
                         owner: nil];
          [pboard setPropertyList: paths forType: NSFilenamesPboardType];
        }
      if (image == nil)
        [self buildImage];

      [self setIconsHidden: YES];
      away = YES;
    }

  [self showOverlayAtScreenPoint: p];

  if (window != targetWindow)
    {
      [self leaveTarget];
      ASSIGN (targetWindow, window);
    }

  if (targetWindow == nil)
    return;

  location = [targetWindow convertScreenToBase: p];
  view = [self dropViewInWindow: targetWindow atPoint: location];

  if (view != targetView)
    {
      if (targetView != nil)
        [targetView draggingExited: self];
      ASSIGN (targetView, view);
      targetOperation = (view != nil) ? [view draggingEntered: self]
                                      : NSDragOperationNone;
    }
  else if (view != nil)
    {
      targetOperation = [view draggingUpdated: self];
    }

  [[FSNSpringLoader sharedLoader] dragIsOverWindow: targetWindow];
}

- (void)dragAwayRests
{
  if (targetView != nil)
    targetOperation = [targetView draggingUpdated: self];
  if (targetWindow != nil)
    [[FSNSpringLoader sharedLoader] dragIsOverWindow: targetWindow];
}

- (void)returnToSource
{
  if (away == NO)
    return;

  [self leaveTarget];
  [self hideOverlay];
  [self setIconsHidden: NO];
  away = NO;
}

- (BOOL)dropAtScreenPoint:(NSPoint)p
{
  BOOL accepted = NO;
  NSView *view = RETAIN (targetView);
  NSDragOperation op = targetOperation;

  /* The image goes before the views are told: the drop may run a
   * confirmation panel, and the image must not float over it. */
  [self hideOverlay];

  if (targetWindow != nil)
    location = [targetWindow convertScreenToBase: p];

  /* A window the items are dropped into is where the user put them, and the
   * loader must know before a confirmation panel can run.  Letting go where
   * nothing takes the drop - a title bar, a window's edge - puts nothing
   * anywhere, so whatever sprang open closes as after any cancelled drag. */
  if (targetWindow != nil && view != nil && op != NSDragOperationNone)
    [[FSNSpringLoader sharedLoader] dragDroppedInWindow: targetWindow];
  else
    [[FSNSpringLoader sharedLoader] dragEnded];

  if (view != nil && op != NSDragOperationNone
      && [view prepareForDragOperation: self]
      && [view performDragOperation: self])
    {
      [view concludeDragOperation: self];
      accepted = YES;
    }
  else if (view != nil)
    {
      [view draggingExited: self];
    }

  RELEASE (view);
  DESTROY (targetView);
  DESTROY (targetWindow);
  away = NO;

  return accepted;
}


/* NSDraggingInfo */

- (NSWindow *)draggingDestinationWindow
{
  return targetWindow;
}

- (NSPoint)draggingLocation
{
  return location;
}

- (NSPasteboard *)draggingPasteboard
{
  return pboard;
}

- (NSInteger)draggingSequenceNumber
{
  return sequence;
}

- (id)draggingSource
{
  return source;
}

- (NSDragOperation)draggingSourceOperationMask
{
  return NSDragOperationEvery;
}

- (NSImage *)draggedImage
{
  return image;
}

- (NSPoint)draggedImageLocation
{
  if (targetWindow == nil || overlay == nil)
    return NSZeroPoint;

  return [targetWindow convertScreenToBase: [overlay frame].origin];
}

- (void)slideDraggedImageTo:(NSPoint)screenPoint
{
}

- (NSArray *)namesOfPromisedFilesDroppedAtDestination:(NSURL *)dropDestination
{
  return nil;
}

@end


@implementation FSNIconDragSession (Private)

/* The icons as they look in their view, side by side as they are placed
 * there. */
- (void)buildImage
{
  NSView *container = [[icons objectAtIndex: 0] superview];
  NSRect group = NSZeroRect;
  NSBitmapImageRep *bitmap;
  NSImage *picture;
  NSUInteger i;

  /* In the icons' own view, whose units are points: window coordinates are
   * device pixels, which differ from points at a scale factor other than 1,
   * and the picture would come out that much too big. */
  for (i = 0; i < [icons count]; i++)
    {
      NSRect r = [[icons objectAtIndex: i] frame];

      group = (i == 0) ? r : NSUnionRect(group, r);
    }

  picture = AUTORELEASE ([[NSImage alloc] initWithSize: group.size]);
  [picture setBackgroundColor: [NSColor clearColor]];

  /* Each icon's own picture is transparent around it: caching the view
   * would bring the window background along.  Drawn as it looks at rest,
   * not as the ghost of a moving icon: a window without a compositor can
   * only show or hide a pixel. */
  [picture lockFocus];
  for (i = 0; i < [icons count]; i++)
    {
      FSNIcon *icon = [icons objectAtIndex: i];
      NSRect r = [icon frame];
      CGFloat y = [container isFlipped]
        ? NSMaxY(group) - NSMaxY(r) : r.origin.y - group.origin.y;

      [[icon restingLookImage] drawAtPoint: NSMakePoint(r.origin.x - group.origin.x, y)
                                  fromRect: NSZeroRect
                                 operation: NSCompositeSourceOver
                                  fraction: 1.0];
    }
  /* The window is shaped after the picture's transparency, and the window
   * server can only read that from a bitmap: from the cached picture it
   * got none, the window stayed a rectangle and showed whatever had been
   * on the screen beneath it. */
  bitmap = AUTORELEASE ([[NSBitmapImageRep alloc] initWithFocusedViewRect:
    NSMakeRect(0, 0, group.size.width, group.size.height)]);
  [picture unlockFocus];

  /* Without a compositor a pixel of the window is either shown or not, and
   * a shown pixel that is only partly covered - a name's translucent plate,
   * the soft edge of an icon - has nothing beneath it to blend with: it
   * showed leftovers of the screen.  Every pixel is made one or the other,
   * cut where the window server cuts the shape. */
  {
    NSColor *base = [NSColor whiteColor];
    NSInteger x, y;

    for (y = 0; y < [bitmap pixelsHigh]; y++)
      {
        for (x = 0; x < [bitmap pixelsWide]; x++)
          {
            NSColor *c = [bitmap colorAtX: x y: y];
            CGFloat a = [c alphaComponent];

            if (a * 256 <= FSNShapeAlphaThreshold)
              c = [NSColor colorWithDeviceRed: 0 green: 0 blue: 0 alpha: 0];
            else if (a < 1.0)
              c = [base blendedColorWithFraction: a
                                         ofColor: [c colorWithAlphaComponent: 1.0]];
            else
              continue;

            [bitmap setColor: c atX: x y: y];
          }
      }
  }

  ASSIGN (image, AUTORELEASE ([[NSImage alloc] initWithSize: group.size]));
  [image setBackgroundColor: [NSColor clearColor]];
  [image addRepresentation: bitmap];
}

- (void)showOverlayAtScreenPoint:(NSPoint)p
{
  NSPoint origin = NSMakePoint(p.x - grabOffset.x, p.y - grabOffset.y);

  if (overlay == nil)
    {
      NSImageView *view;
      NSRect frame = NSMakeRect(origin.x, origin.y,
                                [image size].width, [image size].height);

      /* Made the way GNUstep makes its own drag window: drawn straight to
       * the screen and shaped before it first shows.  Shown unshaped even
       * once, it went on showing, around the icons, whatever had been on
       * the screen when it appeared. */
      overlay = [[NSWindow alloc] initWithContentRect: frame
                                            styleMask: NSBorderlessWindowMask
                                              backing: NSBackingStoreNonretained
                                                defer: NO];
      [overlay setReleasedWhenClosed: NO];
      /* The level GNUstep's own drag image uses, above every window. */
      [overlay setLevel: NSPopUpMenuWindowLevel];
      [overlay setBackgroundColor: [NSColor clearColor]];

      view = AUTORELEASE ([[NSImageView alloc] initWithFrame:
        NSMakeRect(0, 0, frame.size.width, frame.size.height)]);
      [view setImageFrameStyle: NSImageFrameNone];
      [view setImage: image];
      [overlay setContentView: view];

      [GSServerForWindow(overlay) restrictWindow: [overlay windowNumber]
                                         toImage: image];
      [overlay orderFront: nil];
    }
  else
    {
      [overlay setFrameOrigin: origin];
      if ([overlay isVisible] == NO)
        [overlay orderFront: nil];
    }
}

- (void)hideOverlay
{
  [overlay orderOut: nil];
}

- (void)setIconsHidden:(BOOL)hidden
{
  NSUInteger i;

  for (i = 0; i < [icons count]; i++)
    {
      NSView *icon = [icons objectAtIndex: i];

      [icon setHidden: hidden];
      [[icon superview] setNeedsDisplayInRect: [icon frame]];
    }
  [[[icons lastObject] superview] displayIfNeeded];
}

/* The same choice GNUstep makes: the deepest view under the point that
 * registered for a type the drag carries. */
- (NSView *)dropViewInWindow:(NSWindow *)window atPoint:(NSPoint)point
{
  NSArray *types = [pboard types];
  NSView *view = [[[window contentView] superview] hitTest: point];

  while (view != nil)
    {
      if ([[view registeredDraggedTypes] firstObjectCommonWithArray: types] != nil
          && [view respondsToSelector: @selector(draggingEntered:)])
        return view;
      view = [view superview];
    }

  return nil;
}

- (void)leaveTarget
{
  if (targetView != nil)
    [targetView draggingExited: self];

  DESTROY (targetView);
  DESTROY (targetWindow);
  targetOperation = NSDragOperationNone;
}

@end
