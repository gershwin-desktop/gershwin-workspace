/* t_GWViewSettingsManager.m — ObjectTesting coverage for the tiered
 * view-settings facade.
 *
 * GWViewSettingsManager is the single read/write path for folder-scoped view
 * settings (browser, spatial and the desktop all go through it).  This covers
 * the folder tier: a bare folder yields an unloaded info (all has* flags NO),
 * writeSettings creates the folder .DS_Store, and a fresh manager reads the
 * same values back.  The per-volume cache tier writes under $HOME and is
 * deliberately not exercised here.
 *
 * Runs headless; the DSStore back-end is linked as separate objects (see
 * GNUmakefile.preamble).
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

#import <Foundation/Foundation.h>
#import "Testing.h"

#include <unistd.h>

#include "../../Workspace/FileViewer/GWViewSettingsManager.m"

int
main(void)
{
  NSAutoreleasePool *arp = [NSAutoreleasePool new];
  NSFileManager *fm = [NSFileManager defaultManager];

  NSString *dir = [NSTemporaryDirectory() stringByAppendingPathComponent:
                    [NSString stringWithFormat: @"t_gwvsm_%d", (int)getpid()]];
  [fm removeFileAtPath: dir handler: nil];
  [fm createDirectoryAtPath: dir attributes: nil];

  /* --- bare folder: defaults tier, nothing set --- */
  {
    GWViewSettingsManager *sm =
      [[[GWViewSettingsManager alloc] initWithDirectoryPath: dir] autorelease];
    DSStoreInfo *info = [sm readSettings];

    PASS(info != nil, "readSettings on a bare folder returns an info");
    PASS(info.hasViewStyle == NO && info.hasIconSize == NO
         && info.hasWindowFrame == NO,
         "bare folder: no has* flag is set (pure defaults tier)");
  }

  /* --- write -> folder .DS_Store -> read back with a fresh manager --- */
  {
    GWViewSettingsManager *sm =
      [[[GWViewSettingsManager alloc] initWithDirectoryPath: dir] autorelease];
    DSStoreInfo *info = [sm readSettings];

    [info takeValuesFromViewerPrefs: @{ @"viewtype" : @"List",
                                        @"iconsize" : @64 }];
    PASS([sm writeSettings: info], "writeSettings succeeds on a writable folder");
    PASS([fm fileExistsAtPath: [dir stringByAppendingPathComponent: @".DS_Store"]],
         "writeSettings created the folder .DS_Store");

    GWViewSettingsManager *sm2 =
      [[[GWViewSettingsManager alloc] initWithDirectoryPath: dir] autorelease];
    DSStoreInfo *back = [sm2 readSettings];

    PASS(back != nil && back.loaded, "a fresh manager reads the folder tier");
    PASS(back.hasViewStyle && back.viewStyle == DSStoreViewStyleList,
         "view style round-trips through the facade");
    PASS(back.hasIconSize && back.iconSize == 64,
         "icon size round-trips through the facade");
  }

  /* --- per-volume cache: root "/" scoped icon positions round-trip with
   * bare names (regression: the key+"/" prefix was "//" for "/", so scoped
   * "/usr" entries were never stripped back to "usr") --- */
  {
    NSString *cachePath = [NSTemporaryDirectory() stringByAppendingPathComponent:
                            [NSString stringWithFormat: @"t_gwvsm_root_%d.DS_Store",
                                        (int)getpid()]];
    [fm removeFileAtPath: cachePath handler: nil];
    GWVolumeCache *vc =
      [[[GWVolumeCache alloc] initWithCacheFilePath: cachePath] autorelease];

    NSArray *positions = @[
      @{ @"name" : @"usr", @"x" : @100, @"y" : @50 },
      @{ @"name" : @"etc", @"x" : @300, @"y" : @120 },
    ];
    PASS([vc writeIconPositions: positions forDirectoryPath: @"/"],
         "volume cache writes scoped icon positions for /");

    DSStoreInfo *back = [vc readInfoForDirectoryPath: @"/"];
    PASS(back != nil && back.loaded, "volume cache reads back the / record");
    BOOL bareNames = YES;
    if (back) {
      for (NSString *n in [back filenamesWithPositions]) {
        if ([n hasPrefix: @"/"])
          bareNames = NO;
      }
    }
    PASS(bareNames, "root / icon positions come back with bare names");
    DSStoreIconInfo *usr = [back iconInfoForFilename: @"usr"];
    PASS(usr != nil && [usr hasPosition]
         && NSEqualPoints([usr position], NSMakePoint(100, 50)),
         "root / 'usr' position round-trips through the volume cache");

    PASS([vc removeRecordForDirectoryPath: @"/"],
         "removeRecordForDirectoryPath: succeeds for /");
    DSStoreInfo *gone = [vc readInfoForDirectoryPath: @"/"];
    /* Bare-name file entries are volume-global (the Mac convention), so they
     * survive; what must be cleared is the directory's own record.  With no
     * dir-level entry and only bare Iloc, hasViewStyle/hasWindowFrame are NO. */
    PASS(gone == nil || (![gone hasViewStyle] && ![gone hasWindowFrame]),
         "removeRecordForDirectoryPath: clears the / directory record");

    [fm removeFileAtPath: cachePath handler: nil];
  }

  /* --- per-volume cache: a partial write must merge, not wipe ---
   * The viewer persists geometry via writeInfo: (full info), but Clean Up /
   * label edits pass a positions-only or labels-only DSStoreInfo.  Without
   * merging, that partial write would drop the cached window geometry. */
  {
    NSString *cachePath = [NSTemporaryDirectory() stringByAppendingPathComponent:
                            [NSString stringWithFormat: @"t_gwvsm_merge_%d.DS_Store",
                                        (int)getpid()]];
    [fm removeFileAtPath: cachePath handler: nil];
    GWVolumeCache *vc =
      [[[GWVolumeCache alloc] initWithCacheFilePath: cachePath] autorelease];

    /* Full write: geometry + view style + icon size. */
    DSStoreInfo *full = [DSStoreInfo infoForDirectoryPath: @"/" loadImmediately: NO];
    [full takeValuesFromViewerPrefs: @{ @"viewtype" : @"Icon",
                                        @"geometry" : NSStringFromRect(NSMakeRect(100, 150, 600, 400)),
                                        @"iconsize" : @48 }];
    PASS([vc writeInfo: full forDirectoryPath: @"/"],
         "volume cache accepts a full settings write for /");

    /* Partial write: positions only (as Clean Up does). */
    DSStoreInfo *posOnly = [DSStoreInfo infoForDirectoryPath: @"/" loadImmediately: NO];
    DSStoreIconInfo *ii = [DSStoreIconInfo infoForFilename: @"usr"];
    ii.position = NSMakePoint(100, 50);
    ii.hasPosition = YES;
    [posOnly setIconInfo: ii forFilename: @"usr"];
    PASS([vc writeInfo: posOnly forDirectoryPath: @"/"],
         "volume cache accepts a positions-only write for /");

    DSStoreInfo *merged = [vc readInfoForDirectoryPath: @"/"];
    PASS(merged != nil && [merged hasWindowFrame],
         "a positions-only write preserves the cached window geometry");
    PASS(merged != nil && [merged hasViewStyle]
         && [merged viewStyle] == DSStoreViewStyleIcon,
         "a positions-only write preserves the cached view style");
    PASS(merged != nil && [merged hasIconSize] && [merged iconSize] == 48,
         "a positions-only write preserves the cached icon size");
    DSStoreIconInfo *mi = [merged iconInfoForFilename: @"usr"];
    PASS(mi != nil && [mi hasPosition]
         && NSEqualPoints([mi position], NSMakePoint(100, 50)),
         "a positions-only write keeps its own position");

    [fm removeFileAtPath: cachePath handler: nil];
  }

  /* --- bare-name entries are the macOS convention (regression) ---
   * The Finder writes per-file Iloc entries keyed by bare filename in the
   * per-volume cache (verified against real Finder caches).  The read side
   * must prefer the bare-name form; a legacy scoped "<key>/<filename>" entry
   * is only a fallback when no bare entry exists. */
  {
    NSString *cachePath = [NSTemporaryDirectory() stringByAppendingPathComponent:
                            [NSString stringWithFormat: @"t_gwvsm_scoped_%d.DS_Store",
                                        (int)getpid()]];
    [fm removeFileAtPath: cachePath handler: nil];
    GWVolumeCache *vc =
      [[[GWVolumeCache alloc] initWithCacheFilePath: cachePath] autorelease];

    /* A write produces a bare-name entry (the Mac convention). */
    DSStoreInfo *w = [DSStoreInfo infoForDirectoryPath: @"/" loadImmediately: NO];
    DSStoreIconInfo *wi = [DSStoreIconInfo infoForFilename: @"usr"];
    wi.position = NSMakePoint(300, 150);
    wi.hasPosition = YES;
    [w setIconInfo: wi forFilename: @"usr"];
    [vc writeInfo: w forDirectoryPath: @"/"];
    DSStoreInfo *back = [vc readInfoForDirectoryPath: @"/"];
    PASS([[back iconInfoForFilename: @"usr"] hasPosition]
         && NSEqualPoints([[back iconInfoForFilename: @"usr"] position],
                          NSMakePoint(300, 150)),
         "a bare-name write round-trips through the cache (Mac convention)");

    /* Simulate an older scoped cache: write "<key>/<filename>" directly. */
    {
      DSStore *store = [DSStore createStoreAtPath: cachePath withEntries: nil];
      [store load];
      DSStoreEntry *e = [DSStoreEntry iconLocationEntryForFile: @"/usr" x: 999 y: 888];
      [store setEntry: e];
      [store save];
    }
    /* A bare entry still wins over the stale scoped one. */
    DSStoreInfo *mixed = [vc readInfoForDirectoryPath: @"/"];
    PASS([[mixed iconInfoForFilename: @"usr"] hasPosition]
         && NSEqualPoints([[mixed iconInfoForFilename: @"usr"] position],
                          NSMakePoint(300, 150)),
         "bare-name entry takes precedence over a stale scoped entry");

    /* With only a scoped entry present, it is used as a fallback. */
    [fm removeFileAtPath: cachePath handler: nil];
    {
      DSStore *store = [DSStore createStoreAtPath: cachePath withEntries: nil];
      [store load];
      DSStoreEntry *e = [DSStoreEntry iconLocationEntryForFile: @"/etc" x: 123 y: 456];
      [store setEntry: e];
      [store save];
    }
    DSStoreInfo *fallback = [vc readInfoForDirectoryPath: @"/"];
    DSStoreIconInfo *ei = [fallback iconInfoForFilename: @"etc"];
    PASS(ei != nil && [ei hasPosition]
         && NSEqualPoints([ei position], NSMakePoint(123, 456)),
         "a legacy scoped entry is used as a fallback when no bare entry exists");

    [fm removeFileAtPath: cachePath handler: nil];
  }

  /* --- cooperative editor: the volume-cache write must not discard unknown
   * record types for the directory key (forward compatibility) --- */
  {
    NSString *cachePath = [NSTemporaryDirectory() stringByAppendingPathComponent:
                            [NSString stringWithFormat: @"t_gwvsm_preserve_%d.DS_Store",
                                        (int)getpid()]];
    [fm removeFileAtPath: cachePath handler: nil];

    /* Seed an unknown 4CC record for the "/" key. */
    NSData *unk = [NSData dataWithBytes: "\xCA\xFE\xBA\xBE" length: 4];
    {
      DSStore *store = [DSStore createStoreAtPath: cachePath withEntries: nil];
      [store load];
      [store setEntry: [[[DSStoreEntry alloc] initWithFilename: @"/"
                                                          code: @"zzzz"
                                                          type: @"blob"
                                                         value: unk] autorelease]];
      [store save];
    }

    /* A normal Workspace write (icon position for /usr) must preserve it. */
    GWVolumeCache *vc =
      [[[GWVolumeCache alloc] initWithCacheFilePath: cachePath] autorelease];
    DSStoreInfo *w = [DSStoreInfo infoForDirectoryPath: @"/" loadImmediately: NO];
    DSStoreIconInfo *wi = [DSStoreIconInfo infoForFilename: @"usr"];
    wi.position = NSMakePoint(300, 150);
    wi.hasPosition = YES;
    [w setIconInfo: wi forFilename: @"usr"];
    PASS([vc writeInfo: w forDirectoryPath: @"/"],
         "volume cache: a Workspace write succeeds");

    DSStore *chk = [DSStore storeWithPath: cachePath];
    [chk load];
    DSStoreEntry *unkE = [chk entryForFilename: @"/" code: @"zzzz"];
    PASS(unkE != nil && [[unkE value] isEqual: unk],
         "volume cache: unknown record type under the key survives the write");

    [fm removeFileAtPath: cachePath handler: nil];
  }

  /* --- cooperative editor: the volume-cache write must not discard unknown
   * record types for the directory key (forward compatibility) --- */
  {
    NSString *cachePath = [NSTemporaryDirectory() stringByAppendingPathComponent:
                            [NSString stringWithFormat: @"t_gwvsm_preserve_%d.DS_Store",
                                        (int)getpid()]];
    [fm removeFileAtPath: cachePath handler: nil];

    /* Seed an unknown 4CC record for the "/" key. */
    NSData *unk = [NSData dataWithBytes: "\xCA\xFE\xBA\xBE" length: 4];
    {
      DSStore *store = [DSStore createStoreAtPath: cachePath withEntries: nil];
      [store load];
      [store setEntry: [[[DSStoreEntry alloc] initWithFilename: @"/"
                                                          code: @"zzzz"
                                                          type: @"blob"
                                                         value: unk] autorelease]];
      [store save];
    }

    /* A normal Workspace write (icon position for /usr) must preserve it. */
    GWVolumeCache *vc =
      [[[GWVolumeCache alloc] initWithCacheFilePath: cachePath] autorelease];
    DSStoreInfo *w = [DSStoreInfo infoForDirectoryPath: @"/" loadImmediately: NO];
    DSStoreIconInfo *wi = [DSStoreIconInfo infoForFilename: @"usr"];
    wi.position = NSMakePoint(300, 150);
    wi.hasPosition = YES;
    [w setIconInfo: wi forFilename: @"usr"];
    PASS([vc writeInfo: w forDirectoryPath: @"/"],
         "volume cache: a Workspace write succeeds");

    DSStore *chk = [DSStore storeWithPath: cachePath];
    [chk load];
    DSStoreEntry *unkE = [chk entryForFilename: @"/" code: @"zzzz"];
    PASS(unkE != nil && [[unkE value] isEqual: unk],
         "volume cache: unknown record type under the key survives the write");

    [fm removeFileAtPath: cachePath handler: nil];
  }

  /* --- concurrent writers: a foreign change to a field Workspace does not
   * touch survives a Workspace write through the facade (merge strategy) --- */
  {
    /* Simulate: Finder writes a window-geometry record + an unknown record
     * into the folder .DS_Store; Workspace then writes only a new icon
     * position.  Both Finder's records must survive. */
    [fm createFileAtPath: [dir stringByAppendingPathComponent: @"a.txt"]
                contents: [NSData data] attributes: nil];
    [fm removeFileAtPath: [dir stringByAppendingPathComponent: @".DS_Store"] handler: nil];
    NSData *unk = [NSData dataWithBytes: "\x01\x02\x03\x04\x05" length: 5];
    {
      DSStore *store = [DSStore createStoreAtPath:
                         [dir stringByAppendingPathComponent: @".DS_Store"]
                                     withEntries: nil];
      [store load];
      [store setEntry: [[[DSStoreEntry alloc] initWithFilename: @"."
                                                          code: @"zzzz"
                                                          type: @"blob"
                                                         value: unk] autorelease]];
      [store setEntry: [DSStoreEntry viewStyleEntryForFile: @"." style: @"clmv"]];
      [store save];
    }

    /* Workspace writes an icon position for a.txt via the facade. */
    GWViewSettingsManager *sm =
      [[[GWViewSettingsManager alloc] initWithDirectoryPath: dir] autorelease];
    DSStoreInfo *info = [sm readSettings];
    DSStoreIconInfo *ii = [DSStoreIconInfo infoForFilename: @"a.txt"];
    ii.position = NSMakePoint(100, 50);
    ii.hasPosition = YES;
    [info setIconInfo: ii forFilename: @"a.txt"];
    PASS([sm writeSettings: info],
         "concurrent: Workspace write through the facade succeeds");

    /* Both Finder's records + Workspace's new position must be present. */
    DSStore *chk = [DSStore storeWithPath:
                     [dir stringByAppendingPathComponent: @".DS_Store"]];
    [chk load];
    DSStoreEntry *unkE = [chk entryForFilename: @"." code: @"zzzz"];
    PASS(unkE != nil && [[unkE value] isEqual: unk],
         "concurrent: Finder's unknown record survives the facade write");
    DSStoreEntry *vstl = [chk entryForFilename: @"." code: @"vstl"];
    PASS(vstl != nil && [[vstl value] isEqualToString: @"clmv"],
         "concurrent: Finder's view style survives the facade write");
    DSStoreEntry *iloc = [chk entryForFilename: @"a.txt" code: @"Iloc"];
    PASS(iloc != nil && (int)[iloc iconLocation].x == 100,
         "concurrent: Workspace's new icon position is present");
  }

  [fm removeFileAtPath: dir handler: nil];
  [arp release];
  return 0;
}
