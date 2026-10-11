/* GWMetaXattr.c
 *
 * Portable wrapper for POSIX extended attributes.
 *
 * Linux:   uses <sys/xattr.h> (getxattr, setxattr, listxattr, removexattr)
 * FreeBSD:       uses <sys/extattr.h> (extattr_get_file, extattr_set_file,
 *                extattr_list_file, extattr_delete_file) with EXTATTR_NAMESPACE_USER.
 * OpenBSD:       does not support extended attributes — all operations
 *                return ENOTSUP.  Metadata falls back to .DS_Store and
 *                AppleDouble sidecar files.
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

#ifdef HAVE_CONFIG_H
# include <config.h>
#endif

#include "GWMetaXattr.h"

#include <string.h>
#include <stdlib.h>
#include <errno.h>

/* ===================================================================
 * Platform-specific includes and helpers
 * =================================================================== */

#if defined(__linux__)
# include <sys/xattr.h>

/*
 * On Linux the full attribute name includes the "user." namespace
 * prefix, so callers pass e.g. "user.com.apple.FinderInfo".
 * The syscalls are: getxattr, setxattr, listxattr, removexattr.
 */

static int
_gs_set(const char *path, const char *name, const void *value,
        size_t size, int flags)
{
  return setxattr(path, name, value, size, flags);
}

static ssize_t
_gs_get(const char *path, const char *name, void *value, size_t size)
{
  return getxattr(path, name, value, size);
}

static ssize_t
_gs_list(const char *path, char *list, size_t size)
{
  return listxattr(path, list, size);
}

static int
_gs_remove(const char *path, const char *name)
{
  return removexattr(path, name);
}

#elif defined(__FreeBSD__)
# include <sys/extattr.h>

/*
 * On FreeBSD the namespace is separate from the attribute name.
 * We always use EXTATTR_NAMESPACE_USER.
 * The syscalls are: extattr_get_file, extattr_set_file,
 *                   extattr_list_file, extattr_delete_file.
 *
 * FreeBSD listxattr returns entries WITHOUT the "user." prefix on the name;
 * each entry is a single byte for length followed by that many bytes of name.
 * We convert to the Linux convention (null-separated full names including
 * "user." prefix) for consistency.
 */

static int
_gs_set(const char *path, const char *name, const void *value,
        size_t size, int flags)
{
  /*
   * FreeBSD extattr_set_file does not support CREATE/REPLACE natively.
   * We approximate: if GS_XATTR_CREATE is set, check existence first.
   * This is racy but sufficient for our use.
   */
  if (flags & GS_XATTR_CREATE)
    {
      ssize_t ret = extattr_get_file(path, EXTATTR_NAMESPACE_USER,
                                     name, NULL, 0);
      if (ret >= 0)
        {
          errno = EEXIST;
          return -1;
        }
      if (errno != ENOATTR)
        return -1;
    }
  else if (flags & GS_XATTR_REPLACE)
    {
      ssize_t ret = extattr_get_file(path, EXTATTR_NAMESPACE_USER,
                                     name, NULL, 0);
      if (ret < 0 && errno == ENOATTR)
        {
          errno = ENOATTR;
          return -1;
        }
    }

  ssize_t written = extattr_set_file(path, EXTATTR_NAMESPACE_USER,
                                     name, value, size);
  /* FreeBSD refuses a value larger than the file system keeps for one
   * attribute (64 KiB, e.g. a Finder resource fork) with EINVAL, where Linux
   * says E2BIG; callers fall back to the AppleDouble sidecar on E2BIG. */
  if (written < 0 && errno == EINVAL && size > 0)
    errno = E2BIG;
  return (written == (ssize_t)size) ? 0 : -1;
}

static ssize_t
_gs_get(const char *path, const char *name, void *value, size_t size)
{
  return extattr_get_file(path, EXTATTR_NAMESPACE_USER, name, value, size);
}

