/* GWVolumeCache.m
 *
 * Per-volume .DS_Store cache implementation.
 *
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-2.0-or-later
 */

#import "GWVolumeCache.h"
#import "GWVolumeID.h"
#import "DSStoreInfo.h"
#import "DSStore.h"
#import "DSStoreEntry.h"

@implementation GWVolumeCache

@synthesize cacheFilePath = _cacheFilePath;

/* ------------------------------------------------------------------ */
#pragma mark - Factory
/* ------------------------------------------------------------------ */

+ (instancetype)cacheForPath:(NSString *)path
{
  NSString *cachePath = [GWVolumeID cacheFilePathForPath:path];
  if (!cachePath) return nil;

  return [[[self alloc] initWithCacheFilePath:cachePath] autorelease];
}

- (instancetype)initWithCacheFilePath:(NSString *)cacheFilePath
{
  self = [super init];
  if (self) {
    _cacheFilePath = [cacheFilePath copy];
  }
  return self;
}

- (void)dealloc
{
  [_cacheFilePath release];
  [super dealloc];
}

/* ------------------------------------------------------------------ */
#pragma mark - Cache operations
/* ------------------------------------------------------------------ */

- (BOOL)cacheFileExists
{
  return [[NSFileManager defaultManager] fileExistsAtPath:_cacheFilePath];
}

