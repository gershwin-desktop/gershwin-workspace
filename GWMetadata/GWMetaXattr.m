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

#elif defined(__OpenBSD__)
/*
 * OpenBSD does not support extended attributes.
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
# error "Unsupported platform: only Linux, FreeBSD, and OpenBSD are supported."
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

  /* Get list size */
  ssize_t bufsize = gs_listxattr(path, NULL, 0);
  if (bufsize <= 0)
    {
      /* ENOTSUP / no attrs -> return empty list, not an error */
      if (errno == ENOTSUP || errno == EOPNOTSUPP)
        return list;
      free(list);
      return NULL;
    }

  char *buf = malloc(bufsize);
  if (!buf)
    {
      free(list);
      return NULL;
    }

  ssize_t ret = gs_listxattr(path, buf, bufsize);
  if (ret <= 0)
    {
      free(buf);
      free(list);
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

  list->entries = calloc(count, sizeof(gs_xattr_entry_t));
  if (!list->entries && count > 0)
    {
      free(buf);
      free(list);
      return NULL;
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

              ssize_t vsize = gs_getxattr(path, ptr, NULL, 0);
              if (vsize > 0)
                {
                  e->value = malloc(vsize);
                  if (e->value)
                    {
                      gs_getxattr(path, ptr, e->value, vsize);
                      e->size = vsize;
                    }
                }
              list->count++;
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
