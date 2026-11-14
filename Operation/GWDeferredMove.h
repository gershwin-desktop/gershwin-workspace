/* GWDeferredMove.h
 *
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

#ifndef GW_DEFERRED_MOVE_H
#define GW_DEFERRED_MOVE_H

#import <Foundation/Foundation.h>
#include <sys/stat.h>

/* A move to a removable device deletes nothing until the copied data is
 * on the device: a stick pulled while the copy was still in memory would
 * otherwise lose both.  Then each source goes only if it is still the file
 * that was copied. */

typedef enum
{
  GWSourceDelete = 0,
  GWSourceKeepChanged,   /* written to after it was copied: warn */
  GWSourceKeepUncopied   /* never copied (appeared later, or failed) */
} GWSourceDecision;

/* Size and modification time of a file, as recorded when it was copied. */
NSDictionary *GWSourceSnapshotOfStat(const struct stat *st);

GWSourceDecision GWDecideSourceDeletion(NSDictionary *recorded,
                                        NSDictionary *current,
                                        BOOL destinationPresent);

@interface GWDeferredMove : NSObject
{
  NSMutableDictionary *_snapshots;
  NSMutableArray *_items;
  NSLock *_lock;
}

/* Called for every regular file as its copy starts. */
- (void)recordSourcePath:(NSString *)path snapshot:(NSDictionary *)snapshot;

/* A top-level item whose copy completed. */
- (void)addItemFrom:(NSString *)source
                 to:(NSString *)destination
               name:(NSString *)name;
- (NSArray *)items;
- (NSArray *)destinationPaths;
- (BOOL)isEmpty;

/* Deletes the sources of all items, files first, then the folders that
 * became empty.  `moved' gets the items whose source is gone entirely,
 * `changed' the paths kept because they changed since their copy.  A
 * failing delete stops the rest, which stays. */
- (BOOL)deleteSourcesReporting:(void (^)(NSString *name))report
                         moved:(NSMutableArray *)moved
                       changed:(NSMutableArray *)changed
                         error:(NSError **)error;

/* The one place a source is removed (a folder only when empty); 0 or the
 * errno.  A subclass can make it fail where no permission can, as for
 * root. */
- (int)removeSourceAtPath:(NSString *)path directory:(BOOL)isDirectory;

@end

#endif