static ssize_t
_gs_list(const char *path, char *list, size_t size)
{
  /*
   * FreeBSD extattr_list_file returns entries in a packed format:
   *   [1-byte name-length][name bytes...]
   * repeated for each attribute. We convert to the Linux convention:
   *   "user.<name>\0user.<name2>\0..."
   */
  ssize_t raw_size = extattr_list_file(path, EXTATTR_NAMESPACE_USER,
                                       NULL, 0);
  if (raw_size <= 0)
    return raw_size;

  char *raw = malloc(raw_size);
  if (!raw)
    return -1;

  raw_size = extattr_list_file(path, EXTATTR_NAMESPACE_USER, raw, raw_size);
  if (raw_size <= 0)
    {
      free(raw);
      return raw_size;
    }

  /* Compute converted size */
  size_t conv_size = 0;
  size_t offset = 0;
  while (offset < (size_t)raw_size)
    {
      unsigned char nlen = (unsigned char)raw[offset];
      offset++;
      if (offset + nlen <= (size_t)raw_size)
        {
          conv_size += 5 + nlen + 1; /* "user." + name + NUL */
          offset += nlen;
        }
      else
        break;
    }

  if (size == 0 || list == NULL)
    {
      free(raw);
      return conv_size;
    }

  if (conv_size > size)
    {
      free(raw);
      errno = ERANGE;
      return -1;
    }

  offset = 0;
  size_t out_offset = 0;
  while (offset < (size_t)raw_size)
    {
      unsigned char nlen = (unsigned char)raw[offset];
      offset++;
      if (offset + nlen > (size_t)raw_size)
        break;

      memcpy(list + out_offset, "user.", 5);
      out_offset += 5;
      memcpy(list + out_offset, raw + offset, nlen);
      out_offset += nlen;
      list[out_offset] = '\0';
      out_offset++;

      offset += nlen;
    }

  free(raw);
  return out_offset;
}

static int
_gs_remove(const char *path, const char *name)
{
  return extattr_delete_file(path, EXTATTR_NAMESPACE_USER, name);
}

/*
 * On FreeBSD the attribute name includes the "user." prefix when passed
 * to our public API (for source compatibility with Linux code). Strip it
 * before calling the FreeBSD syscalls, which use bare names.
 */
#define STRIP_USER_PREFIX(n) \
  ((strncmp((n), "user.", 5) == 0) ? (n) + 5 : (n))

#elif defined(__OpenBSD__) || defined(_WIN32)
/*
 * OpenBSD does not support extended attributes, and on Windows (MinGW)
 * no POSIX xattr API is available.
 * All operations return ENOTSUP (operation not supported).
 * Metadata is handled via .DS_Store and AppleDouble sidecar files instead.
 */

static int
_gs_set(const char *path, const char *name, const void *value,
        size_t size, int flags)
{
  errno = ENOTSUP;
  return -1;
}

static ssize_t
_gs_get(const char *path, const char *name, void *value, size_t size)
{
  errno = ENOTSUP;
  return -1;
}

static ssize_t
_gs_list(const char *path, char *list, size_t size)
{
  errno = ENOTSUP;
  return -1;
}

static int
_gs_remove(const char *path, const char *name)
{
  errno = ENOTSUP;
  return -1;
}

#else
# error "Unsupported platform: only Linux, FreeBSD, OpenBSD and Windows (MinGW) are supported."
#endif /* platform */

/* ===================================================================
 * Public API
 * =================================================================== */

int
gs_setxattr(const char *path, const char *name,
            const void *value, size_t size, int flags)
{
  if (!path || !name || !value)
    {
      errno = EINVAL;
      return -1;
    }
  if (size > GS_XATTR_MAX_SIZE)
    {
      errno = EFBIG;
      return -1;
    }

#if defined(__FreeBSD__)
  const char *bare_name = STRIP_USER_PREFIX(name);
  return _gs_set(path, bare_name, value, size, flags);
#else
  return _gs_set(path, name, value, size, flags);
#endif
}

ssize_t
gs_getxattr(const char *path, const char *name, void *value, size_t size)
{
  if (!path || !name)
    {
      errno = EINVAL;
      return -1;
    }

#if defined(__FreeBSD__)
  const char *bare_name = STRIP_USER_PREFIX(name);
  return _gs_get(path, bare_name, value, size);
#else
  return _gs_get(path, name, value, size);
#endif
}

ssize_t
gs_listxattr(const char *path, char *list, size_t size)
{
  if (!path)
    {
      errno = EINVAL;
      return -1;
    }

  return _gs_list(path, list, size);
}

