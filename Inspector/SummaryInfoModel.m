/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

#import "SummaryInfoModel.h"
#import "FinderInfoModel.h"
#import "FSNode.h"

@implementation SummaryInfoModel

@synthesize itemCount = _itemCount;
@synthesize folderCount = _folderCount;
@synthesize totalBytes = _totalBytes;
@synthesize finished = _finished;
@synthesize kinds = _kinds;
@synthesize commonLabel = _commonLabel;
@synthesize lockedState = _lockedState;
@synthesize supportsLocking = _supportsLocking;

- (id)initWithPaths:(NSArray *)paths
{
  self = [super init];
  if (self)
    {
      _paths = [paths copy];
      _kinds = [NSMutableDictionary new];
      _commonLabel = 0;
      _lockedState = SummaryStateNone;
    }
  return self;
}

- (void)dealloc
{
  [_paths release];
  [_kinds release];
  [_target release];
  [super dealloc];
}

/* The list view's Kind column asks the node, so the same words appear here. */
- (NSString *)kindOfPath:(NSString *)path
{
  return [[FSNode nodeWithPath: path] typeDescription];
}

/* Sizes of regular files only, links are not followed: a link into another
 * volume must not count the volume. */
- (unsigned long long)bytesBelow:(NSString *)path
{
  NSFileManager *fm = [NSFileManager defaultManager];
  NSDirectoryEnumerator *e = [fm enumeratorAtPath: path];
  unsigned long long sum = 0;
  NSString *sub;

  while ((sub = [e nextObject]) != nil)
    {
      NSDictionary *a = [e fileAttributes];

      if (_cancelled)
        {
          break;
        }
      if ([[a fileType] isEqual: NSFileTypeRegular])
        {
          sum += [a fileSize];
        }
    }
  return sum;
}

- (void)compute
{
  NSFileManager *fm = [NSFileManager defaultManager];
  NSUInteger i, lockedCount = 0, count = [_paths count];
  NSInteger label = 0;
  BOOL first = YES;

  _supportsLocking = [FinderInfoModel supportsLocking];
  for (i = 0; i < count && !_cancelled; i++)
    {
      NSAutoreleasePool *pool = [NSAutoreleasePool new];
      NSString *path = [_paths objectAtIndex: i];
      NSDictionary *a = [fm fileAttributesAtPath: path traverseLink: NO];
      NSString *type = [a fileType];
      BOOL isDir = [type isEqual: NSFileTypeDirectory];
      NSString *kind = [self kindOfPath: path];
      FinderInfoModel *info = [FinderInfoModel modelForPath: path];
      NSNumber *n;

      _itemCount++;
      if (isDir)
        {
          _folderCount++;
          _totalBytes += [self bytesBelow: path];
        }
      else if ([type isEqual: NSFileTypeRegular])
        {
          _totalBytes += [a fileSize];
        }
      n = [_kinds objectForKey: kind];
      [_kinds setObject: [NSNumber numberWithUnsignedInteger: [n unsignedIntegerValue] + 1]
                 forKey: kind];

      if (info != nil)
        {
          if (first)
            {
              label = [info labelNumber];
            }
          else if (label != [info labelNumber])
            {
              label = -1;
            }
          if ([info locked])
            {
              lockedCount++;
            }
        }
      first = NO;
      [pool release];
    }
  _commonLabel = label;
  if (lockedCount == 0)
    {
      _lockedState = SummaryStateNone;
    }
  else if (lockedCount == count)
    {
      _lockedState = SummaryStateAll;
    }
  else
    {
      _lockedState = SummaryStateMixed;
    }
  _finished = !_cancelled;
}

- (void)runInBackground:(id)unused
{
  NSAutoreleasePool *pool = [NSAutoreleasePool new];

  [self compute];
  if (!_cancelled && _target != nil)
    {
      [_target performSelectorOnMainThread: _doneSelector
                                withObject: self
                             waitUntilDone: NO];
    }
  /* The window owns the model; keeping the window alive from here on would
   * make a retain cycle that nothing breaks. */
  [_target release];
  _target = nil;
  [pool release];
}

- (void)startInBackgroundNotifying:(id)target selector:(SEL)doneSelector
{
  [target retain];
  [_target release];
  _target = target;
  _doneSelector = doneSelector;
  [NSThread detachNewThreadSelector: @selector(runInBackground:)
                           toTarget: self
                         withObject: nil];
}

- (NSUInteger)applyLabel:(NSInteger)label
{
  NSUInteger i, failures = 0;

  for (i = 0; i < [_paths count]; i++)
    {
      FinderInfoModel *info = [FinderInfoModel modelForPath: [_paths objectAtIndex: i]];

      [info setLabelNumber: label];
      if (info == nil || ![info write: NULL])
        {
          failures++;
        }
    }
  if (failures < [_paths count])
    {
      _commonLabel = failures == 0 ? label : -1;
    }
  return failures;
}

- (void)cancel
{
  _cancelled = YES;
}

+ (NSString *)descriptionForByteCount:(unsigned long long)bytes
{
  static const char *units[] = { "KB", "MB", "GB", "TB" };
  NSNumberFormatter *nf = [[NSNumberFormatter new] autorelease];
  NSString *exact;
  double v = (double)bytes;
  int u = -1;

  [nf setNumberStyle: NSNumberFormatterDecimalStyle];
  exact = [nf stringFromNumber: [NSNumber numberWithUnsignedLongLong: bytes]];
  if (bytes < 1000)
    {
      return [NSString stringWithFormat: NSLocalizedString(@"%@ bytes", @"Size"),
                exact];
    }
  while (v >= 1000.0 && u < 3)
    {
      v /= 1000.0;
      u++;
    }
  return [NSString stringWithFormat:
            NSLocalizedString(@"%.1f %s (%@ bytes)", @"Size, human readable and exact"),
            v, units[u], exact];
}

@end
