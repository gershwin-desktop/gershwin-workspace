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
  self = [super init];
  if (self) {
    /* Normalise */
    NSString *norm = [[path stringByStandardizingPath] stringByResolvingSymlinksInPath];
    _directoryPath = [(norm ? norm : path) copy];

    _volumeCache = [[GWVolumeCache cacheForPath:_directoryPath] retain];
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
  DSStoreInfo *info = nil;

  /* Tier 1: per-folder .DS_Store */
  NSString *dotDSStore = [self folderDSStorePath];
  NSFileManager *fm = [NSFileManager defaultManager];

  if ([fm fileExistsAtPath:dotDSStore]) {
    info = [DSStoreInfo infoForDirectoryPath:_directoryPath];
    if ([info loaded]) {
      NSDebugLLog(@"gwspace", @"GWViewSettingsManager: ✓ Read from per-folder .DS_Store for %@",
                  _directoryPath);
      return info;
    }
    [info release];
    info = nil;
  }

  /* Tier 2: per-volume cache */
  if (_volumeCache) {
    info = [_volumeCache readInfoForDirectoryPath:_directoryPath];
    if (info) {
      NSDebugLLog(@"gwspace", @"GWViewSettingsManager: ✓ Read from per-volume cache for %@",
                  _directoryPath);
      return info;
    }
  }

  /* Tier 3: defaults — return a fresh, unloaded DSStoreInfo */
  info = [DSStoreInfo infoForDirectoryPath:_directoryPath loadImmediately:NO];
  NSDebugLLog(@"gwspace", @"GWViewSettingsManager: Using defaults for %@", _directoryPath);
  return info;
}

/* ------------------------------------------------------------------ */
#pragma mark - Write (spec §3)
/* ------------------------------------------------------------------ */

- (BOOL)writeSettings:(DSStoreInfo *)info
{
  if (!info) return NO;

  BOOL wroteFolder = NO;
  NSString *dotDSStore = [self folderDSStorePath];

  /* Check whether we should try writing the per-folder .DS_Store */
  BOOL canWriteFolder = [self isDirectoryWritable]
                         && ![self isNetworkStoreWriteBlocked];

  if (canWriteFolder) {
    wroteFolder = [info saveToPath:dotDSStore];
    if (wroteFolder) {
      NSDebugLLog(@"gwspace", @"GWViewSettingsManager: ✓ Wrote per-folder .DS_Store for %@",
                  _directoryPath);

      /* Spec §3 step 3: cache cleanup — remove stale entry from cache */
      if (_volumeCache) {
        [_volumeCache removeRecordForDirectoryPath:_directoryPath];
      }
    } else {
      NSDebugLLog(@"gwspace", @"GWViewSettingsManager: ⚠ Per-folder .DS_Store write failed for %@",
                  _directoryPath);
    }
  } else {
    NSString *reason = ![self isDirectoryWritable]
                        ? @"directory not writable"
                        : @"DSDontWriteNetworkStores blocks network writes";
    NSDebugLLog(@"gwspace", @"GWViewSettingsManager: Skipping per-folder .DS_Store (%@) for %@",
                reason, _directoryPath);
  }

  /* Spec §3 step 2: fallback to per-volume cache */
  if (!wroteFolder && _volumeCache) {
    NSDebugLLog(@"gwspace", @"GWViewSettingsManager: cache path=%@ for %@",
                [_volumeCache cacheFilePath], _directoryPath);
    BOOL wroteCache = [_volumeCache writeInfo:info forDirectoryPath:_directoryPath];
    if (wroteCache) {
      NSDebugLLog(@"gwspace", @"GWViewSettingsManager: ✓ Wrote per-volume cache for %@",
                  _directoryPath);
      return YES;
    } else {
      NSDebugLLog(@"gwspace", @"GWViewSettingsManager: ✗ Failed cache write for %@",
                  _directoryPath);
      return NO;
    }
  } else if (!wroteFolder) {
    NSDebugLLog(@"gwspace", @"GWViewSettingsManager: ✗ No cache fallback for %@ (_volumeCache=%@)",
                _directoryPath, _volumeCache);
  }

  return wroteFolder;
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

  /* Fallback: try running `defaults read` via NSTask */
  NSTask *task = [[NSTask alloc] init];
  NSPipe *pipe = [NSPipe pipe];

  @try {
    [task setLaunchPath:@"/usr/bin/defaults"];
    [task setArguments:[NSArray arrayWithObjects:@"read", prefDomain, prefKey, nil]];
    [task setStandardOutput:pipe];
    [task setStandardError:[NSFileHandle fileHandleWithNullDevice]];
    [task launch];
    [task waitUntilExit];

    if ([task terminationStatus] == 0) {
      NSData *data = [[pipe fileHandleForReading] readDataToEndOfFile];
      NSString *output = [[[NSString alloc] initWithData:data
                                                encoding:NSUTF8StringEncoding] autorelease];
      output = [output stringByTrimmingCharactersInSet:
                         [NSCharacterSet whitespaceAndNewlineCharacterSet]];
      BOOL blocked = [output isEqualToString:@"1"]
                      || [output isEqualToString:@"true"]
                      || [output isEqualToString:@"YES"];
      [task release];
      return blocked;
    }
  } @catch (NSException *e) {
    NSDebugLLog(@"gwspace", @"GWViewSettingsManager: defaults read failed: %@", e);
  }

  [task release];
  return NO;  /* default: allow network .DS_Store writes */
}

/* ------------------------------------------------------------------ */
#pragma mark - Path helpers
/* ------------------------------------------------------------------ */

- (NSString *)folderDSStorePath
{
  return [_directoryPath stringByAppendingPathComponent:@".DS_Store"];
}

@end
