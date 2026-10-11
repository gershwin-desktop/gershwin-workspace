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

/* Older caches carry "<directory>/<name>" entries next to the bare names.
 * Under the root every entry starts with "/", so a scoped child of "/" is
 * only a name with no further separator; a plain prefix test would claim
 * every folder on the volume (and delete them all when "/" was saved). */
static BOOL
GWVolumeCacheIsScopedChild(NSString *filename, NSString *directory)
{
  if ([directory isEqualToString:@"/"]) {
    return [filename hasPrefix:@"/"]
           && [filename rangeOfString:@"/" options:0 range:NSMakeRange(1, [filename length] - 1)].location == NSNotFound;
  }
  return [filename hasPrefix:[directory stringByAppendingString:@"/"]];
}

@implementation GWVolumeCache

@synthesize cacheFilePath = _cacheFilePath;

/* ------------------------------------------------------------------ */
#pragma mark - Factory
/* ------------------------------------------------------------------ */

+ (instancetype)cacheForPath:(NSString *)path
{
  [GWVolumeID adoptLegacyCacheFileForPath:path];
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
    return nil;
  }

  /* Open and parse */
  DSStore *store = [DSStore storeWithPath:_cacheFilePath];
  if (![store load]) {
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
    return nil;
  }

  DSStoreInfo *info = [DSStoreInfo infoForDirectoryPath:dirPath loadImmediately:NO];

  /* Directory-level records under the folder's path, decoded exactly like
   * those in a folder's own or its parent's store. */
  [info takeDirectoryRecordsFromStore:store key:key];

  /* --- Per-file entries: icon positions (Iloc), label colors (lclr), comments (cmmt) ---
   * The macOS Finder writes these keyed by BARE filename (verified against
   * real Finder volume caches).  Caches written by older versions of this app
   * may additionally carry scoped "<key>/<filename>" entries.  Prefer the
   * bare-name form (the Mac convention and our new writes); only fall back to
   * a scoped entry when no bare entry exists for that file. */
  NSArray *allFiles = [store allFilenames];

  NSMutableArray *scopedFiles = [NSMutableArray array];
  NSMutableArray *bareFiles = [NSMutableArray array];
  for (NSString *filename in allFiles) {
    if ([filename isEqualToString:key]) continue;  /* dir-level entries */
    if (GWVolumeCacheIsScopedChild(filename, key)) {
      [scopedFiles addObject:filename];
    } else {
      [bareFiles addObject:filename];
    }
  }

  /* Pass 1: bare-name entries (Mac convention, authoritative).  Skip ghosts:
   * entries whose name is not an on-disk child of the directory would
   * otherwise collide with a live file that now has the same position. */
  NSSet *children = [DSStoreInfo childrenOfDirectory: dirPath];

  for (NSString *filename in bareFiles) {
    if ([key isEqualToString:@"/"] == NO && [filename rangeOfString:@"/"].location != NSNotFound)
      continue;
    if (children && [children containsObject: filename] == NO)
      continue;   /* ghost - drop */
    [self readPerFileEntry:filename bareName:filename fromStore:store into:info];
  }

  /* Pass 2: legacy scoped entries - only fill files that got no bare entry. */
  NSUInteger prefixLength = [key isEqualToString:@"/"] ? 1 : [key length] + 1;
  for (NSString *filename in scopedFiles) {
    NSString *bareName = [filename substringFromIndex:prefixLength];
    if ([info iconInfoForFilename: bareName] == nil) {
      [self readPerFileEntry:filename bareName:bareName fromStore:store into:info];
    }
  }

  [info markAsLoaded];
  return info;
}

/* Read Iloc/lclr/cmmt for one cache filename and apply to @p info under the
 * bare name. */
- (void)readPerFileEntry:(NSString *)filename
                bareName:(NSString *)bareName
               fromStore:(DSStore *)store
                    into:(DSStoreInfo *)info
{
  DSStoreIconInfo *ii =
    [DSStoreInfo iconInfoForFile: filename bareName: bareName fromStore: store];
  if (ii) {
    [info setIconInfo: ii forFilename: bareName];
  }
}

- (DSStoreInfo *)readDirectoryInfoForDirectoryPath:(NSString *)dirPath
{
  NSString *key = [[dirPath stringByStandardizingPath] stringByResolvingSymlinksInPath];
  if (!key) key = dirPath;
  if (![self cacheFileExists]) return nil;

  DSStore *store = [DSStore storeWithPath:_cacheFilePath];
  if (![store load] || [[store allCodesForFilename:key] count] == 0) {
    return nil;
  }
  DSStoreInfo *info = [DSStoreInfo infoForDirectoryPath:dirPath loadImmediately:NO];
  [info takeDirectoryRecordsFromStore:store key:key];
  [info markAsLoaded];
  return info;
}

