/* FSNIconPlacement.m
 *
 * Implementation of FSNIconItemData placement data model.
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

#import "FSNIconPlacement.h"

@implementation FSNIconItemData

- (instancetype)init
{
  self = [super init];
  if (self)
    {
      _itemID = [[[NSProcessInfo processInfo] globallyUniqueString] copy];
      _filename = nil;
      _placementMode = FSNIconPlacementModeAuto;
      _pixelPosition = NSZeroPoint;
      _ilocPosition = NSMakePoint(-1, -1);
    }
  return self;
}

- (void)dealloc
{
  [_itemID release];
  [_filename release];
  [super dealloc];
}

- (id)copyWithZone:(NSZone *)zone
{
  FSNIconItemData *copy = [[FSNIconItemData allocWithZone: zone] init];
  [copy setItemID: _itemID];
  [copy setFilename: _filename];
  [copy setPlacementMode: _placementMode];
  [copy setPixelPosition: _pixelPosition];
  [copy setIlocPosition: _ilocPosition];
  return copy;
}

- (NSString *)description
{
  return [NSString stringWithFormat:
    @"<FSNIconItemData %p: file=%@ mode=%lu pix=(%.0f,%.0f)>",
    self, _filename,
    (unsigned long)_placementMode,
    _pixelPosition.x, _pixelPosition.y];
}

@end
