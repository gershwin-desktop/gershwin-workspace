/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

#import <Foundation/Foundation.h>

/* Common state of a property over all items of a selection. */
typedef enum {
  SummaryStateNone = 0,   /* no item has it */
  SummaryStateAll,        /* every item has it */
  SummaryStateMixed       /* some have it */
} SummaryState;

/* Implemented by Workspace: the one place that labels files. */
@protocol SummaryInfoLabelWriter
- (NSUInteger)setLabelNumber:(NSInteger)label forPaths:(NSArray *)paths nodeView:(id)nodeView;
@end

/* Totals over a multiple selection, for the Summary Info window.  Free of
 * AppKit so the counting rules can be tested headless. */
@interface SummaryInfoModel : NSObject
{
  NSArray *_paths;
  NSUInteger _itemCount;
  NSUInteger _folderCount;
  unsigned long long _totalBytes;
  NSMutableDictionary *_kinds;
  NSInteger _commonLabel;      /* label number, or -1 when the items differ */
  SummaryState _lockedState;
  BOOL _supportsLocking;
  BOOL _finished;
  volatile BOOL _cancelled;
  id _target;
  SEL _doneSelector;
}

- (id)initWithPaths:(NSArray *)paths;

/* Walks the items on the calling thread; stops early after -cancel. */
- (void)compute;

/* Computes on a background thread, then sends doneSelector to target on the
 * main thread.  A deep folder tree can take long; the window must not wait. */
- (void)startInBackgroundNotifying:(id)target selector:(SEL)doneSelector;
- (void)cancel;

/* Gives every item the label (0 = None, 1-7 as in the Label menu) and returns
 * how many items could not be written.  The writer is the one object that
 * labels files for all of Workspace, -setLabelNumber:forPaths:nodeView:, so
 * open viewers refresh too; this class has no way of writing labels itself.
 * There is no undo: Workspace has no undo stack for metadata changes. */
- (NSUInteger)applyLabel:(NSInteger)label writer:(id<SummaryInfoLabelWriter>)writer;

@property (nonatomic, readonly) NSUInteger itemCount;
@property (nonatomic, readonly) NSUInteger folderCount;
@property (nonatomic, readonly) unsigned long long totalBytes;
@property (nonatomic, readonly) BOOL finished;
/* Kind description to number of items, e.g. "Folder" = 2. */
@property (nonatomic, readonly) NSDictionary *kinds;
@property (nonatomic, readonly) NSInteger commonLabel;
@property (nonatomic, readonly) SummaryState lockedState;
@property (nonatomic, readonly) BOOL supportsLocking;

/* "1.5 MB (1,500,000 bytes)" */
+ (NSString *)descriptionForByteCount:(unsigned long long)bytes;

@end
