/* GWViewSettingsManager.m
 *
 * Central orchestrator for .DS_Store view-settings persistence.
 *
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-2.0-or-later
 */

#import "GWViewSettingsManager.h"
#import "GWVolumeCache.h"
#import "GWVolumeID.h"
#import "DSStoreInfo.h"
#import "DSStore.h"
#import "DSStoreEntry.h"

@implementation GWViewSettingsManager

@synthesize directoryPath = _directoryPath;
@synthesize volumeCache = _volumeCache;

/* ------------------------------------------------------------------ */
#pragma mark - Factory / Init
/* ------------------------------------------------------------------ */

+ (instancetype)managerForDirectoryPath:(NSString *)path
{
  return [[[self alloc] initWithDirectoryPath:path] autorelease];
}

- (instancetype)initWithDirectoryPath:(NSString *)path
{
  NSString *norm = [[path stringByStandardizingPath] stringByResolvingSymlinksInPath];

  return [self initWithDirectoryPath:path
                         volumeCache:[GWVolumeCache cacheForPath:(norm ? norm : path)]];
}

- (instancetype)initWithDirectoryPath:(NSString *)path volumeCache:(GWVolumeCache *)cache
{
  self = [super init];
  if (self) {
    /* Normalise */
    NSString *norm = [[path stringByStandardizingPath] stringByResolvingSymlinksInPath];
    _directoryPath = [(norm ? norm : path) copy];
    _volumeCache = [cache retain];
  }
  return self;
}

- (void)dealloc
{
  [_directoryPath release];
  [_volumeCache release];
  [super dealloc];
}

/* ------------------------------------------------------------------ */
#pragma mark - Read (spec §2)
/* ------------------------------------------------------------------ */

- (DSStoreInfo *)readSettings
{
  NSFileManager *fm = [NSFileManager defaultManager];
  BOOL hasOwnStore = [fm fileExistsAtPath:[self folderDSStorePath]];

  /* The folder's own "." records, its record in the parent's store (which
   * wins, being what Finder 10.6 reads [O:E1]) and the FinderInfo fallback. */
  DSStoreInfo *info = [DSStoreInfo infoForDirectoryPath:_directoryPath];

  /* The volume cache stands in for whatever store could not be written: the
   * folder's own (then it holds the icon positions too) or the parent's (then
   * only the folder's records).  It only fills what the stores left open. */
  if (_volumeCache) {
    DSStoreInfo *cached = hasOwnStore
      ? [_volumeCache readDirectoryInfoForDirectoryPath:_directoryPath]
      : [_volumeCache readInfoForDirectoryPath:_directoryPath];
    if (cached) {
      [info mergeMissingFieldsFromInfo:cached];
    }
  }
  return info;
}

/* ------------------------------------------------------------------ */
#pragma mark - Write (spec §3)
/* ------------------------------------------------------------------ */

- (BOOL)writeSettings:(DSStoreInfo *)info
{
  if (!info) return NO;

  BOOL storesAllowed = ![self isNetworkStoreWriteBlocked];
  BOOL wroteFolder = NO;
  BOOL wroteParent = NO;

  if (storesAllowed && [self isDirectoryWritable]) {
    wroteFolder = [info saveToPath:[self folderDSStorePath]];
  }
  if (storesAllowed) {
    wroteParent = [info saveToParentStore];
  }

  if (_volumeCache == nil) {
    return wroteFolder;
  }
  if (!wroteFolder) {
    return [_volumeCache writeInfo:info forDirectoryPath:_directoryPath];
  }
  /* Finder persists nothing for a folder whose parent cannot be written
   * [O:E14]; the cache keeps it for us.  A volume root or the home folder has
   * no parent record: its "." is all there is. */
  if (!wroteParent && [info hasFinderViewRecords]
      && [DSStoreInfo parentStorePathForDirectory:_directoryPath] != nil) {
    return [_volumeCache writeFinderViewRecordsOfInfo:info forDirectoryPath:_directoryPath];
  }
  /* Both stores hold the settings now; a cached copy would only go stale. */
  [_volumeCache removeRecordForDirectoryPath:_directoryPath];
  return YES;
}

/* Removes @p code under @p key from the store at @p path, if both exist. */
static void
removeRecord(NSString *path, NSString *key, NSString *code)
{
  DSStore *store;

  if (path == nil || ![[NSFileManager defaultManager] fileExistsAtPath:path]) {
    return;
  }
  store = [DSStore storeWithPath:path];
  if (![store load] || [store entryForFilename:key code:code] == nil) {
    return;
  }
  [store removeEntryForFilename:key code:code];
  if (![store save]) {
    NSLog(@"GWViewSettingsManager: cannot write %@", path);
  }
}

- (void)removeViewStyle
{
  removeRecord([DSStoreInfo parentStorePathForDirectory:_directoryPath],
               [_directoryPath lastPathComponent], @"vstl");
  removeRecord([self folderDSStorePath], @".", @"vstl");
  removeRecord([_volumeCache cacheFilePath], _directoryPath, @"vstl");
}

/* ------------------------------------------------------------------ */
#pragma mark - Policy checks
/* ------------------------------------------------------------------ */

- (BOOL)isDirectoryWritable
{
  NSFileManager *fm = [NSFileManager defaultManager];
  return [fm isWritableFileAtPath:_directoryPath];
}

- (BOOL)isNetworkStoreWriteBlocked
{
  if (![GWVolumeID isNetworkMount:_directoryPath]) return NO;
  return [[self class] dsDontWriteNetworkStores];
}

+ (BOOL)dsDontWriteNetworkStores
{
  /* macOS-compatible: check the desktopservices preference.
   * On Linux/GNUstep we check a GSDomain default as well.
   * Returns YES if the user has opted out of network .DS_Store writes. */

  /* Try macOS defaults command via NSTask as a compatibility shim */
  NSString *prefDomain = @"com.apple.desktopservices";
  NSString *prefKey    = @"DSDontWriteNetworkStores";

  /* First try NSUserDefaults with the domain */
  id val = [[NSUserDefaults standardUserDefaults]
             objectForKey:[NSString stringWithFormat:@"%@.%@", prefDomain, prefKey]];
  if (val) {
    if ([val respondsToSelector:@selector(boolValue)])
      return [val boolValue];
    if ([val respondsToSelector:@selector(intValue)])
      return [val intValue] != 0;
    if ([val isKindOfClass:[NSString class]]) {
      return [val isEqualToString:@"1"]
             || [val isEqualToString:@"true"]
             || [val isEqualToString:@"YES"];
    }
    return NO;
  }

  /* Also try a GSDomain-specific default (used by GNUstep preferences) */
  val = [[NSUserDefaults standardUserDefaults]
          objectForKey:prefKey];
  if (val) {
    if ([val respondsToSelector:@selector(boolValue)])
      return [val boolValue];
  }

  /* No macOS `defaults`/CFPreferences equivalent on GNUstep — the
   * NSUserDefaults checks above are the supported way to set this.
   * Default: allow network .DS_Store writes. */
  return NO;
}

/* ------------------------------------------------------------------ */
#pragma mark - Path helpers
/* ------------------------------------------------------------------ */

- (NSString *)folderDSStorePath
{
  return [_directoryPath stringByAppendingPathComponent:@".DS_Store"];
}

@end
