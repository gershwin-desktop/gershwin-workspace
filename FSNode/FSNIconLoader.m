/* FSNIconLoader.m - Time-budgeted deferred decoration for lazy-loaded views.
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

#import "FSNIconLoader.h"
#import "FSNode.h"

#import <AppKit/AppKit.h>
#import <GNUstepBase/GNUstep.h>

/* Timer cadence and per-fire budget.  At 50 ms cadence with a 20 ms budget
 * the loader costs at most ~40% of one core while draining a large backlog
 * and disappears completely once the queue is empty.  Up to 128 items per
 * fire keep a full directory (or desktop) draining within a second or two. */
#define FSN_LOADER_INTERVAL (0.05)
#define FSN_LOADER_BUDGET (0.02)
#define FSN_LOADER_MAX_ITEMS (128)

@interface FSNIconLoaderItem : NSObject
{
@private
  id _client;             /* retained; clients cancel in -dealloc */
  FSNode *_node;
  NSInteger _generation;
  NSString *_key;
}

- (instancetype)initWithClient:(id <FSNDecorationClient>)client
                          node:(FSNode *)node
                    generation:(NSInteger)generation
                           key:(NSString *)key;

- (id)client;
- (FSNode *)node;
- (NSInteger)generation;
- (NSString *)key;

@end

@implementation FSNIconLoaderItem

- (instancetype)initWithClient:(id <FSNDecorationClient>)client
                          node:(FSNode *)node
                    generation:(NSInteger)generation
                           key:(NSString *)key
{
  self = [super init];

  if (self)
    {
      _client = [client retain];
      _node = [node retain];
      _generation = generation;
      _key = [key copy];
    }

  return self;
}

- (void)dealloc
{
  RELEASE (_client);
  RELEASE (_node);
  RELEASE (_key);
  [super dealloc];
}

- (id)client
{
  return _client;
}

- (FSNode *)node
{
  return _node;
}

- (NSInteger)generation
{
  return _generation;
}

- (NSString *)key
{
  return _key;
}

@end

@implementation FSNIconLoader

static FSNIconLoader *_sharedLoader = nil;

+ (FSNIconLoader *)sharedLoader
{
  if (_sharedLoader == nil)
    {
      _sharedLoader = [[FSNIconLoader alloc] init];
    }
  return _sharedLoader;
}

- (instancetype)init
{
  self = [super init];

  if (self)
    {
      _urgentQueue = [NSMutableArray new];
      _bulkQueue = [NSMutableArray new];
      _pendingKeys = [NSMutableSet new];
      _timer = nil;
    }

  return self;
}

- (void)dealloc
{
  [_timer invalidate];
  RELEASE (_timer);
  RELEASE (_urgentQueue);
  RELEASE (_bulkQueue);
  RELEASE (_pendingKeys);
  [super dealloc];
}

/* Main-thread only: the decoration callbacks touch AppKit views. */
- (void)enqueueNode:(FSNode *)node
             client:(id <FSNDecorationClient>)client
             urgent:(BOOL)urgent
{
  if (node == nil || client == nil)
    {
      return;
    }

  NSString *key = [NSString stringWithFormat: @"%p|%@", client, [node path]];

  if ([_pendingKeys containsObject: key])
    {
      /* Already queued: honor an urgent re-request by promoting the item.
       * Its stored generation is kept - if the client reloaded since, the
       * stale check drops it at fire time. */
      if (urgent)
        {
          FSNIconLoaderItem *promoted = nil;

          for (FSNIconLoaderItem *item in _bulkQueue)
            {
              if ([[item key] isEqual: key])
                {
                  promoted = item;
                  break;
                }
            }

          if (promoted != nil)
            {
              /* The bulk queue holds the only reference: keep the item
               * alive across the move. */
              [promoted retain];
              [_bulkQueue removeObject: promoted];
              [_urgentQueue addObject: promoted];
              [promoted release];
              [self _startTimerIfNeeded];
            }
        }
      return;
    }

  NSInteger generation = 0;

  if ([client respondsToSelector: @selector(fsnDecorationGeneration)])
    {
      generation = [client fsnDecorationGeneration];
    }

  FSNIconLoaderItem *item = [[FSNIconLoaderItem alloc]
                               initWithClient: client
                                         node: node
                                   generation: generation
                                          key: key];

  [_pendingKeys addObject: key];

  if (urgent)
    {
      [_urgentQueue addObject: item];
    }
  else
    {
      [_bulkQueue addObject: item];
    }

  RELEASE (item);
  [self _startTimerIfNeeded];
}

