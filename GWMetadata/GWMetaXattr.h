/* GWMetaXattr.h
 *
 * Portable wrapper for POSIX extended attributes.
 * Provides a uniform interface across Linux (sys/xattr.h),
 * FreeBSD (sys/extattr.h), and OpenBSD (ENOTSUP stubs) for storing
 * Mac OS metadata attributes
 * in the "user" namespace (user.com.apple.*).
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

#ifndef GWMETAXATTR_H
#define GWMETAXATTR_H

#include <sys/types.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/**
 * Flags for gs_setxattr.
 */
#define GS_XATTR_CREATE   1  /* Fail if the attribute already exists. */
#define GS_XATTR_REPLACE  2  /* Fail if the attribute does not exist. */

/**
 * Maximum size we accept for a single xattr value (256 MiB).
 * This is far above typical resource fork sizes but provides a safety bound.
 */
#define GS_XATTR_MAX_SIZE  (256 * 1024 * 1024)

/**
 * Set an extended attribute on a file.
 *
 * @param path  Filesystem path
 * @param name  Attribute name (e.g. "user.com.apple.FinderInfo")
 * @param value Pointer to the value data
 * @param size  Size of value in bytes
 * @param flags 0, GS_XATTR_CREATE, or GS_XATTR_REPLACE
 * @return 0 on success, -1 on error (errno is set)
 */
int gs_setxattr(const char *path, const char *name,
                const void *value, size_t size, int flags);

/**
 * Get an extended attribute from a file.
 *
 * @param path  Filesystem path
 * @param name  Attribute name
 * @param value Buffer to receive the value (may be NULL to query size)
 * @param size  Size of buffer
 * @return The number of bytes written on success, or -1 on error (errno is set).
 *         If value is NULL, returns the size needed to hold the attribute.
 */
ssize_t gs_getxattr(const char *path, const char *name,
                    void *value, size_t size);

/**
 * List extended attribute names on a file.
 *
 * The list is a sequence of null-terminated strings.
 *
 * @param path Filesystem path
 * @param list Buffer to receive the list (may be NULL to query size)
 * @param size Size of buffer
 * @return The total number of bytes in the list on success, or -1 on error.
 */
ssize_t gs_listxattr(const char *path, char *list, size_t size);

/**
 * Remove an extended attribute from a file.
 *
 * @param path Filesystem path
 * @param name Attribute name
 * @return 0 on success, -1 on error (errno is set)
 */
int gs_removexattr(const char *path, const char *name);

/**
 * Check whether extended attributes are supported on the filesystem
 * containing the given path.
 *
 * @param path A path on the filesystem to test
 * @return 1 if supported, 0 if not supported, -1 on error
 */
int gs_xattr_supported(const char *path);

/**
 * Copy the type name of the filesystem holding path into buf: the kernel's
 * own name where it has one (f_fstypename on the BSDs, the volume's file
 * system name on Windows), on Linux a name for the statfs magic number
 * ("fuseblk" for block-backed FUSE, "fuse.<subtype>" from mountinfo for
 * the rest).
 *
 * @return 0, or -1 with errno set (ENAMETOOLONG when buf is too small)
 */
int gs_fs_type_name(const char *path, char *buf, size_t size);

/**
 * The name gs_fs_type_name() gives a Linux statfs magic number; fuseType is
 * the mountinfo type for FUSE (NULL when mountinfo does not say, giving
 * "fuse").  A magic we do not list is named "0x<hex>", which no rule below
 * matches.  Separate so that tests can feed any magic.
 *
 * @return 0, or -1 with errno set (ENAMETOOLONG when buf is too small)
 */
int gs_fs_type_name_for_magic(unsigned long magic, const char *fuseType,
                              char *buf, size_t size);

/**
 * Whether the type is an SMB mount, where a Samba server may refuse "._"
 * files (vfs_fruit, fruit:veto_appledouble).
 */
int gs_fs_type_is_smb(const char *fstype);

/**
 * Whether a Mac reads Finder metadata on a filesystem of this type only
 * from "._" AppleDouble files: FAT, exFAT, SMB and NTFS.  There, metadata
 * must be written as sidecars even when the local mount would accept
 * extended attributes, because the Mac never sees those.
 *
 * @param fstype A name as gs_fs_type_name() returns it (case ignored)
 * @return 1 or 0
 */
int gs_fs_type_wants_appledouble(const char *fstype);

/**
 * Entry returned by gs_xattr_list_for_path().
 */
typedef struct {
  char   *name;   /* Attribute name (malloced)  */
  void   *value;  /* Attribute value (malloced) */
  size_t  size;   /* Size of value in bytes     */
} gs_xattr_entry_t;

/**
 * List of extended attribute entries.
 */
typedef struct {
  gs_xattr_entry_t *entries;  /* Array of entries    */
  int               count;    /* Number of entries   */
} gs_xattr_list_t;

/**
 * Read all extended attributes matching a name prefix from a file.
 * If prefix is NULL, returns all attributes.
 *
 * @param path   Filesystem path
 * @param prefix Optional name prefix filter (e.g. "user.com.apple.")
 * @return A newly allocated list (count 0 when the file has no matching
 *         attributes or the filesystem has none), or NULL on failure with
 *         errno set.  An attribute with an empty value has value NULL and
 *         size 0.  Free with gs_xattr_list_free().
 */
gs_xattr_list_t *gs_xattr_list_for_path(const char *path, const char *prefix);

/**
 * Free a list returned by gs_xattr_list_for_path().
 */
void gs_xattr_list_free(gs_xattr_list_t *list);

#ifdef __cplusplus
}
#endif

/* GNUstep's -fileSystemRepresentation returns UTF-16 on Windows, but the gs_*xattr
   functions take narrow strings, so use the UTF-8 form there. On
   the other platforms this is the plain -fileSystemRepresentation call. */
#ifdef _WIN32
#define GW_FSREP(path) [(path) UTF8String]
#else
#define GW_FSREP(path) [(path) fileSystemRepresentation]
#endif

#endif /* GWMETAXATTR_H */
