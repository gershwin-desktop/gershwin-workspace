/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-2.0-or-later
 */

/* Where GWViewSettingsManager puts a folder's view settings when a store
 * cannot be written (FEATURES.md: read-only folder layout, network folder
 * layout, root volume layout): the folder's own store, the parent's store,
 * or the per-volume cache.
 *
 * A store is made unwritable by putting a directory where the .DS_Store file
 * would go: unlike chmod, that also holds when the suite runs as root, as
 * it does in the CI containers. */

#import <Foundation/Foundation.h>
#import "Testing.h"
#import "GWTestTemporaryDirectory.h"

#include <unistd.h>

#include "../../Workspace/FileViewer/GWViewSettingsManager.m"

/* Stands in for a folder on a network mount with DSDontWriteNetworkStores
 * set; the statfs probe itself cannot be faked without a real share. */
@interface NetworkBlockedManager : GWViewSettingsManager
@end
@implementation NetworkBlockedManager
- (BOOL)isNetworkStoreWriteBlocked { return YES; }
@end

static NSString *
makeDir(NSString *path)
{
  [[NSFileManager defaultManager] createDirectoryAtPath: path
                            withIntermediateDirectories: YES
                                             attributes: nil
                                                  error: NULL];
  return path;
}

/* A directory named .DS_Store: no store can be loaded or saved there. */
static void
blockStore(NSString *dir)
{
  makeDir([dir stringByAppendingPathComponent: @".DS_Store"]);
}

static BOOL
isStoreFile(NSString *dir)
{
  BOOL isDir = YES;

  return [[NSFileManager defaultManager]
           fileExistsAtPath: [dir stringByAppendingPathComponent: @".DS_Store"]
                isDirectory: &isDir] && !isDir;
}

static DSStoreInfo *
listViewInfo(GWViewSettingsManager *sm)
{
  DSStoreInfo *info = [sm readSettings];

  [info takeValuesFromViewerPrefs: @{ @"viewtype" : @"List" }];
  return info;
}

static BOOL
cacheHasListView(GWVolumeCache *cache, NSString *dir)
{
  DSStoreInfo *c = [cache readInfoForDirectoryPath: dir];

  return c != nil && c.hasViewStyle && c.viewStyle == DSStoreViewStyleList;
}

