/* FSNDirEntry.m - A single entry of a directory listing snapshot.
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

#import "FSNDirEntry.h"

@implementation FSNDirEntry

- (instancetype)initWithName:(NSString *)name kind:(FSNDirEntryKind)kind
{
  self = [super init];

  if (self)
    {
      _name = [name copy];
      _kind = kind;
    }

  return self;
}

- (NSString *)name
{
  return _name;
}

- (FSNDirEntryKind)kind
{
  return _kind;
}

- (BOOL)hasUnknownKind
{
  return _kind == FSNDirEntryKindUnknown;
}

- (NSComparisonResult)compare:(FSNDirEntry *)other
{
  return [_name compare: [other name]];
}

@end
