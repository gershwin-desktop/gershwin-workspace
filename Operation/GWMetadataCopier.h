/* GWMetadataCopier.h
 *
 * Carries the extended attributes and AppleDouble sidecars of a file or
 * folder tree to its copy.  NSFileManager copies only the data fork and the
 * POSIX attributes, so everything a Mac keeps beside the data (quarantine
 * flag, resource fork, Finder info, tags, attributes of other programs)
 * would be lost by a copy, a duplicate or a move across filesystems.
 *
 * Where the destination has extended attributes, every "user." attribute
 * is copied under its own name.  Where it has none (FAT, exFAT, OpenBSD),
 * all of them go into the "._" AppleDouble sidecar, laid out the way Mac OS X
 * lays it out.  A sidecar on the source is carried to the destination as it
 * is.
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

#import <Foundation/Foundation.h>

@interface GWMetadataCopier : NSObject
{
  int (^_xattrSupportProbe)(NSString *);
  int (^_xattrSetter)(NSString *, NSString *, NSData *);
}

/**
 * Decides whether the filesystem holding a path stores extended attributes.
 * Returns 1 for yes, 0 for no, -1 when that cannot be told (the copy then
 * fails rather than guessing).  The default asks the filesystem
 * (gs_xattr_supported); tests substitute a block to exercise the sidecar
 * path on a filesystem that has xattrs.
 */
@property (nonatomic, copy) int (^xattrSupportProbe)(NSString *path);

/**
 * Stores one attribute (full "user." name) and returns 0 or an errno.  When
 * an attribute does not fit (E2BIG, ENOSPC) all metadata of the item goes
 * into the sidecar instead and the attributes already written are removed.
 * Tests substitute a block to provoke that.
 */
@property (nonatomic, copy) int (^xattrSetter)(NSString *path, NSString *name, NSData *value);

/**
 * Copy the metadata of the item at srcPath onto the existing item at
 * dstPath, including srcPath's sidecar.  Symbolic links and special files
 * carry no metadata and are skipped.  Returns NO with an error naming the
 * path and attribute that could not be carried.
 */
- (BOOL)copyMetadataFromPath:(NSString *)srcPath
                      toPath:(NSString *)dstPath
                       error:(NSError **)error;

/**
 * Same for a whole tree: the item itself and everything below it.
 * Sidecar files inside the tree were already copied as ordinary files.
 */
- (BOOL)copyMetadataOfTreeAtPath:(NSString *)srcPath
                          toPath:(NSString *)dstPath
                           error:(NSError **)error;

/**
 * Copy an item and its metadata (see above), sidecar included.  Returns NO
 * when the copy itself failed; the handler has been told.  Returns YES when
 * the copy was made; then *metadataError is set if the metadata could not be
 * carried over completely, so the caller can report it.
 */
- (BOOL)copyItemAtPath:(NSString *)srcPath
                toPath:(NSString *)dstPath
               handler:(id)handler
         metadataError:(NSError **)metadataError;

/**
 * Move an item and its sidecar.  Within one filesystem this is a rename and
 * everything travels with the item.  Across filesystems the data is copied
 * with its metadata and the source removed only once all of it arrived; if
 * the metadata did not, the source stays, NO is returned and *metadataError
 * says why.
 */
- (BOOL)moveItemAtPath:(NSString *)srcPath
                toPath:(NSString *)dstPath
               handler:(id)handler
         metadataError:(NSError **)metadataError;

/**
 * Whether a move from srcPath to a new item dstPath is a rename.
 * Overridable so that tests can force the copy-and-remove path on a
 * machine with one filesystem.
 */
- (BOOL)isRenameFromPath:(NSString *)srcPath toPath:(NSString *)dstPath;

/**
 * The sidecar path of an item: /a/b -> /a/._b.
 */
+ (NSString *)sidecarPathForPath:(NSString *)path;

@end