- (DSStoreInfo *)readInfoForDirectoryPath:(NSString *)dirPath
{
  if (!dirPath || !_cacheFilePath) return nil;

  /* Normalise the path for use as a cache key */
  NSString *key = [[dirPath stringByStandardizingPath] stringByResolvingSymlinksInPath];
  if (!key) key = dirPath;

  /* If the cache file doesn't exist, nothing to read */
  if (![self cacheFileExists]) {
    NSDebugLLog(@"gwspace", @"GWVolumeCache: No cache file at %@", _cacheFilePath);
    return nil;
  }

  /* Open and parse */
  DSStore *store = [DSStore storeWithPath:_cacheFilePath];
  if (![store load]) {
    NSDebugLLog(@"gwspace", @"GWVolumeCache: Failed to load %@", _cacheFilePath);
    return nil;
  }

  /* Check whether the cache has any entries for this directory.
   * A record may consist of:
   *   (a) directory-level entries keyed by the directory path (from
   *       writeInfo:forDirectoryPath:), or
   *   (b) per-file entries keyed by bare filenames (from
   *       writeIconPositions:forDirectoryPath:, which stores only
   *       Iloc entries without a directory-level marker).
   *
   * We accept either form. */
  NSArray *dirCodes = [store allCodesForFilename:key];
  BOOL hasDirEntries = (dirCodes && [dirCodes count] > 0);
  BOOL hasFileEntries = NO;
  if (!hasDirEntries) {
    /* Check for per-file entries.  The key is the directory path; any
     * filename in the store that is NOT the key is a per-file entry. */
    NSArray *allFnames = [store allFilenames];
    for (NSString *fn in allFnames) {
      if (![fn isEqualToString:key]) {
        hasFileEntries = YES;
        break;
      }
    }
  }

  if (!hasDirEntries && !hasFileEntries) {
    NSDebugLLog(@"gwspace", @"GWVolumeCache: No cached record for %@", key);
    return nil;
  }

  DSStoreInfo *info = [DSStoreInfo infoForDirectoryPath:dirPath loadImmediately:NO];

  /* --- Window geometry (bwsp) --- */
  DSStoreEntry *bwsp = [store entryForFilename:key code:@"bwsp"];
  if (bwsp && [[bwsp type] isEqualToString:@"blob"]) {
    NSData *data = (NSData *)[bwsp value];
    NSError *err = nil;
    NSDictionary *plist = [NSPropertyListSerialization propertyListWithData:data
                                                                    options:NSPropertyListImmutable
                                                                     format:NULL
                                                                      error:&err];
    if (plist && [plist isKindOfClass:[NSDictionary class]]) {
      NSString *bounds = [plist objectForKey:@"WindowBounds"];
      if (bounds) {
        NSRect r = NSRectFromString(bounds);
        if (r.size.width > 0 && r.size.height > 0) {
          [info setWindowFrame:r];
          [info setHasWindowFrame:YES];
        }
      }
      id sw = [plist objectForKey:@"SidebarWidth"];
      if (sw) {
        [info setSidebarWidth:[sw intValue]];
        [info setHasSidebarWidth:YES];
      }
    }
  }

  /* --- Legacy window geometry (fwi0) --- */
  if (![info hasWindowFrame]) {
    DSStoreEntry *fwi0 = [store entryForFilename:key code:@"fwi0"];
    if (fwi0 && [[fwi0 type] isEqualToString:@"blob"]) {
      NSData *data = (NSData *)[fwi0 value];
      if ([data length] >= 8) {
        const uint8_t *b = (const uint8_t *)[data bytes];
        uint16_t top    = (b[0] << 8) | b[1];
        uint16_t left   = (b[2] << 8) | b[3];
        uint16_t bottom = (b[4] << 8) | b[5];
        uint16_t right  = (b[6] << 8) | b[7];
        NSRect r = NSMakeRect(left, top, right - left, bottom - top);
        [info setWindowFrame:r];
        [info setHasWindowFrame:YES];
      }
    }
  }

  /* --- View style (vstl) --- */
  DSStoreEntry *vstl = [store entryForFilename:key code:@"vstl"];
  if (vstl && [[vstl type] isEqualToString:@"type"]) {
    NSString *style = (NSString *)[vstl value];
    if ([style isEqualToString:@"icnv"])
      [info setViewStyle:DSStoreViewStyleIcon];
    else if ([style isEqualToString:@"Nlsv"])
      [info setViewStyle:DSStoreViewStyleList];
    else if ([style isEqualToString:@"clmv"])
      [info setViewStyle:DSStoreViewStyleColumn];
    else if ([style isEqualToString:@"glyv"])
      [info setViewStyle:DSStoreViewStyleGallery];
    else if ([style isEqualToString:@"Flwv"])
      [info setViewStyle:DSStoreViewStyleCoverflow];
    [info setHasViewStyle:YES];
  }

  /* --- Icon size (icvo/icvp) --- */
  DSStoreEntry *icvo = [store entryForFilename:key code:@"icvo"];
  if (icvo && [[icvo type] isEqualToString:@"blob"]) {
    NSData *data = (NSData *)[icvo value];
    if ([data length] >= 4) {
      const uint8_t *b = (const uint8_t *)[data bytes];
      /* Try icv4 format first: size at offset 4-5, big-endian */
      char magic[5] = {b[0], b[1], b[2], b[3], 0};
      int size = 0;
      if (strcmp(magic, "icv4") == 0 && [data length] >= 6) {
        size = (b[4] << 8) | b[5];
      } else if ([data length] >= 14) {
        size = (b[12] << 8) | b[13];  /* old icvo format */
      }
      if (size > 0 && size <= 512) {
        [info setIconSize:size];
        [info setHasIconSize:YES];
      }
    }
  }

  /* Also check icvp plist for icon size */
  DSStoreEntry *icvp = [store entryForFilename:key code:@"icvp"];
  if (icvp && [[icvp type] isEqualToString:@"blob"]) {
    NSData *data = (NSData *)[icvp value];
    NSError *err = nil;
    NSDictionary *plist = [NSPropertyListSerialization propertyListWithData:data
                                                                    options:NSPropertyListImmutable
                                                                     format:NULL
                                                                      error:&err];
    if (plist && [plist isKindOfClass:[NSDictionary class]]) {
      id sz = [plist objectForKey:@"iconSize"];
      if (sz && !info.hasIconSize) {
        int v = [sz intValue];
        if (v > 0 && v <= 512) {
          [info setIconSize:v];
          [info setHasIconSize:YES];
        }
      }
      /* Arrangement from plist */
      id arr = [plist objectForKey:@"arrangeBy"];
      if (arr) {
        NSString *a = [arr description];
        if ([a isEqualToString:@"grid"] || [a isEqualToString:@"1"]) {
          [info setIconArrangement:DSStoreIconArrangementGrid];
        } else {
          [info setIconArrangement:DSStoreIconArrangementNone];
        }
        [info setHasIconArrangement:YES];
      }
      /* Label position */
      id lbl = [plist objectForKey:@"labelOnBottom"];
      if (lbl) {
        [info setLabelPosition:[lbl boolValue] ? DSStoreLabelPositionBottom
                           : DSStoreLabelPositionRight];
        [info setHasLabelPosition:YES];
      }
      /* Grid spacing */
      id gs = [plist objectForKey:@"gridSpacing"];
      if (gs) {
        [info setGridSpacing:[gs floatValue]];
        [info setHasGridSpacing:YES];
      }
    }
  }

  /* --- Background --- */
  DSStoreEntry *bkgd = [store entryForFilename:key code:@"BKGD"];
  if (bkgd && [[bkgd type] isEqualToString:@"blob"]) {
    NSData *data = (NSData *)[bkgd value];
    if ([data length] >= 4) {
      const char *b = (const char *)[data bytes];
      if (strncmp(b, "ClrB", 4) == 0 && [data length] >= 10) {
        const uint8_t *cb = (const uint8_t *)b;
        CGFloat r = ((cb[4] << 8) | cb[5]) / 65535.0;
        CGFloat g = ((cb[6] << 8) | cb[7]) / 65535.0;
        CGFloat bl= ((cb[8] << 8) | cb[9]) / 65535.0;
        [info setBackgroundColor:[NSColor colorWithCalibratedRed:r green:g blue:bl alpha:1.0]];
        [info setBackgroundType:DSStoreBackgroundColor];
      } else if (strncmp(b, "PctB", 4) == 0) {
        [info setBackgroundType:DSStoreBackgroundPicture];
      } else {
        [info setBackgroundType:DSStoreBackgroundDefault];
      }
    }
  }

  /* --- Sidebar width (fwsw) --- */
  DSStoreEntry *fwsw = [store entryForFilename:key code:@"fwsw"];
  if (fwsw && [[fwsw type] isEqualToString:@"long"]) {
    [info setSidebarWidth:[[fwsw value] intValue]];
    [info setHasSidebarWidth:YES];
  }

  /* --- Per-file entries: icon positions (Iloc), label colors (lclr), comments (cmmt) --- */
  NSArray *allFiles = [store allFilenames];
  for (NSString *filename in allFiles) {
    if ([filename isEqualToString:key]) continue;  /* dir-level entries */

    BOOL hasData = NO;
    DSStoreIconInfo *ii = nil;

    /* Iloc: icon location */
    DSStoreEntry *iloc = [store entryForFilename:filename code:@"Iloc"];
    if (iloc && [[iloc type] isEqualToString:@"blob"]) {
      NSData *data = (NSData *)[iloc value];
      if ([data length] >= 8) {
        const uint8_t *b = (const uint8_t *)[data bytes];
        int32_t x = (int32_t)((b[0] << 24) | (b[1] << 16) | (b[2] << 8) | b[3]);
        int32_t y = (int32_t)((b[4] << 24) | (b[5] << 16) | (b[6] << 8) | b[7]);
        if (!ii) ii = [DSStoreIconInfo infoForFilename:filename];
        [ii setPosition:NSMakePoint((CGFloat)x, (CGFloat)y)];
        [ii setHasPosition:YES];
        hasData = YES;
      }
    }

    /* lclr: label color */
    DSStoreEntry *lclr = [store entryForFilename:filename code:@"lclr"];
    if (lclr && [[lclr type] isEqualToString:@"long"]) {
      if (!ii) ii = [DSStoreIconInfo infoForFilename:filename];
      [ii setLabelColor:(DSStoreLabelColor)[[lclr value] intValue]];
      [ii setHasLabelColor:YES];
      hasData = YES;
    }

    /* cmmt: comments */
    DSStoreEntry *cmmt = [store entryForFilename:filename code:@"cmmt"];
    if (cmmt && [[cmmt type] isEqualToString:@"ustr"]) {
      if (!ii) ii = [DSStoreIconInfo infoForFilename:filename];
      [ii setComments:(NSString *)[cmmt value]];
      hasData = YES;
    }

    if (hasData && ii) {
      [info setIconInfo:ii forFilename:filename];
    }
  }

  [info markAsLoaded];
  return info;
}

