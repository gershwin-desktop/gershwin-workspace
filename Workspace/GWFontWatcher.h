/* GWFontWatcher.h

   Copyright (C) 2026 Free Software Foundation, Inc.

   Author: Gershwin Developers
   Date:   September 2026

   This file is part of Gershwin Workspace.

   This library is free software; you can redistribute it and/or
   modify it under the terms of the GNU Lesser General Public
   License as published by the Free Software Foundation; either
   version 2.1 of the License, or (at your option) any later version.

   This library is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
   Lesser General Public License for more details.

   You should have received a copy of the GNU Lesser General Public
   License along with this library; if not, write to the Free
   Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
   Boston, MA 02110 USA.
*/

#import <Foundation/Foundation.h>

@class Workspace;

/**
 * Watches the configured font directories for file system changes
 * (fonts added or removed) and triggers a font cache rebuild so
 * already-running GNUstep applications pick up new fonts without
 * requiring a restart.
 *
 * The flow is:
 *   1. fswatcher notifies Workspace of a change in a watched path.
 *   2. Workspace's -watchedPathDidChange: calls -fontDirectoryDidChange:
 *      if the path is inside a known font directory.
 *   3. The watcher debounces rapid changes, runs `fc-cache -f`, then
 *      posts GSFontManagerAvailableFontsDidChangeNotification via
 *      NSDistributedNotificationCenter so every GNUstep app refreshes
 *      its font list.
 */
@interface GWFontWatcher : NSObject
{
  Workspace   *_workspace;
  NSSet       *_fontDirectoryPaths;
  NSTimer     *_debounceTimer;
  BOOL         _cacheUpdatePending;
}

/**
 * Designated initializer.  Pass the Workspace instance so we can
 * reach the fswatcher proxy if needed.
 */
- (instancetype)initWithWorkspace:(Workspace *)workspace;

/**
 * Returns YES if path is inside one of the font directories.
 */
- (BOOL)isFontDirectoryPath:(NSString *)path;

/**
 * Called by Workspace's -watchedPathDidChange: when a file system
 * event occurs in a watched path.  The method checks whether the
 * path is inside a font directory and, if so, schedules a debounced
 * font cache update.
 */
- (void)fontDirectoryDidChange:(NSString *)path;

/**
 * Returns the set of font directory paths being watched.
 */
- (NSArray *)fontDirectoryPaths;

/**
 * Returns YES if a font cache update is currently pending
 * (debounce timer active).
 */
- (BOOL)isCacheUpdatePending;

/**
 * Run fc-cache and post the notification immediately.
 * Exposed for testing and for forced refreshes.
 */
- (void)performFontCacheUpdate;

@end

/**
 * Posted by GWFontWatcher after the font cache has been rebuilt.
 * Equivalent to GSFontManagerAvailableFontsDidChangeNotification
 * but specific to the Workspace process for internal observation.
 */
extern NSString * const GWFontCacheDidChangeNotification;
