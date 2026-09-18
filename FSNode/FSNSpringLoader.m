/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-2.0-or-later
 */

#import "FSNSpringLoader.h"
#import "FSNode.h"

static NSString *const FSNSpringEnabledKey = @"SpringLoadedFolders";
static NSString *const FSNSpringDelayKey = @"SpringLoadedFoldersDelay";

static const NSTimeInterval FSNSpringDefaultDelay = 0.5;
static const NSTimeInterval FSNSpringMinimumDelay = 0.1;
static const NSTimeInterval FSNSpringMaximumDelay = 2.0;

/* Two off-on cycles before the folder opens, like a button that is clicked.
 * A step is longer than the 30ms between drag updates, so no half of the
 * flash can fall between two of them. */
static const NSTimeInterval FSNSpringFlashStep = 0.06;
static const int FSNSpringFlashSteps = 4;

/* Crossing a border or a title bar on the way back into a sprung window must
 * not close it, so a window the pointer left closes only after this long. */
static const NSTimeInterval FSNSpringLeaveGrace = 0.3;

/* GNUstep repeats drag updates every 30ms while a drag is over one of our
 * windows.  When they stop, the drag has ended somewhere we are not told
 * about - a refused drop, a drop into another application - or the pointer
 * has gone to another application's window.  Either way the windows opened
 * for the drag close. */
static const NSTimeInterval FSNSpringIdleTimeout = 0.6;
static const NSTimeInterval FSNSpringWatchdogPeriod = 0.1;

/* One thing done for the drag: the delegate's token, the window it happened
 * in, and whether the pointer has been in that window yet.  A window the
 * pointer never reached stays open, the user may still be on the way to it;
 * one it entered and then left closes. */
@interface FSNSpringEntry : NSObject
{
@public
  id token;
  NSWindow *window;
  BOOL entered;
  NSTimeInterval leftAt;
}
@end

@implementation FSNSpringEntry

- (void)dealloc
{
  RELEASE (token);
  RELEASE (window);
  [super dealloc];
}

@end


@interface FSNSpringLoader (Private)
- (BOOL)canSpringNode:(FSNode *)node draggedPaths:(NSArray *)paths;
- (void)disarm;
- (void)fire;
- (NSInteger)indexOfLastEntryForWindow:(NSWindow *)window;
- (void)undoEntriesFromIndex:(NSUInteger)index;
- (void)undoEntriesOutsideWindow:(NSWindow *)kept;
- (void)startWatchdog;
- (void)stopWatchdogIfIdle;
- (void)watchdogFired:(NSTimer *)timer;
@end


@implementation FSNSpringLoader

+ (FSNSpringLoader *)sharedLoader
{
  static FSNSpringLoader *loader = nil;

  if (loader == nil)
    loader = [[FSNSpringLoader alloc] init];

  return loader;
}

- (id)init
{
  self = [super init];

  if (self)
    chain = [NSMutableArray new];

  return self;
}

- (void)dealloc
{
  [watchdog invalidate];
  RELEASE (watchdog);
  RELEASE (chain);
  RELEASE (armedNode);
  RELEASE (armedView);
  RELEASE (flasher);
  [super dealloc];
}

- (void)setDelegate:(id <FSNSpringLoaderDelegate>)aDelegate
{
  delegate = aDelegate;
}

- (BOOL)isEnabled
{
  id value = [[NSUserDefaults standardUserDefaults] objectForKey: FSNSpringEnabledKey];

  return (value == nil) ? YES : [value boolValue];
}

- (NSTimeInterval)delay
{
  id value = [[NSUserDefaults standardUserDefaults] objectForKey: FSNSpringDelayKey];
  NSTimeInterval d = (value == nil) ? FSNSpringDefaultDelay : [value doubleValue];

  if (d < FSNSpringMinimumDelay)
    d = FSNSpringMinimumDelay;
  if (d > FSNSpringMaximumDelay)
    d = FSNSpringMaximumDelay;

  return d;
}

+ (NSArray *)draggedPathsOfDraggingInfo:(id <NSDraggingInfo>)info
{
  NSPasteboard *pb = [info draggingPasteboard];
  id paths;

  if ([[pb types] containsObject: NSFilenamesPboardType] == NO)
    return nil;

  paths = [pb propertyListForType: NSFilenamesPboardType];

  return [paths isKindOfClass: [NSArray class]] ? paths : nil;
}

