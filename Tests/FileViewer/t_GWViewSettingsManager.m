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

  [fm removeFileAtPath: dir handler: nil];
  [arp release];
  return 0;
}
