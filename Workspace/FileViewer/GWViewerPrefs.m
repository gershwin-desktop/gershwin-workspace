/* GWViewerPrefs.m
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

#import "GWViewerPrefs.h"

NSString *
GWViewerPrefsKey(NSString *path, BOOL spatial,
                 NSNumber *rootKey, BOOL firstRootViewer)
{
  if (spatial)
    {
      if (rootKey != nil)
        return [NSString stringWithFormat: @"spatial_at_%@_%lu",
                         path, [rootKey unsignedLongValue]];
      return [NSString stringWithFormat: @"spatial_at_%@", path];
    }

  if (firstRootViewer)
    return @"root_viewer";

  if (rootKey != nil)
    return [NSString stringWithFormat: @"%lu_viewer_at_%@",
                     [rootKey unsignedLongValue], path];

  return [NSString stringWithFormat: @"viewer_at_%@", path];
}

NSString *
GWViewerLegacySharedPrefsKey(NSString *path, NSNumber *rootKey)
{
  if (rootKey != nil)
    return [NSString stringWithFormat: @"viewer_at_%@_%lu",
                     path, [rootKey unsignedLongValue]];
  return [NSString stringWithFormat: @"viewer_at_%@", path];
}
