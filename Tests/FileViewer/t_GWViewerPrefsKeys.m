/* t_GWViewerPrefsKeys.m — ObjectTesting coverage for the viewer prefs-key
 * derivation.
 *
 * GWViewerPrefsKey is the single source for the NSUserDefaults key a viewer
 * persists its per-folder remainder under.  Browser and spatial windows get
 * distinct keys (they store different state shapes); previously both used
 * "viewer_at_<path>" and the last closer clobbered the other.  Pinning the
 * shapes here makes the naming half of viewer identity testable.
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

#import <Foundation/Foundation.h>
#import "Testing.h"

#include "../../Workspace/FileViewer/GWViewerPrefs.m"

int
main(void)
{
  NSAutoreleasePool *arp = [NSAutoreleasePool new];
  NSString *path = @"/home/user/Documents";
  NSNumber *rk = [NSNumber numberWithUnsignedLong: 42];

  /* --- browser shapes --- */
  PASS_EQUAL(GWViewerPrefsKey(@"/", NO, nil, YES), @"root_viewer",
             "browser first root viewer -> root_viewer");
  PASS_EQUAL(GWViewerPrefsKey(@"/", NO, rk, NO), @"42_viewer_at_/",
             "browser extra root viewer -> <key>_viewer_at_<path>");
  PASS_EQUAL(GWViewerPrefsKey(path, NO, nil, NO),
             @"viewer_at_/home/user/Documents",
             "browser normal -> viewer_at_<path>");

  /* --- spatial shapes (kind-separated) --- */
  PASS_EQUAL(GWViewerPrefsKey(path, YES, nil, NO),
             @"spatial_at_/home/user/Documents",
             "spatial normal -> spatial_at_<path>");
  PASS_EQUAL(GWViewerPrefsKey(@"/", YES, rk, NO), @"spatial_at_/_42",
             "spatial extra root viewer -> spatial_at_<path>_<key>");
  PASS(NO == [GWViewerPrefsKey(path, YES, nil, NO)
               isEqualToString: GWViewerPrefsKey(path, NO, nil, NO)],
       "browser and spatial keys for the same path differ (no shared-key fight)");

  /* firstRootViewer only matters for the browser kind */
  PASS_EQUAL(GWViewerPrefsKey(@"/", YES, nil, YES), @"spatial_at_/",
             "spatial ignores firstRootViewer (no special root name)");

  /* --- legacy shared key (spatial read fallback) --- */
  PASS_EQUAL(GWViewerLegacySharedPrefsKey(path, nil),
             @"viewer_at_/home/user/Documents",
             "legacy shared key matches the browser normal shape");
  PASS_EQUAL(GWViewerLegacySharedPrefsKey(@"/", rk), @"viewer_at_/_42",
             "legacy shared key, root variant");
  PASS_EQUAL(GWViewerLegacySharedPrefsKey(path, nil),
             GWViewerPrefsKey(path, NO, nil, NO),
             "legacy spatial key == browser key (documents the old collision)");

  [arp release];
  return 0;
}
