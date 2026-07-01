/* GWIconPositionStore.m
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

#import <Foundation/Foundation.h>
#import "GWIconPositionStore.h"
#import "GSFileMetadata.h"
#import "GWViewSettingsManager.h"
#import "DSStoreInfo.h"

@implementation GWIconPositionStore

+ (instancetype)sharedStore
{
  static GWIconPositionStore *shared = nil;
  if (shared == nil)
    shared = [[self alloc] init];
  return shared;
}

/* Write one folder's batch of iloc entries (@[name, ilocX, ilocY]). */
- (void)writeBatch:(NSArray *)batch toFolder:(NSString *)folder
{
  NSUInteger bi;

  /* Persist the positions through the settings orchestrator, which owns the
   * write hierarchy: folder .DS_Store when writable (and not policy-blocked),
   * otherwise the per-volume cache.  Carry only the iloc positions; loading
   * inside saveToPath merges them with any existing view settings/labels. */
  DSStoreInfo *info = [DSStoreInfo infoForDirectoryPath: folder loadImmediately: NO];
  for (bi = 0; bi < [batch count]; bi++)
    {
      NSArray *entry = [batch objectAtIndex: bi];
      DSStoreIconInfo *ii = [DSStoreIconInfo infoForFilename: [entry objectAtIndex: 0]];
      [ii setPosition: NSMakePoint([[entry objectAtIndex: 1] intValue],
                                   [[entry objectAtIndex: 2] intValue])];
      [ii setHasPosition: YES];
      [info setIconInfo: ii forFilename: [entry objectAtIndex: 0]];
    }
  [[GWViewSettingsManager managerForDirectoryPath: folder] writeSettings: info];

  /* fdLocation xattr export, per file. */
  for (bi = 0; bi < [batch count]; bi++)
    {
      NSArray *entry = [batch objectAtIndex: bi];
      NSString *fullPath = [folder stringByAppendingPathComponent: [entry objectAtIndex: 0]];
      GSFileMetadata *md = [GSFileMetadata metadataForFileAtPath: fullPath];
      if (!md)
        md = [[[GSFileMetadata alloc] init] autorelease];
      [md setIconPosition: NSMakePoint((int16_t)[[entry objectAtIndex: 1] intValue],
                                        (int16_t)[[entry objectAtIndex: 2] intValue])];
      [md writeToFileAtPath: fullPath error: nil];
    }
}

- (void)saveIconPositionsByFolder:(NSDictionary *)positionsByFolder
{
  for (NSString *folder in positionsByFolder)
    [self writeBatch: [positionsByFolder objectForKey: folder] toFolder: folder];
}

- (NSDictionary *)storedIconPositionsForFolder:(NSString *)folder
{
  NSMutableDictionary *result = [NSMutableDictionary dictionary];
  if (folder == nil)
    return result;

  /* Read through the settings manager's hierarchy (folder .DS_Store, then
   * per-volume cache, then empty defaults) and pull out the iloc positions. */
  GWViewSettingsManager *sm = [GWViewSettingsManager managerForDirectoryPath: folder];
  DSStoreInfo *info = [sm readSettings];
  if (info == nil)
    return result;

  for (NSString *name in [info filenamesWithPositions])
    {
      DSStoreIconInfo *ii = [info iconInfoForFilename: name];
      if (ii && [ii hasPosition])
        [result setObject: [NSValue valueWithPoint: [ii position]] forKey: name];
    }
  return result;
}

- (void)saveIconPosition:(NSPoint)ilocCenter forFileAtPath:(NSString *)path
{
  if (!path)
    return;
  NSString *folder = [path stringByDeletingLastPathComponent];
  NSString *name = [path lastPathComponent];
  if ([folder length] == 0 || [name length] == 0)
    return;

  NSArray *entry = @[name,
                     [NSNumber numberWithInt: (int)ilocCenter.x],
                     [NSNumber numberWithInt: (int)ilocCenter.y]];
  [self writeBatch: [NSArray arrayWithObject: entry] toFolder: folder];
}

@end