int
main(void)
{
  NSAutoreleasePool *arp = [NSAutoreleasePool new];
  NSString *root = makeDir([GWTestTemporaryDirectory()
                             stringByAppendingPathComponent: @"routing"]);
  GWVolumeCache *cache = [[[GWVolumeCache alloc] initWithCacheFilePath:
    [GWTestTemporaryDirectory() stringByAppendingPathComponent: @"cache.DS_Store"]]
    autorelease];

  /* --- neither the folder's store nor the parent's can be written --- */
  {
    NSString *parent = makeDir([root stringByAppendingPathComponent: @"locked"]);
    NSString *dir = makeDir([parent stringByAppendingPathComponent: @"ro"]);
    GWViewSettingsManager *sm;
    DSStoreInfo *back;

    blockStore(parent);
    blockStore(dir);
    sm = [[[GWViewSettingsManager alloc] initWithDirectoryPath: dir
                                                   volumeCache: cache] autorelease];
    PASS([sm writeSettings: listViewInfo(sm)],
         "settings of a folder whose stores are unwritable are still saved");
    PASS(cacheHasListView(cache, dir), "they went to the volume cache");
    back = [[[[GWViewSettingsManager alloc] initWithDirectoryPath: dir
                                                       volumeCache: cache] autorelease]
             readSettings];
    PASS(back.hasViewStyle && back.viewStyle == DSStoreViewStyleList,
         "a fresh manager reads them back from the cache alone");
  }

  /* --- the folder is writable, its parent is not (Finder keeps nothing
   * then [O:E14]) --- */
  {
    NSString *parent = makeDir([root stringByAppendingPathComponent: @"roparent"]);
    NSString *dir = makeDir([parent stringByAppendingPathComponent: @"w"]);
    GWViewSettingsManager *sm;

    blockStore(parent);
    sm = [[[GWViewSettingsManager alloc] initWithDirectoryPath: dir
                                                   volumeCache: cache] autorelease];
    PASS([sm writeSettings: listViewInfo(sm)], "writing succeeds");
    PASS(isStoreFile(dir), "the folder's own store was written");
    PASS(cacheHasListView(cache, dir),
         "the view records the parent could not take are in the cache");
  }

  /* --- both stores writable: a cached copy is dropped, it would go stale --- */
  {
    NSString *parent = makeDir([root stringByAppendingPathComponent: @"open"]);
    NSString *dir = makeDir([parent stringByAppendingPathComponent: @"rw"]);
    GWViewSettingsManager *sm;
    DSStoreInfo *seed = [DSStoreInfo infoForDirectoryPath: dir loadImmediately: NO];
    DSStoreInfo *left;

    [seed takeValuesFromViewerPrefs: @{ @"viewtype" : @"Icon" }];
    PASS([cache writeInfo: seed forDirectoryPath: dir], "a cached record is seeded");
    sm = [[[GWViewSettingsManager alloc] initWithDirectoryPath: dir
                                                   volumeCache: cache] autorelease];
    PASS([sm writeSettings: listViewInfo(sm)], "writing succeeds");
    PASS(isStoreFile(dir) && isStoreFile(parent),
         "the folder's and the parent's store were written");
    left = [cache readInfoForDirectoryPath: dir];
    PASS(left == nil || !left.hasViewStyle, "the cached record was removed");
  }

  /* --- network store writes blocked: only the cache is written --- */
  {
    NSString *parent = makeDir([root stringByAppendingPathComponent: @"share"]);
    NSString *dir = makeDir([parent stringByAppendingPathComponent: @"net"]);
    GWViewSettingsManager *sm;

    sm = [[[NetworkBlockedManager alloc] initWithDirectoryPath: dir
                                                   volumeCache: cache] autorelease];
    PASS([sm writeSettings: listViewInfo(sm)], "writing succeeds");
    PASS(!isStoreFile(dir) && !isStoreFile(parent),
         "no .DS_Store is written on a blocked network folder");
    PASS(cacheHasListView(cache, dir), "the settings are in the volume cache");
    /* One cache serves the whole volume: a write for one folder must not
     * drop the records of the others. */
    PASS(cacheHasListView(cache, [root stringByAppendingPathComponent: @"locked/ro"]),
         "the first folder's cached settings survive later writes for others");
  }

  /* --- DSDontWriteNetworkStores is read from the defaults --- */
  {
    NSString *key = @"com.apple.desktopservices.DSDontWriteNetworkStores";

    PASS(![GWViewSettingsManager dsDontWriteNetworkStores],
         "network stores are written by default");
    [[NSUserDefaults standardUserDefaults] registerDefaults:
      [NSDictionary dictionaryWithObject: [NSNumber numberWithBool: YES] forKey: key]];
    PASS([GWViewSettingsManager dsDontWriteNetworkStores],
         "DSDontWriteNetworkStores YES blocks them");
    [[NSUserDefaults standardUserDefaults] registerDefaults:
      [NSDictionary dictionaryWithObject: @"NO" forKey: key]];
    PASS(![GWViewSettingsManager dsDontWriteNetworkStores],
         "DSDontWriteNetworkStores NO allows them");
  }

  /* --- a volume root and the home folder keep their settings as "." --- */
  {
    PASS([DSStoreInfo parentStorePathForDirectory: @"/"] == nil,
         "/ has no parent record");
    PASS([DSStoreInfo parentStorePathForDirectory: NSHomeDirectory()] == nil,
         "the home folder has no parent record");
    PASS_EQUAL([DSStoreInfo parentStorePathForDirectory:
                  [root stringByAppendingPathComponent: @"open/rw"]],
               [root stringByAppendingPathComponent: @"open/.DS_Store"],
               "an ordinary folder's record is in its parent's store");
  }

  [arp release];
  return 0;
}
