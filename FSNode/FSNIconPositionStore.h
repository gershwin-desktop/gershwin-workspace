/* FSNIconPositionStore.h
 *
 * Protocol through which FSNode persists icon positions without depending on
 * a concrete store (.DS_Store / per-volume cache / xattr).  The Workspace
 * application registers a concrete store on FSNodeRep at startup; when none
 * is set, position changes are simply not persisted.
 *
 * Keeps the generic file-representation framework decoupled from the
 * .DS_Store persistence stack, and gives all icon-position writes a single
 * home in the application.
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

#ifndef FSN_ICON_POSITION_STORE_H
#define FSN_ICON_POSITION_STORE_H

#import <Foundation/Foundation.h>

@protocol FSNIconPositionStore <NSObject>

/* Persist icon positions.  positionsByFolder maps a folder path to an
 * NSArray of per-file entries, each an NSArray of
 * @[ filename (NSString), ilocX (NSNumber), ilocY (NSNumber) ], where ilocX/Y
 * are DS_Store top-left CENTER coordinates. */
- (void)saveIconPositionsByFolder:(NSDictionary *)positionsByFolder;

/* Read stored positions for a folder (folder .DS_Store, then per-volume
 * cache).  Returns filename -> NSValue(NSPoint) with DS_Store top-left
 * CENTER (iloc) coordinates, or an empty dictionary when none are stored. */
- (NSDictionary *)storedIconPositionsForFolder:(NSString *)folder;

@end

#endif /* FSN_ICON_POSITION_STORE_H */
