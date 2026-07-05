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

/* Write one folder's batch of iloc entries (@[name, ilocX, ilocY]).
 *
 * Combines persistence into three distinct phases so that all reads happen
 * together, then all writes happen together - no interleaving of metadata
 * reads and writes that could trigger cache-invalidation use-after-free. */
- (void)writeBatch:(NSArray *)batch toFolder:(NSString *)folder
{
  NSUInteger bi, count = [batch count];
  if (count == 0) return;

  /* Phase 1: Combine all icon positions into a single .DS_Store write. */
  {
    DSStoreInfo *info = [DSStoreInfo infoForDirectoryPath: folder loadImmediately: NO];
    for (bi = 0; bi < count; bi++)
      {
        NSArray *entry = [batch objectAtIndex: bi];
        DSStoreIconInfo *ii = [DSStoreIconInfo infoForFilename: [entry objectAtIndex: 0]];
        [ii setPosition: NSMakePoint([[entry objectAtIndex: 1] intValue],
                                      [[entry objectAtIndex: 2] intValue])];
        [ii setHasPosition: YES];
        [info setIconInfo: ii forFilename: [entry objectAtIndex: 0]];
      }
    [[GWViewSettingsManager managerForDirectoryPath: folder] writeSettings: info];
  }

  /* Phase 2: Collect all per-file metadata, modifying positions in memory.
   * All reads happen here — the GSFileMetadata cache is populated with every
   * entry before any xattr write touches the filesystem. */
  {
    NSMutableArray *mds = [NSMutableArray arrayWithCapacity: count];
    NSMutableArray *paths = [NSMutableArray arrayWithCapacity: count];

    for (bi = 0; bi < count; bi++)
      {
        NSArray *entry = [batch objectAtIndex: bi];
        NSString *fullPath = [folder stringByAppendingPathComponent: [entry objectAtIndex: 0]];
        GSFileMetadata *md = [GSFileMetadata metadataForFileAtPath: fullPath];
        if (!md)
          md = [[[GSFileMetadata alloc] init] autorelease];
        [md setIconPosition: NSMakePoint((int16_t)[[entry objectAtIndex: 1] intValue],
                                          (int16_t)[[entry objectAtIndex: 2] intValue])];
        [mds addObject: md];
        [paths addObject: fullPath];
      }

    /* Phase 3: Flush all xattr writes.  The metadata objects are kept alive
     * by the array (and the GSFileMetadata cache), so self remains valid
     * through every writeToFileAtPath:error: call - no use-after-free even if
     * the implementation temporarily removes the cache entry. */
    for (bi = 0; bi < count; bi++)
      {
        [[mds objectAtIndex: bi] writeToFileAtPath: [paths objectAtIndex: bi] error: nil];
      }
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
