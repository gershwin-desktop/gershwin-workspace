/* GWViewerPrefs.h
 *
 * Single source for the NSUserDefaults key under which a viewer persists its
 * per-folder remainder state (geometry fallback, shelf, last selection, ...).
 *
 * Browser and spatial windows for the same folder are different window kinds
 * with different state shapes, so they get distinct keys — previously both
 * wrote the same "viewer_at_<path>" key and the last closer won.
 *
 * Foundation-only, so the naming half of viewer identity is unit-testable.
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

#ifndef GW_VIEWER_PREFS_H
#define GW_VIEWER_PREFS_H

#import <Foundation/Foundation.h>

/* Key shapes:
 *   browser, first root viewer:  "root_viewer"
 *   browser, extra root viewer:  "<key>_viewer_at_<path>"
 *   browser, normal:             "viewer_at_<path>"
 *   spatial, extra root viewer:  "spatial_at_<path>_<key>"
 *   spatial, normal (any root):  "spatial_at_<path>"
 *
 * rootKey is the per-window uniquing number for additional root viewers
 * (nil otherwise).  firstRootViewer only matters for the browser kind. */
NSString *GWViewerPrefsKey(NSString *path, BOOL spatial,
                           NSNumber *rootKey, BOOL firstRootViewer);

/* The pre-split key a spatial viewer used to share with the browser
 * ("viewer_at_<path>" / "viewer_at_<path>_<key>").  Read-only fallback so
 * existing users keep their shelf/geometry on first run after the split;
 * never written to for spatial viewers anymore. */
NSString *GWViewerLegacySharedPrefsKey(NSString *path, NSNumber *rootKey);

#endif /* GW_VIEWER_PREFS_H */