- (void)pointerRestsOnNode:(FSNode *)node
                    inView:(NSView *)view
                   flasher:(id <FSNSpringFlashing>)aFlasher
              draggedPaths:(NSArray *)paths
{
  NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
  int step;

  lastActivity = now;

  if (paths == nil || [self isEnabled] == NO)
    {
      [self disarm];
      return;
    }

  if (armedView != view || [[armedNode path] isEqual: [node path]] == NO)
    {
      [self disarm];

      ASSIGN (armedNode, node);
      ASSIGN (armedView, view);
      ASSIGN (flasher, aFlasher);
      armedAt = now;
      flashStartedAt = 0;

      /* Decided once per folder rather than on every update: the answer
       * needs the file system, and updates come every 30ms. */
      firedForArmedNode = ([self canSpringNode: node draggedPaths: paths] == NO);

      if (firedForArmedNode == NO)
        [self startWatchdog];
      return;
    }

  if (firedForArmedNode)
    return;

  if (flashStartedAt == 0)
    {
      if ((now - armedAt) < [self delay])
        return;
      flashStartedAt = now;
    }

  step = (int)((now - flashStartedAt) / FSNSpringFlashStep);

  if (step < FSNSpringFlashSteps)
    {
      [flasher setSpringHighlightVisible: (step % 2) == 1];
      return;
    }

  [flasher setSpringHighlightVisible: YES];
  firedForArmedNode = YES;
  [self fire];
}

- (void)pointerLeftView:(NSView *)view
{
  if (view == armedView)
    [self disarm];
}

- (void)noteEvent:(NSEvent *)event inWindow:(NSWindow *)window
{
  if ([event type] != NSAppKitDefined)
    return;

  switch ([event subtype])
    {
      case GSAppKitDraggingEnter:
      case GSAppKitDraggingUpdate:
        [self dragIsOverWindow: window];
        break;

      case GSAppKitDraggingDrop:
        [self dragDroppedInWindow: window];
        break;

      default:
        break;
    }
}

- (void)dragIsOverWindow:(NSWindow *)window
{
  NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
  NSInteger here;
  NSUInteger i;

  lastActivity = now;

  if ([chain count] == 0)
    return;

  /* The pointer is in the window of entry `here`, so it is also inside every
   * window opened before it on the way there; only the ones beyond can have
   * been left. */
  here = [self indexOfLastEntryForWindow: window];

  for (i = 0; i < [chain count]; i++)
    {
      FSNSpringEntry *entry = [chain objectAtIndex: i];

      if (here != NSNotFound && (NSInteger)i <= here)
        {
          if (entry->window == window)
            entry->entered = YES;
          entry->leftAt = 0;
        }
      else if (entry->entered && entry->leftAt == 0)
        {
          entry->leftAt = now;
        }
    }

  for (i = 0; i < [chain count]; i++)
    {
      FSNSpringEntry *entry = [chain objectAtIndex: i];

      if (entry->entered && entry->leftAt != 0
          && (now - entry->leftAt) >= FSNSpringLeaveGrace)
        {
          [self undoEntriesFromIndex: i];
          break;
        }
    }
}

- (void)dragDroppedInWindow:(NSWindow *)window
{
  /* The window the drop landed in stays open: it is where the user put the
   * item.  Everything else opened for the drag closes. */
  [self undoEntriesOutsideWindow: window];
  [chain removeAllObjects];
  [self disarm];
  [self stopWatchdogIfIdle];
}

- (void)dragEnded
{
  if ([chain count] > 0)
    [self undoEntriesFromIndex: 0];
  [self disarm];
  [self stopWatchdogIfIdle];
}

@end


@implementation FSNSpringLoader (Private)

/* A node opens for a drag when it is a folder one can look into, and is
 * neither one of the dragged items nor inside one: nothing could be dropped
 * there. */
- (BOOL)canSpringNode:(FSNode *)node draggedPaths:(NSArray *)paths
{
  NSFileManager *fm = [NSFileManager defaultManager];
  NSString *path;
  FSNode *target;
  NSUInteger i;

  if (node == nil || [node isValid] == NO)
    return NO;

  path = [[node path] stringByResolvingSymlinksInPath];
  target = [node isLink] ? [FSNode nodeWithPath: path] : node;

  if (target == nil || [target isValid] == NO)
    return NO;
  if ([target isDirectory] == NO || [target isPackage])
    return NO;
  if ([fm isReadableFileAtPath: path] == NO
      || [fm isExecutableFileAtPath: path] == NO)
    return NO;

  for (i = 0; i < [paths count]; i++)
    {
      NSString *dragged = [[paths objectAtIndex: i] stringByResolvingSymlinksInPath];

      if ([path isEqual: dragged]
          || [path hasPrefix: [dragged stringByAppendingString: @"/"]])
        return NO;
    }

  return (delegate == nil) || [delegate springLoader: self mayOpenNode: target];
}

