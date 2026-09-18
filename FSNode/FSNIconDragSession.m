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
{
  self = [super init];

  if (self)
    {
      NSMutableArray *p = [NSMutableArray arrayWithCapacity: [draggedIcons count]];
      NSUInteger i;

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
 * there, and where on that picture the pointer holds them. */
- (void)buildImage
{
  NSRect group = NSZeroRect;
  NSPoint pointer;
  NSUInteger i;

  for (i = 0; i < [icons count]; i++)
    {
      NSView *icon = [icons objectAtIndex: i];
      NSRect r = [icon convertRect: [icon bounds] toView: nil];

      group = (i == 0) ? r : NSUnionRect(group, r);
    }

  ASSIGN (image, AUTORELEASE ([[NSImage alloc] initWithSize: group.size]));
  /* A clear background is what lets the window be shaped like the icons. */
  [image setBackgroundColor: [NSColor clearColor]];

  /* Each icon's own picture is transparent around it: caching the view
   * would bring the window background along, and the shaped window would
   * then be a rectangle.  Drawn as it looks at rest, not as the ghost of a
   * moving icon: a window without a compositor can only show or hide a
   * pixel. */
  [image lockFocus];
  for (i = 0; i < [icons count]; i++)
    {
      FSNIcon *icon = [icons objectAtIndex: i];
      NSRect r = [icon convertRect: [icon bounds] toView: nil];

      [[icon restingLookImage] drawAtPoint: NSMakePoint(r.origin.x - group.origin.x,
                                                         r.origin.y - group.origin.y)
                                  fromRect: NSZeroRect
                                 operation: NSCompositeSourceOver
                                  fraction: 1.0];
    }
  [image unlockFocus];

  pointer = [sourceWindow mouseLocationOutsideOfEventStream];
  grabOffset = NSMakePoint(pointer.x - group.origin.x, pointer.y - group.origin.y);
}

- (void)showOverlayAtScreenPoint:(NSPoint)p
{
  NSPoint origin = NSMakePoint(p.x - grabOffset.x, p.y - grabOffset.y);

  if (overlay == nil)
    {
      NSImageView *view;
      NSRect frame = NSMakeRect(origin.x, origin.y,
                                [image size].width, [image size].height);

      overlay = [[NSWindow alloc] initWithContentRect: frame
                                            styleMask: NSBorderlessWindowMask
                                              backing: NSBackingStoreBuffered
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

      [overlay orderFront: nil];
      [GSServerForWindow(overlay) restrictWindow: [overlay windowNumber]
                                         toImage: image];
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
