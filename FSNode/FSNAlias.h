/* FSNAlias.h - Alias records for Finder interoperability (issue #71:
 * Support Aliases for interoperability).
 *
 * An Alias is a small binary record ("alis") holding enough metadata about
 * a target file - POSIX path, volume, name, and a stable identifier - that
 * the target can still be found after it has been moved or renamed.
 * Unlike a symlink it survives moves of source or target.
 *
 * Two on-disk forms are supported:
 *   - the classic big-endian "alis" record (versions 2 and 3) with tagged
 *     TLV data, documented in akrieger/mac_alias docs/alias_fmt.rst;
 *   - the 10.6 "bookmark" stored in the data fork, a little-endian record
 *     resolved by the Finder without needing a CNID or volume UUID.
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

#ifndef _FSNALIAS_H_
#define _FSNALIAS_H_

#import <Foundation/Foundation.h>

/* File-operation name for "create Alias records" drops and menu actions
 * (handled by the Operation framework like the workspace operations). */
extern NSString * const FSNWorkspaceCreateAliasOperation;

@interface FSNAlias : NSObject
{
@private
  int		_version;
  BOOL		_isDirectory;
  NSString	*_volumeName;
  NSString	*_targetName;
  NSString	*_posixPath;
  NSString	*_volumeMountPoint;
  uint32_t	_targetCNID;
  NSString	*_parentName;
  uint32_t	_parentCNID;
}

/* YES if the data starts with a valid alias record header (classic "alis"
 * or a 10.6 "book" bookmark). */
+ (BOOL)isAliasData:(NSData *)data;

/* Build an alias record describing an existing filesystem path (the target
 * must exist locally so its kind and inode can be captured). */
+ (FSNAlias *)aliasWithPath:(NSString *)path;

/* Build an alias record purely from a target path string and the name of the
 * volume the target lives on.  The target need not exist locally - this is the
 * constructor for producing Finder-resolvable aliases of paths that only exist
 * on a remote Finder system. */
+ (FSNAlias *)aliasWithTargetPath:(NSString *)targetPath
			volumeName:(NSString *)volumeName;

/* Write a classic "alis" alias file for an existing path into a directory,
 * named "<name> alias" ("... alias 2", "... alias 3", ... on collision).
 * Returns the created file's path, or nil if the target does not exist
 * or the record could not be written.  The alias is written with an empty
 * data fork and a "._" AppleDouble sidecar carrying the resource fork and
 * Finder Info, so it resolves through Finder interoperability. */
+ (NSString *)writeAliasFileForPath:(NSString *)path
			inDirectory:(NSString *)directory;

/* Like +writeAliasFileForPath:inDirectory: but for a foreign target path that
 * only exists on a remote Finder system, using the given volume name. */
+ (NSString *)writeAliasFileForTargetPath:(NSString *)targetPath
				inDirectory:(NSString *)directory
				  volumeName:(NSString *)volumeName;

/* Build the 10.6 bookmark data for a target path.  The startup volume is
 * identified implicitly (root volume, mount point "/"); no CNID or volume
 * UUID is required, so GNUstep can produce this with no Finder-specific
 * state.  volumeName/volumeUUID, when known, are recorded but may be empty. */
+ (NSData *)aliasBookmarkForTargetPath:(NSString *)targetPath
			    volumeName:(NSString *)volumeName
			    volumeUUID:(NSString *)volumeUUID;

/* Convenience form of the above with no volume name or UUID. */
+ (NSData *)aliasBookmarkForTargetPath:(NSString *)targetPath;

/* Write a 10.6 bookmark alias file for a target path.  The bookmark lives in
 * the data fork; a "._" AppleDouble sidecar carries the Finder Info (type
 * "alis") so the file is recognised as an alias once it reaches a Finder
 * system.  Returns the created file's path, or nil on failure. */
+ (NSString *)writeAliasBookmarkForTargetPath:(NSString *)targetPath
				  inDirectory:(NSString *)directory
				    volumeName:(NSString *)volumeName;

/* Convenience form of the above with no volume name. */
+ (NSString *)writeAliasBookmarkForTargetPath:(NSString *)targetPath
				  inDirectory:(NSString *)directory;

/* Parse an alias record; returns nil for malformed data. */
- (instancetype)initWithData:(NSData *)data;

/* Serialize back to the wire format (version 2 record). */
- (NSData *)aliasData;

/* Try to locate the target.  Prefers the recorded POSIX path (guarded by
 * the stored inode when present), then searches below the deepest existing
 * ancestor directory for the recorded inode. */
- (NSString *)resolvePath;

- (int)version;
- (BOOL)isDirectory;
- (NSString *)volumeName;
- (NSString *)targetName;
- (NSString *)posixPath;
- (NSString *)volumeMountPoint;
- (uint32_t)targetCNID;

@end

#endif /* _FSNALIAS_H_ */