int
gs_removexattr(const char *path, const char *name)
{
  if (!path || !name)
    {
      errno = EINVAL;
      return -1;
    }

#if defined(__FreeBSD__)
  const char *bare_name = STRIP_USER_PREFIX(name);
  return _gs_remove(path, bare_name);
#else
  return _gs_remove(path, name);
#endif
}

int
gs_xattr_supported(const char *path)
{
  /* Try to write a tiny test attribute */
  int ret = gs_setxattr(path, "user.gs.test", "t", 1, GS_XATTR_CREATE);
  if (ret == 0)
    {
      gs_removexattr(path, "user.gs.test");
      return 1;
    }

  if (errno == ENOTSUP || errno == EOPNOTSUPP)
    return 0;

  /* EEXIST means xattrs ARE supported (the test attr already existed) */
  if (errno == EEXIST)
    {
      gs_removexattr(path, "user.gs.test");
      return 1;
    }

  return -1;
}

gs_xattr_list_t *
gs_xattr_list_for_path(const char *path, const char *prefix)
{
  if (!path)
    {
      errno = EINVAL;
      return NULL;
    }

  gs_xattr_list_t *list = calloc(1, sizeof(gs_xattr_list_t));
  if (!list)
    return NULL;

  /* Get list size.  Zero means the file carries no attributes, which is an
   * empty list, not a failure; errno is only meaningful for -1. */
  errno = 0;
  ssize_t bufsize = gs_listxattr(path, NULL, 0);
  if (bufsize == 0)
    return list;
  if (bufsize < 0)
    {
      /* ENOTSUP -> the filesystem has none: an empty list, not an error */
      if (errno == ENOTSUP || errno == EOPNOTSUPP)
        return list;
      int saved = errno;
      free(list);
      errno = saved;
      return NULL;
    }

  char *buf = malloc(bufsize);
  if (!buf)
    {
      free(list);
      return NULL;
    }

  /* The list can change between the two calls; ERANGE then means "ask
   * again", which the caller sees as a failure rather than a truncated list. */
  ssize_t ret = gs_listxattr(path, buf, bufsize);
  if (ret < 0)
    {
      int saved = errno;
      free(buf);
      free(list);
      errno = saved;
      return NULL;
    }

  /* Count matching entries */
  size_t prefix_len = (prefix != NULL) ? strlen(prefix) : 0;
  int count = 0;
  char *ptr = buf;
  while (ptr < buf + ret)
    {
      size_t len = strlen(ptr);
      if (len > 0)
        {
          if (!prefix || strncmp(ptr, prefix, prefix_len) == 0)
            count++;
        }
      ptr += len + 1;
    }

  if (count > 0)
    {
      list->entries = calloc(count, sizeof(gs_xattr_entry_t));
      if (!list->entries)
        {
          free(buf);
          free(list);
          return NULL;
        }
    }
  list->count = 0;

  /* Copy matching entries */
  ptr = buf;
  while (ptr < buf + ret)
    {
      size_t len = strlen(ptr);
      if (len > 0)
        {
          if (!prefix || strncmp(ptr, prefix, prefix_len) == 0)
            {
              gs_xattr_entry_t *e = &list->entries[list->count];
              e->name = strdup(ptr);
              if (!e->name)
                {
                  free(buf);
                  gs_xattr_list_free(list);
                  return NULL;
                }
              list->count++;

              /* A value that cannot be read must fail the whole listing:
               * a caller copying attributes would otherwise copy a
               * silently emptied one. */
              ssize_t vsize = gs_getxattr(path, ptr, NULL, 0);
              if (vsize < 0)
                {
                  int saved = errno;
                  free(buf);
                  gs_xattr_list_free(list);
                  errno = saved;
                  return NULL;
                }
              if (vsize > 0)
                {
                  e->value = malloc(vsize);
                  if (!e->value)
                    {
                      free(buf);
                      gs_xattr_list_free(list);
                      return NULL;
                    }
                  ssize_t got = gs_getxattr(path, ptr, e->value, vsize);
                  if (got < 0)
                    {
                      int saved = errno;
                      free(buf);
                      gs_xattr_list_free(list);
                      errno = saved;
                      return NULL;
                    }
                  e->size = got;
                }
            }
        }
      ptr += len + 1;
    }

  free(buf);
  return list;
}