- (BOOL)writeInfo:(DSStoreInfo *)info forDirectoryPath:(NSString *)dirPath
{
  if (!info || !dirPath || !_cacheFilePath) return NO;

  NSString *key = [[dirPath stringByStandardizingPath] stringByResolvingSymlinksInPath];
  if (!key) key = dirPath;

  /* Ensure cache directory exists */
  NSString *cacheDir = [_cacheFilePath stringByDeletingLastPathComponent];
  NSFileManager *fm = [NSFileManager defaultManager];
  BOOL isDir = NO;
  if (![fm fileExistsAtPath:cacheDir isDirectory:&isDir]) {
    if (![fm createDirectoryAtPath:cacheDir
       withIntermediateDirectories:YES
                        attributes:nil
                             error:NULL]) {
      NSDebugLLog(@"gwspace", @"GWVolumeCache: Cannot create cache dir %@", cacheDir);
      return NO;
    }
  }

  /* Open existing cache or create new */
  DSStore *store;
  if ([fm fileExistsAtPath:_cacheFilePath]) {
    store = [DSStore storeWithPath:_cacheFilePath];
    if (![store load]) {
      NSDebugLLog(@"gwspace", @"GWVolumeCache: Failed to load cache, creating new");
      store = [DSStore createStoreAtPath:_cacheFilePath withEntries:nil];
      if (store) [store load];
    }
  } else {
    store = [DSStore createStoreAtPath:_cacheFilePath withEntries:nil];
    if (store) [store load];
  }

  if (!store) return NO;

  /* Remove any existing entries for this key (clean merge) */
  [store removeAllEntriesForFilename:key];

  NSDebugLLog(@"gwspace", @"GWVolumeCache: writing for %@ (key=%@, cache=%@)",
              dirPath, key, _cacheFilePath);

  /* --- Write directory-level entries keyed by the directory path --- */
  if ([info hasViewStyle]) {
    NSString *styleStr = @"icnv";
    switch ([info viewStyle]) {
      case DSStoreViewStyleIcon:     styleStr = @"icnv"; break;
      case DSStoreViewStyleList:     styleStr = @"Nlsv"; break;
      case DSStoreViewStyleColumn:   styleStr = @"clmv"; break;
      case DSStoreViewStyleGallery:  styleStr = @"glyv"; break;
      case DSStoreViewStyleCoverflow:styleStr = @"Flwv"; break;
    }
    DSStoreEntry *e = [DSStoreEntry viewStyleEntryForFile:key style:styleStr];
    if (e) [store setEntry:e];
  }

  if ([info hasIconSize] && [info iconSize] > 0 && [info iconSize] <= 512) {
    DSStoreEntry *e = [DSStoreEntry iconSizeEntryForFile:key size:[info iconSize]];
    if (e) [store setEntry:e];
  }

  if ([info hasIconArrangement]) {
    int arr = ([info iconArrangement] == DSStoreIconArrangementGrid) ? 1 : 0;
    DSStoreEntry *e = [DSStoreEntry iconArrangementEntryForFile:key arrangement:arr];
    if (e) [store setEntry:e];
  }

  if ([info hasLabelPosition]) {
    int pos = ([info labelPosition] == DSStoreLabelPositionBottom) ? 0 : 1;
    DSStoreEntry *e = [DSStoreEntry labelPositionEntryForFile:key position:pos];
    if (e) [store setEntry:e];
  }

  if ([info hasGridSpacing] && [info gridSpacing] > 0) {
    DSStoreEntry *e = [DSStoreEntry gridSpacingEntryForFile:key
                                                    spacing:(int)[info gridSpacing]];
    if (e) [store setEntry:e];
  }

  if ([info backgroundType] == DSStoreBackgroundColor && [info backgroundColor]) {
    CGFloat r, g, b, a;
    [[info backgroundColor] getRed:&r green:&g blue:&b alpha:&a];
    DSStoreEntry *e = [DSStoreEntry backgroundColorEntryForFile:key
                                                           red:(int)(r * 65535.0)
                                                         green:(int)(g * 65535.0)
                                                          blue:(int)(b * 65535.0)];
    if (e) [store setEntry:e];
  }

  if ([info hasSidebarWidth]) {
    DSStoreEntry *e = [DSStoreEntry sidebarWidthEntryForFile:key width:[info sidebarWidth]];
    if (e) [store setEntry:e];
  }

  if ([info hasListTextSize]) {
    DSStoreEntry *e = [DSStoreEntry textSizeEntryForFile:key size:[info listTextSize]];
    if (e) [store setEntry:e];
  }

  /* Write icon positions for child files */
  NSDictionary *allIcons = [info allIconInfo];
  NSDebugLLog(@"gwspace", @"GWVolumeCache: writing %lu icon entries for %@",
              (unsigned long)[allIcons count], key);
  for (NSString *filename in allIcons) {
    DSStoreIconInfo *ii = [allIcons objectForKey:filename];
    NSDebugLLog(@"gwspace", @"GWVolumeCache:   file='%@' pos=%d lbl=%d",
                filename, [ii hasPosition], [ii hasLabelColor]);
    if ([ii hasPosition]) {
      DSStoreEntry *e = [DSStoreEntry iconLocationEntryForFile:filename
                                                             x:(int)[ii position].x
                                                             y:(int)[ii position].y];
      if (e) [store setEntry:e];
    }
    if ([ii comments]) {
      DSStoreEntry *e = [DSStoreEntry commentsEntryForFile:filename
                                                  comments:[ii comments]];
      if (e) [store setEntry:e];
    }
    if ([ii hasLabelColor]) {
      DSStoreEntry *e = [DSStoreEntry labelColorEntryForFile:filename
                                                       color:(int)[ii labelColor]];
      if (e) [store setEntry:e];
    }
  }

  BOOL saved = [store save];
  NSDebugLLog(@"gwspace", @"GWVolumeCache: save %s for %@ (%lu entries)",
              saved ? "OK" : "FAILED", dirPath,
              (unsigned long)[[store entries] count]);
  return saved;
}