- (DSStore *)openOrCreateStore
{
  NSFileManager *fm = [NSFileManager defaultManager];
  NSString *cacheDir = [_cacheFilePath stringByDeletingLastPathComponent];
  if (![fm fileExistsAtPath:cacheDir]
      && ![fm createDirectoryAtPath:cacheDir withIntermediateDirectories:YES
                         attributes:nil error:NULL]) {
    return nil;
  }
  if ([fm fileExistsAtPath:_cacheFilePath]) {
    DSStore *store = [DSStore storeWithPath:_cacheFilePath];
    if ([store load]) {
      return store;
    }
  }
  DSStore *store = [DSStore createStoreAtPath:_cacheFilePath withEntries:nil];
  [store load];
  return store;
}

- (BOOL)writeFinderViewRecordsOfInfo:(DSStoreInfo *)info forDirectoryPath:(NSString *)dirPath
{
  if (!info || !dirPath || !_cacheFilePath) return NO;

  NSString *key = [[dirPath stringByStandardizingPath] stringByResolvingSymlinksInPath];
  if (!key) key = dirPath;

  DSStore *store = [self openOrCreateStore];
  if (!store) return NO;
  [DSStoreInfo writeFinderViewRecordsForInfo:info key:key toStore:store];
  return [store save];
}

- (BOOL)writeInfo:(DSStoreInfo *)info forDirectoryPath:(NSString *)dirPath
{
  if (!info || !dirPath || !_cacheFilePath) return NO;

  NSString *key = [[dirPath stringByStandardizingPath] stringByResolvingSymlinksInPath];
  if (!key) key = dirPath;

  DSStore *store = [self openOrCreateStore];
  if (!store) return NO;

  /* Merge, don't clobber: a caller may persist a partial DSStoreInfo (icon
   * positions only, label colors only, ...).  Load the existing cached
   * record for this directory and fold in any fields the incoming info does
   * not carry, so window geometry / view settings survive partial writes.
   * Without this the removeAllEntriesForFilename: below would drop them. */
  {
    DSStoreInfo *existing = [self readInfoForDirectoryPath: dirPath];
    if (existing != nil && existing != info) {
      [info mergeMissingFieldsFromInfo: existing];
    }
  }

  /* Remove the directory key's OWNED records (cooperative merge).  Only the
   * 4CC codes Workspace writes are dropped; any unknown record type under the
   * key that Finder wrote is preserved and carried forward. */
  [store removeEntriesForFilename: key
                            codes: [DSStoreInfo ownedDirectoryCodes]];


  /* --- Write directory-level + per-file entries keyed by the dir path.
   * Per-file Iloc entries are keyed by BARE filename, matching the macOS
   * Finder convention (verified against real Finder volume caches: directory
   * window settings are keyed by full path, per-file Iloc entries by bare
   * filename).  Older caches written by this app may still carry scoped
   * "<key>/<filename>" entries; the read side prefers the bare form and falls
   * back to those. --- */
  [DSStoreInfo writeStoreEntriesForInfo: info
                                    key: key
                                toStore: store];

  /* Prune ghost per-file entries on write: remove bare-name Iloc/lclr/cmmt
   * entries for files that are no longer on-disk children of this directory.
   * A foreign Finder (or a removed/renamed file) leaves such entries, and they
   * collide with a live file that now has the same position.  The directory's
   * own path-keyed record is never pruned. */
  [DSStoreInfo pruneNonChildEntriesInStore: store
                              forDirectory: dirPath
                                  keepPath: key];

  BOOL saved = [store save];
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

  /* Also remove any legacy scoped child-file entries ("<key>/<filename>")
   * written by older versions of this app.  Bare-name entries are NOT removed:
   * they are volume-global (the Mac convention) and may belong to another
   * directory.  The root "/" itself is already a "/" - do not build a "//"
   * prefix. */
  NSArray *allFiles = [store allFilenames];
  for (NSString *fname in allFiles) {
    if (GWVolumeCacheIsScopedChild(fname, key) && [fname isEqualToString:key] == NO) {
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

  DSStore *store = [self openOrCreateStore];
  if (!store) return NO;

  /* Write each icon position as an Iloc entry keyed by BARE filename,
   * matching the macOS Finder convention. */
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
