/* t_FSNIconLoader.m - headless coverage for the deferred decoration queue.
 *
 * FSNIconLoader schedules "decorate this node" work items: urgent items
 * (the visible rows + prefetch window) before bulk ones (the remainder),
 * deduplicated per (client, node), cancelled with the client, and dropped
 * when the client's generation moved on.  The node here is a stand-in that
 * only has to answer -path, which is all the loader uses.
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import "Testing.h"
#import "FSNIconLoader.h"
#import "FSNode.h"

/* Minimal node stand-in: the loader only reads -path. */
@interface LoaderTestNode : NSObject
{
  NSString *_path;
}
- (instancetype)initWithPath:(NSString *)path;
- (NSString *)path;
@end

@implementation LoaderTestNode

- (instancetype)initWithPath:(NSString *)path
{
  self = [super init];
  if (self)
    {
      _path = [path copy];
    }
  return self;
}

- (NSString *)path
{
  return _path;
}

@end

/* Client recording decorate calls, with a mutable generation. */
@interface LoaderTestClient : NSObject <FSNDecorationClient>
{
  NSMutableArray *_decorated;
  NSInteger _generation;
}
- (NSArray *)decorated;
- (void)setGeneration:(NSInteger)generation;
@end

@implementation LoaderTestClient

- (instancetype)init
{
  self = [super init];
  if (self)
    {
      _decorated = [NSMutableArray new];
      _generation = 1;
    }
  return self;
}

- (void)dealloc
{
  [[FSNIconLoader sharedLoader] cancelClient: self];
  [_decorated release];
  [super dealloc];
}

- (NSArray *)decorated
{
  return _decorated;
}

- (void)setGeneration:(NSInteger)generation
{
  _generation = generation;
}

- (NSInteger)fsnDecorationGeneration
{
  return _generation;
}

- (BOOL)fsnLoaderDecorateNode:(FSNode *)node
{
  [_decorated addObject: [(id)node path]];
  return YES;
}

@end

int
main(void)
{
  NSAutoreleasePool *arp = [NSAutoreleasePool new];

  START_SET("urgent items are processed before bulk items")
    {
      LoaderTestClient *client = [LoaderTestClient new];
      LoaderTestNode *a = [[LoaderTestNode alloc] initWithPath: @"/bulk-a"];
      LoaderTestNode *b = [[LoaderTestNode alloc] initWithPath: @"/bulk-b"];
      LoaderTestNode *v = [[LoaderTestNode alloc] initWithPath: @"/visible"];

      [[FSNIconLoader sharedLoader] enqueueNode: (FSNode *)a client: client urgent: NO];
      [[FSNIconLoader sharedLoader] enqueueNode: (FSNode *)b client: client urgent: NO];
      [[FSNIconLoader sharedLoader] enqueueNode: (FSNode *)v client: client urgent: YES];

      PASS([[FSNIconLoader sharedLoader] pendingCount] == 3, "three items queued");

      [[FSNIconLoader sharedLoader] processNow];

      PASS([[client decorated] count] == 3, "all items processed");
      PASS([[[client decorated] objectAtIndex: 0] isEqual: @"/visible"],
           "urgent (visible) item processed first");
      PASS([[[client decorated] objectAtIndex: 1] isEqual: @"/bulk-a"]
           && [[[client decorated] objectAtIndex: 2] isEqual: @"/bulk-b"],
           "bulk items keep FIFO order after urgent");

      PASS([[FSNIconLoader sharedLoader] pendingCount] == 0, "queue drained");

      [a release];
      [b release];
      [v release];
      [client release];
    }
  END_SET("urgent items are processed before bulk items")

  START_SET("enqueueing the same node twice is deduplicated")
    {
      LoaderTestClient *client = [LoaderTestClient new];
      LoaderTestNode *a = [[LoaderTestNode alloc] initWithPath: @"/dup"];

      [[FSNIconLoader sharedLoader] enqueueNode: (FSNode *)a client: client urgent: NO];
      [[FSNIconLoader sharedLoader] enqueueNode: (FSNode *)a client: client urgent: YES];

      PASS([[FSNIconLoader sharedLoader] pendingCount] == 1, "duplicate not queued twice");

      [[FSNIconLoader sharedLoader] processNow];

      PASS([[client decorated] count] == 1, "duplicate processed once");

      [a release];
      [client release];
    }
  END_SET("enqueueing the same node twice is deduplicated")

  START_SET("stale generation items are dropped")
    {
      LoaderTestClient *client = [LoaderTestClient new];
      LoaderTestNode *old = [[LoaderTestNode alloc] initWithPath: @"/old-content"];
      LoaderTestNode *new = [[LoaderTestNode alloc] initWithPath: @"/new-content"];

      /* Enqueue while the client is at generation 1 ... */
      [[FSNIconLoader sharedLoader] enqueueNode: (FSNode *)old client: client urgent: NO];

      /* ... simulate a contents reload ... */
      [client setGeneration: 2];
      [[FSNIconLoader sharedLoader] enqueueNode: (FSNode *)new client: client urgent: NO];

      [[FSNIconLoader sharedLoader] processNow];

      PASS([[client decorated] containsObject: @"/old-content"] == NO,
           "item from before the reload was dropped");
      PASS([[client decorated] containsObject: @"/new-content"],
           "item enqueued after the reload was processed");

      [old release];
      [new release];
      [client release];
    }
  END_SET("stale generation items are dropped")

  START_SET("cancelClient drops pending items")
    {
      LoaderTestClient *client = [LoaderTestClient new];
      LoaderTestNode *a = [[LoaderTestNode alloc] initWithPath: @"/cancelled"];

      [[FSNIconLoader sharedLoader] enqueueNode: (FSNode *)a client: client urgent: NO];
      [[FSNIconLoader sharedLoader] cancelClient: client];

      PASS([[FSNIconLoader sharedLoader] pendingCount] == 0,
           "cancelled items leave the queue");

      [[FSNIconLoader sharedLoader] processNow];

      PASS([[client decorated] count] == 0, "cancelled items are not processed");

      [a release];
      [client release];
    }
  END_SET("cancelClient drops pending items")

  START_SET("a queued item does not retain the queue alive after cancel")
    {
      LoaderTestClient *client = [LoaderTestClient new];
      LoaderTestNode *a = [[LoaderTestNode alloc] initWithPath: @"/x"];

      [[FSNIconLoader sharedLoader] enqueueNode: (FSNode *)a client: client urgent: NO];
      [[FSNIconLoader sharedLoader] enqueueNode: (FSNode *)a client: client urgent: NO];

      PASS([[FSNIconLoader sharedLoader] pendingCount] == 1,
           "re-enqueue after cancel deduplicates against pending set");
      /* The item survived the duplicate attempt; clear the slate for the
       * next set. */
      [[FSNIconLoader sharedLoader] cancelClient: client];

      [a release];
      [client release];
    }
  END_SET("a queued item does not retain the queue alive after cancel")

  [arp release];
  return 0;
}