- (BOOL)removeRecordForDirectoryPath:(NSString *)dirPath
{
  if (!dirPath || !_cacheFilePath) return YES;  /* nothing to remove */

  NSString *key = [[dirPath stringByStandardizingPath] stringByResolvingSymlinksInPath];
  if (!key) key = dirPath;

  if (![self cacheFileExists]) return YES;

  DSStore *store = [DSStore storeWithPath:_cacheFilePath];
  if (![store load]) {
    /* File exists but is corrupt; remove it */
    [[NSFileManager defaultManager] removeItemAtPath:_cacheFilePath error:NULL];
    return YES;
  }

  [store removeAllEntriesForFilename:key];

  /* Also remove any child-file entries from the cache that are
   * icon positions for files in this directory.  We do this by
   * checking if any filename starts with the key + "/". */
  NSArray *allFiles = [store allFilenames];
  NSString *keyPrefix = [key stringByAppendingString:@"/"];
  for (NSString *fname in allFiles) {
    if ([fname hasPrefix:keyPrefix]) {
      [store removeAllEntriesForFilename:fname];
    }
  }

  return [store save];
}

- (BOOL)writeIconPositions:(NSArray *)positions forDirectoryPath:(NSString *)dirPath
{
  if (!positions || !dirPath || !_cacheFilePath) return NO;

  NSString *key = [[dirPath stringByStandardizingPath] stringByResolvingSymlinksInPath];
  if (!key) key = dirPath;

  /* Ensure cache directory exists */
  NSString *cacheDir = [_cacheFilePath stringByDeletingLastPathComponent];
  NSFileManager *fm = [NSFileManager defaultManager];
  BOOL isDir = NO;
  if (![fm fileExistsAtPath:cacheDir isDirectory:&isDir]) {
    if (![fm createDirectoryAtPath:cacheDir
       withIntermediateDirectories:YES
                        attributes:nil
                             error:NULL]) {
      return NO;
    }
  }

  /* Open or create the cache */
  DSStore *store;
  if ([fm fileExistsAtPath:_cacheFilePath]) {
    store = [DSStore storeWithPath:_cacheFilePath];
    if (![store load]) {
      store = [DSStore createStoreAtPath:_cacheFilePath withEntries:nil];
      if (store) [store load];
    }
  } else {
    store = [DSStore createStoreAtPath:_cacheFilePath withEntries:nil];
    if (store) [store load];
  }

  if (!store) return NO;

  /* Write each icon position as an Iloc entry keyed by the child filename */
  for (NSDictionary *pos in positions) {
    NSString *name = [pos objectForKey:@"name"];
    NSNumber *xVal = [pos objectForKey:@"x"];
    NSNumber *yVal = [pos objectForKey:@"y"];
    if (name && xVal && yVal) {
      DSStoreEntry *e = [DSStoreEntry iconLocationEntryForFile:name
                                                             x:[xVal intValue]
                                                             y:[yVal intValue]];
      if (e) [store setEntry:e];
    }
  }

  return [store save];
}

@end
