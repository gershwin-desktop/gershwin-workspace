/* GWMountWatchState.h
 *
 * The pure decision MPointWatcher's mount-change watcher needs: given the
 * desktop volume list from the previous snapshot and the one just read
 * from the mount table, which paths were added and which were removed.
 * Kept apart from GWDesktopManager.m so it can be exercised headless,
 * without an NSThread, a live mount table, or a running desktop.
 *
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

#import <Foundation/Foundation.h>

/**
 * Compare two snapshots of the desktop volume-path list and report what
 * changed. @p added and @p removed always come back as (possibly empty)
 * arrays, never nil; duplicate entries and the order of either input do
 * not affect the result.
 */
void GWMountWatchStateDiff(NSArray *oldPaths, NSArray *newPaths,
                           NSArray **added, NSArray **removed);