void
gs_xattr_list_free(gs_xattr_list_t *list)
{
  int i;

  if (!list)
    return;

  for (i = 0; i < list->count; i++)
    {
      free(list->entries[i].name);
      free(list->entries[i].value);
    }
  free(list->entries);
  free(list);
}

/* ===================================================================
 * Filesystem type
 * =================================================================== */

#include <stdio.h>

/* Linux only gives a magic number; these are the names mount(8) uses.
 * vfat and msdos share one magic, as do ext2, ext3 and ext4. */
static const struct { unsigned long magic; const char *name; } gsFsMagic[] = {
  { 0x4d44UL,     "msdos" },
  { 0x2011BAB0UL, "exfat" },
  { 0xFF534D42UL, "cifs" },
  { 0xFE534D42UL, "smb3" },
  { 0x517BUL,     "smbfs" },
  { 0x5346544eUL, "ntfs" },
  { 0xEF53UL,     "ext4" },
  { 0x58465342UL, "xfs" },
  { 0x9123683EUL, "btrfs" },
  { 0x2fc12fc1UL, "zfs" },
  { 0xF2F52010UL, "f2fs" },
  { 0xca451a4eUL, "bcachefs" },
  { 0x01021994UL, "tmpfs" },
  { 0x858458f6UL, "ramfs" },
  { 0x794c7630UL, "overlay" },
  { 0x6969UL,     "nfs" },
  { 0x482bUL,     "hfsplus" },
  { 0x4244UL,     "hfs" },
  { 0x9660UL,     "iso9660" },
  { 0x15013346UL, "udf" },
  { 0x73717368UL, "squashfs" },
};
#define GS_FUSE_MAGIC 0x65735546UL

int
gs_fs_type_name_for_magic(unsigned long magic, const char *fuseType,
                          char *buf, size_t size)
{
  const char *name = NULL;
  size_t i;

  if (!buf || size == 0)
    {
      errno = EINVAL;
      return -1;
    }
  if (magic == GS_FUSE_MAGIC)
    name = fuseType ? fuseType : "fuse";
  for (i = 0; name == NULL && i < sizeof(gsFsMagic) / sizeof(gsFsMagic[0]); i++)
    {
      if (magic == gsFsMagic[i].magic)
        name = gsFsMagic[i].name;
    }
  if (name == NULL)
    {
      /* Identified, just not one we tell apart: a name no rule matches,
       * so the item keeps the native behaviour. */
      if (snprintf(buf, size, "0x%lx", magic) >= (int)size)
        {
          errno = ENAMETOOLONG;
          return -1;
        }
      return 0;
    }
  if (strlen(name) >= size)
    {
      errno = ENAMETOOLONG;
      return -1;
    }
  strcpy(buf, name);
  return 0;
}

#if defined(__linux__)
# include <sys/vfs.h>
# include <sys/stat.h>
# include <sys/sysmacros.h>

/* FUSE shares one magic between ntfs-3g, exfat-fuse, sshfs and the rest;
 * only mountinfo, keyed by the device number, says which one it is.
 * Returns 0 when it does not say: the filesystem is still FUSE. */
static int
gs_fuse_type_name(const char *path, char *buf, size_t size)
{
  struct stat st;
  char key[32];
  char line[4096];
  FILE *f;

  if (stat(path, &st) != 0)
    return 0;
  snprintf(key, sizeof(key), " %u:%u ",
           (unsigned)major(st.st_dev), (unsigned)minor(st.st_dev));
  f = fopen("/proc/self/mountinfo", "r");
  if (f == NULL)
    return 0;
  while (fgets(line, sizeof(line), f) != NULL)
    {
      char *sep;
      char *type;
      size_t n;

      if (strstr(line, key) == NULL || (sep = strstr(line, " - ")) == NULL)
        continue;
      type = sep + 3;
      n = strcspn(type, " \n");
      fclose(f);
      if (n == 0 || n >= size)
        return 0;
      memcpy(buf, type, n);
      buf[n] = '\0';
      return 1;
    }
  fclose(f);
  return 0;
}