- (void)cancelClient:(id <FSNDecorationClient>)client
{
  if (client == nil)
    {
      return;
    }

  for (FSNIconLoaderItem *item in [_urgentQueue copy])
    {
      if ([item client] == client)
        {
          [_pendingKeys removeObject: [item key]];
          [_urgentQueue removeObject: item];
        }
    }

  for (FSNIconLoaderItem *item in [_bulkQueue copy])
    {
      if ([item client] == client)
        {
          [_pendingKeys removeObject: [item key]];
          [_bulkQueue removeObject: item];
        }
    }

  [self _stopTimerIfIdle];
}

- (NSUInteger)pendingCount
{
  return [_urgentQueue count] + [_bulkQueue count];
}

- (void)processNow
{
  [self _processQueue];
}

- (void)_startTimerIfNeeded
{
  if (_timer != nil)
    {
      return;
    }

  _timer = [[NSTimer timerWithTimeInterval: FSN_LOADER_INTERVAL
                                    target: self
                                  selector: @selector(_timerFired:)
                                  userInfo: nil
                                   repeats: YES] retain];

  /* Event tracking (scrolling, dragging) runs its own run loop mode;
   * without adding the timer there, decoration would pause mid-scroll. */
  [[NSRunLoop currentRunLoop] addTimer: _timer
                               forMode: NSDefaultRunLoopMode];
  [[NSRunLoop currentRunLoop] addTimer: _timer
                               forMode: NSEventTrackingRunLoopMode];
}

- (void)_stopTimerIfIdle
{
  if (_timer != nil && [_urgentQueue count] == 0 && [_bulkQueue count] == 0)
    {
      [_timer invalidate];
      RELEASE (_timer);
      _timer = nil;
    }
}

- (void)_timerFired:(NSTimer *)timer
{
  [self _processQueue];
}

/* Process items until the per-fire time budget or item cap is reached.
 * Urgent items always go first.  Stale items (cancelled or generation
 * bumped) are dropped without invoking the client. */
- (void)_processQueue
{
  if ([_urgentQueue count] == 0 && [_bulkQueue count] == 0)
    {
      [self _stopTimerIfIdle];
      return;
    }

  NSTimeInterval start = [NSDate timeIntervalSinceReferenceDate];
  NSUInteger processed = 0;

  while ([_urgentQueue count] > 0 || [_bulkQueue count] > 0)
    {
      NSMutableArray *queue = ([_urgentQueue count] > 0) ? _urgentQueue
                                                         : _bulkQueue;
      FSNIconLoaderItem *item = [queue objectAtIndex: 0];

      /* The queue holds the only reference: pull the item's fields before
       * removing it, or the item dies underneath us. */
      NSString *key = [[item key] retain];
      id <FSNDecorationClient> client = [[item client] retain];
      FSNode *node = [[item node] retain];
      NSInteger generation = [item generation];

      [queue removeObject: item];
      [_pendingKeys removeObject: key];

      BOOL stale = ([client respondsToSelector: @selector(fsnDecorationGeneration)]
                      && [client fsnDecorationGeneration] != generation);

      if (stale == NO)
        {
          [client fsnLoaderDecorateNode: node];
        }

      [key release];
      [client release];
      [node release];

      processed++;

      if (([NSDate timeIntervalSinceReferenceDate] - start) >= FSN_LOADER_BUDGET
          || processed >= FSN_LOADER_MAX_ITEMS)
        {
          break;
        }
    }

  [self _stopTimerIfIdle];
}

@end
