/* FSNDirEntry.h - A single entry of a directory listing snapshot.
 *
 * Directory snapshots are produced by FSNodeRep from one readdir(3) pass.
 * The entry kind comes from the dirent d_type field, so directory-ness of
 * every entry is known without a per-file stat(); viewers use this to lay
 * out lazy-loaded cells cheaply and defer the full FSNode attribute load.
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

#ifndef _FSNDIRENTRY_H_
#define _FSNDIRENTRY_H_

#import <Foundation/Foundation.h>

typedef enum
{
  FSNDirEntryKindUnknown = 0,
  FSNDirEntryKindDirectory,
  FSNDirEntryKindPlain,
  FSNDirEntryKindLink
} FSNDirEntryKind;

@interface FSNDirEntry : NSObject
{
@private
  NSString	*_name;
  FSNDirEntryKind _kind;
}

- (instancetype)initWithName:(NSString *)name kind:(FSNDirEntryKind)kind;

- (NSString *)name;
- (FSNDirEntryKind)kind;

/* YES when the readdir pass could not tell the kind (d_type DT_UNKNOWN). */
- (BOOL)hasUnknownKind;

/* Orders entries by name (used to sort a snapshot). */
- (NSComparisonResult)compare:(FSNDirEntry *)other;

@end

#endif /* _FSNDIRENTRY_H_ */
