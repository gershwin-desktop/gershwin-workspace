/* GWIconPositionStore.h
 *
 * The single home for icon-position persistence in Workspace: writes the
 * folder .DS_Store Iloc (or the per-volume cache when the folder is not
 * writable) plus the per-file fdLocation xattr export.  Registered on
 * FSNodeRep as its FSNIconPositionStore so FSNode never writes these stores
 * directly, and so every position write (drag, Clean Up, single-file) goes
 * through one code path.
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

#import <Foundation/Foundation.h>
#import "FSNIconPositionStore.h"

@interface GWIconPositionStore : NSObject <FSNIconPositionStore>

+ (instancetype)sharedStore;

/* Convenience for a single file (top-left iloc CENTER coordinates). */
- (void)saveIconPosition:(NSPoint)ilocCenter forFileAtPath:(NSString *)path;

@end