int
gs_fs_type_name(const char *path, char *buf, size_t size)
{
  struct statfs sf;
  char fuse[64];
  int haveFuse = 0;

  if (!path || !buf || size == 0)
    {
      errno = EINVAL;
      return -1;
    }
  if (statfs(path, &sf) != 0)
    return -1;
  if ((unsigned long)sf.f_type == GS_FUSE_MAGIC)
    haveFuse = gs_fuse_type_name(path, fuse, sizeof(fuse));
  return gs_fs_type_name_for_magic((unsigned long)sf.f_type,
                                   haveFuse ? fuse : NULL, buf, size);
}

#elif defined(__FreeBSD__) || defined(__OpenBSD__)
# include <sys/param.h>
# include <sys/mount.h>

int
gs_fs_type_name(const char *path, char *buf, size_t size)
{
  struct statfs sf;

  if (!path || !buf || size == 0)
    {
      errno = EINVAL;
      return -1;
    }
  if (statfs(path, &sf) != 0)
    return -1;
  if (strlen(sf.f_fstypename) >= size)
    {
      errno = ENAMETOOLONG;
      return -1;
    }
  strcpy(buf, sf.f_fstypename);
  return 0;
}

#elif defined(_WIN32)
# include <windows.h>

int
gs_fs_type_name(const char *path, char *buf, size_t size)
{
  wchar_t wpath[MAX_PATH];
  wchar_t root[MAX_PATH + 1];
  wchar_t fsname[MAX_PATH + 1];

  if (!path || !buf || size == 0)
    {
      errno = EINVAL;
      return -1;
    }
  /* Callers pass UTF-8 (GW_FSREP); the ANSI calls would misread it. */
  if (MultiByteToWideChar(CP_UTF8, 0, path, -1, wpath, MAX_PATH) == 0
      || GetFileAttributesW(wpath) == INVALID_FILE_ATTRIBUTES
      || !GetVolumePathNameW(wpath, root, MAX_PATH + 1)
      || !GetVolumeInformationW(root, NULL, 0, NULL, NULL, NULL,
                                fsname, MAX_PATH + 1))
    {
      errno = ENOENT;
      return -1;
    }
  if (WideCharToMultiByte(CP_UTF8, 0, fsname, -1, buf, (int)size,
                          NULL, NULL) == 0)
    {
      errno = ENAMETOOLONG;
      return -1;
    }
  return 0;
}
#endif

int
gs_fs_type_wants_appledouble(const char *fstype)
{
  /* Mac OS X keeps Finder metadata in "._" files on exactly these: it has
   * no native attributes on FAT and exFAT, and over SMB and on NTFS it does
   * not see the attributes a Linux mount stores there. */
  static const char *const appleDouble[] = {
    "msdos", "msdosfs", "vfat", "fat", "fat12", "fat16", "fat32", "exfat",
    "cifs", "smb", "smb2", "smb3", "smbfs",
    "ntfs", "ntfs3", "ntfs-3g", "fuseblk",
  };
  char lower[64];
  const char *name;
  size_t i;

  if (!fstype || strlen(fstype) >= sizeof(lower))
    return 0;
  for (i = 0; fstype[i]; i++)
    lower[i] = (fstype[i] >= 'A' && fstype[i] <= 'Z')
      ? (char)(fstype[i] - 'A' + 'a') : fstype[i];
  lower[i] = '\0';
  /* FUSE drivers are named after what they mount: fuse.exfat on Linux,
   * fusefs.ntfs on FreeBSD. */
  name = lower;
  if (strncmp(name, "fuse.", 5) == 0)
    name += 5;
  else if (strncmp(name, "fusefs.", 7) == 0)
    name += 7;
  for (i = 0; i < sizeof(appleDouble) / sizeof(appleDouble[0]); i++)
    {
      if (strcmp(name, appleDouble[i]) == 0)
        return 1;
    }
  return 0;
}

int
gs_fs_type_is_smb(const char *fstype)
{
  static const char *const smb[] = { "cifs", "smb", "smb2", "smb3", "smbfs" };
  size_t i;

  for (i = 0; fstype && i < sizeof(smb) / sizeof(smb[0]); i++)
    {
      if (strcmp(fstype, smb[i]) == 0)
        return 1;
    }
  return 0;
}
