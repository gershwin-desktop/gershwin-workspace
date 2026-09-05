/* FSNIconLoader.h - Time-budgeted deferred decoration for lazy-loaded views.
 *
 * When a large directory is displayed, the views first lay out cheap
 * placeholder rows (name + kind from the readdir snapshot) and then
 * decorate them - attributes, type flags, icons, tag colors, info lines -
 * progressively.  The loader owns the queue: visible rows are enqueued as
 * urgent, the rest as bulk; items are processed on the main thread in
 * NSTimer fires under a per-fire time budget so the UI stays responsive.
 * This is the "load what is displayed plus the next few" scheme, with the
 * remainder trickled in the background.
 *
 * The loader does no AppKit work itself: the client performs the actual
 * decoration in its -fsnLoaderDecorateNode: callback and decides whether
 * it still shows the node (stale items simply return NO).
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

#ifndef _FSNICONLOADER_H_
#define _FSNICONLOADER_H_

#import <Foundation/Foundation.h>

@class FSNode;

@protocol FSNDecorationClient <NSObject>

/* Do the deferred decoration work for the node (load its attributes, type
 * flags, icon, tag color, info line - whatever the client displays) and
 * redraw the affected cells/views.  Called on the main thread inside the
 * loader's time budget.  Return YES when work was done, NO when the client
 * no longer shows the node (stale item). */
- (BOOL)fsnLoaderDecorateNode:(FSNode *)node;

@optional

/* Current generation of the client's contents.  Items enqueued with an
 * older generation are dropped instead of decorated; clients bump their
 * generation whenever they reload their contents. */
- (NSInteger)fsnDecorationGeneration;

@end

@interface FSNIconLoader : NSObject
{
@private
  NSMutableArray	*_urgentQueue;	/* FSNIconLoaderItem, FIFO */
  NSMutableArray	*_bulkQueue;	/* FSNIconLoaderItem, FIFO */
  NSMutableSet		*_pendingKeys;	/* "client|path" dedup */
  NSTimer		*_timer;
}

+ (FSNIconLoader *)sharedLoader;

/* Queue a decoration pass for the node.  Urgent items are processed before
 * all bulk items.  A (client, node) pair already queued is not queued
 * again.  The client is retained until the item is processed or cancelled;
 * clients must -cancelClient: themselves in -dealloc. */
- (void)enqueueNode:(FSNode *)node
             client:(id <FSNDecorationClient>)client
             urgent:(BOOL)urgent;

/* Drop every pending item of the client (call from -dealloc and whenever
 * the client's whole contents are replaced without a generation change). */
- (void)cancelClient:(id <FSNDecorationClient>)client;

/* Number of queued items (urgent + bulk). */
- (NSUInteger)pendingCount;

/* Process queued items immediately, under the normal per-fire time budget.
 * The timer keeps running; used by tests and by clients that want to flush
 * urgent work without waiting for the next tick. */
- (void)processNow;

@end

#endif /* _FSNICONLOADER_H_ */
