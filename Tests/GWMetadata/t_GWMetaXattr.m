/* t_GWMetaXattr.m — ObjectTesting coverage for the portable xattr wrapper.
 *
 * Compiles the unit under test in-process (Foundation only, no display) so it
 * runs headless via `gnustep-tests`.  Covers the set/get/list/remove round-trip
 * that fdLocation-in-xattr persistence relies on, and the ENOTSUP path for
 * filesystems/platforms without extended-attribute support (e.g. OpenBSD,
 * some tmpfs), where the suite must skip rather than fail.
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

#import <Foundation/Foundation.h>
#import "Testing.h"

#include <errno.h>
#include <string.h>
#include <unistd.h>

/* Bring the implementation in directly — it depends only on libc. */
#include "GWMetaXattr.m"

int
main(void)
{
  NSAutoreleasePool *arp = [NSAutoreleasePool new];
  NSFileManager *fm = [NSFileManager defaultManager];

  NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:
                     [NSString stringWithFormat: @"t_gwmetaxattr_%d", (int)getpid()]];
  [fm removeFileAtPath: path handler: nil];
  [fm createFileAtPath: path contents: [NSData data] attributes: nil];

  const char *cpath = [path fileSystemRepresentation];
  const char *name  = "user.com.apple.TestAttr";
  const unsigned char value[4] = { 0x01, 0x02, 0x03, 0x04 };

  errno = 0;
  int rc = gs_setxattr(cpath, name, value, sizeof(value), 0);

  BOOL unsupported = (rc != 0) &&
    (errno == ENOTSUP
#ifdef EOPNOTSUPP
     || errno == EOPNOTSUPP
#endif
     || errno == ENOSYS);

  if (unsupported)
    {
      /* No xattr support on this filesystem/platform: assert the wrapper
       * reports that consistently, and skip the round-trip. */
      PASS(gs_xattr_supported(cpath) == 0,
           "gs_xattr_supported() reports unsupported when setxattr returns ENOTSUP");
    }
  else
    {
      PASS(rc == 0, "gs_setxattr() writes an attribute");

      ssize_t need = gs_getxattr(cpath, name, NULL, 0);
      PASS(need == (ssize_t)sizeof(value),
           "gs_getxattr() size query returns the value length");

      unsigned char buf[16] = {0};
      ssize_t got = gs_getxattr(cpath, name, buf, sizeof(buf));
      PASS(got == (ssize_t)sizeof(value)
           && memcmp(buf, value, sizeof(value)) == 0,
           "gs_getxattr() round-trips the value bytes");

      ssize_t lsz = gs_listxattr(cpath, NULL, 0);
      PASS(lsz > 0, "gs_listxattr() size query is > 0");
      char *list = malloc((size_t)(lsz > 0 ? lsz : 1));
      ssize_t ln = gs_listxattr(cpath, list, (size_t)lsz);
      BOOL found = NO;
      for (ssize_t i = 0; i >= 0 && i < ln; )
        {
          if (strcmp(list + i, name) == 0) { found = YES; break; }
          i += (ssize_t)strlen(list + i) + 1;
        }
      free(list);
      PASS(found, "gs_listxattr() includes the attribute name");

      PASS(gs_removexattr(cpath, name) == 0, "gs_removexattr() succeeds");

      errno = 0;
      ssize_t after = gs_getxattr(cpath, name, buf, sizeof(buf));
      PASS(after < 0, "gs_getxattr() after remove fails (attribute is gone)");

      PASS(gs_xattr_supported(cpath) == 1,
           "gs_xattr_supported() reports supported on an xattr filesystem");
    }

  [fm removeFileAtPath: path handler: nil];
  [arp release];
  return 0;
}