- (void)disarm
{
  /* Stopped half way through the flash: leave the folder lit, as it was. */
  if (flasher != nil && flashStartedAt != 0 && firedForArmedNode == NO)
    [flasher setSpringHighlightVisible: YES];

  DESTROY (armedNode);
  DESTROY (armedView);
  DESTROY (flasher);
  flashStartedAt = 0;
  firedForArmedNode = NO;
}

- (void)fire
{
  NSWindow *fromWindow = [armedView window];
  NSInteger from = [self indexOfLastEntryForWindow: fromWindow];
  FSNode *target = armedNode;
  id token;

  /* Opening the folder can replace the view that reported it - a browsing
   * window moving in place builds new icons - so nothing may talk to the
   * old view or its flasher afterwards. */
  DESTROY (flasher);

  /* Springing from a window drops whatever was sprung beyond it before: the
   * drag has left that branch.  From a window outside the chain, the whole
   * chain goes. */
  [self undoEntriesFromIndex: (from == NSNotFound) ? 0 : (NSUInteger)(from + 1)];

  if ([armedNode isLink])
    target = [FSNode nodeWithPath: [[armedNode path] stringByResolvingSymlinksInPath]];

  token = [delegate springLoader: self openNode: target fromView: armedView];

  /* Opening a large folder can take longer than the drag may go quiet. */
  lastActivity = [NSDate timeIntervalSinceReferenceDate];

  if (token != nil)
    {
      FSNSpringEntry *entry = [FSNSpringEntry new];

      ASSIGN (entry->token, token);
      ASSIGN (entry->window, [delegate springLoader: self windowForToken: token]);
      /* A browsing window that moved in place is the window the pointer is
       * in already. */
      entry->entered = (entry->window == fromWindow);
      entry->leftAt = 0;
      [chain addObject: entry];
      RELEASE (entry);
    }
}

- (NSInteger)indexOfLastEntryForWindow:(NSWindow *)window
{
  NSInteger i;

  for (i = (NSInteger)[chain count] - 1; i >= 0; i--)
    {
      FSNSpringEntry *entry = [chain objectAtIndex: i];

      if (entry->window == window)
        return i;
    }

  return NSNotFound;
}

/* Later entries were opened from earlier ones, so they are undone first. */
- (void)undoEntriesFromIndex:(NSUInteger)index
{
  while ([chain count] > index)
    {
      FSNSpringEntry *entry = RETAIN ([chain lastObject]);

      [chain removeLastObject];
      [delegate springLoader: self undo: entry->token];
      RELEASE (entry);
    }
}

/* Every entry in the kept window is part of the state the user dropped
 * into - a browsing window may have moved several levels down - so none of
 * them is undone. */
- (void)undoEntriesOutsideWindow:(NSWindow *)kept
{
  NSInteger i;

  for (i = (NSInteger)[chain count] - 1; i >= 0; i--)
    {
      FSNSpringEntry *entry = [chain objectAtIndex: i];

      if (entry->window != kept)
        [delegate springLoader: self undo: entry->token];
    }
}

- (void)startWatchdog
{
  if (watchdog != nil)
    return;

  ASSIGN (watchdog, [NSTimer timerWithTimeInterval: FSNSpringWatchdogPeriod
                                            target: self
                                          selector: @selector(watchdogFired:)
                                          userInfo: nil
                                           repeats: YES]);

  /* The drag loops, GNUstep's and the free-position move's, run the event
   * tracking mode. */
  [[NSRunLoop currentRunLoop] addTimer: watchdog forMode: NSDefaultRunLoopMode];
  [[NSRunLoop currentRunLoop] addTimer: watchdog forMode: NSEventTrackingRunLoopMode];
}

- (void)stopWatchdogIfIdle
{
  if ([chain count] > 0 || armedNode != nil)
    return;

  [watchdog invalidate];
  DESTROY (watchdog);
}

- (void)watchdogFired:(NSTimer *)timer
{
  NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];

  if ((now - lastActivity) >= FSNSpringIdleTimeout)
    [self dragEnded];
  else
    [self stopWatchdogIfIdle];
}

@end
