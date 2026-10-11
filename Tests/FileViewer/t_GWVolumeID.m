/* t_GWVolumeID.m — ObjectTesting coverage for GWVolumeID.
 *
 * Self-contained: GWVolumeID is Foundation-only (statfs + string work, no
 * gnustep-gui), so the implementation is compiled in-process and runs
 * headless.  These assertions describe the stable public contract and act
 * as a behaviour guard for the CR-14 rewrite (replacing /proc/self/mountinfo
 * with getmntent/getmntinfo): the results below must not change.
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

#import <Foundation/Foundation.h>
#import "Testing.h"

#include "../../Workspace/FileViewer/GWVolumeID.m"

int
main(void)
{
  NSAutoreleasePool *arp = [NSAutoreleasePool new];

  /* nil path is handled without crashing */
  PASS([GWVolumeID volumeIDForPath: nil] == nil, "volumeIDForPath: nil -> nil");

  /* The root volume always resolves to a stable, non-empty id */
  NSString *root1 = [GWVolumeID volumeIDForPath: @"/"];
  PASS(root1 != nil && [root1 length] > 0, "volumeIDForPath: / is non-empty");

  NSString *root2 = [GWVolumeID volumeIDForPath: @"/"];
  PASS_EQUAL(root1, root2, "volume id is stable across calls (cached)");

  /* Two paths on the same volume share an id */
  NSString *tmpOnRoot = [GWVolumeID volumeIDForPath: @"/etc"];
  PASS_EQUAL(tmpOnRoot, root1, "paths on the same volume share a volume id");

  /* The local root filesystem is not a network mount */
  PASS([GWVolumeID isNetworkMount: @"/"] == NO, "/ is not a network mount");

  /* Filesystem type is reported for a local path */
  PASS([GWVolumeID filesystemTypeForPath: @"/"] != nil,
       "filesystemTypeForPath: / is non-nil");

  /* Cache file path is derived and well-formed */
  NSString *cf = [GWVolumeID cacheFilePathForPath: @"/"];
  PASS(cf != nil && [cf hasSuffix: @".DS_Store"],
       "cacheFilePathForPath: / ends in .DS_Store");

  /* --- removable media keep their cache file: the id is the file
   * system's own identity, not the device number --- */
  {
    NSFileManager *fm = [NSFileManager defaultManager];
    /* Any device node will do; the mount source of / is none in a container
     * (overlay), and the BSDs' /dev/ufsid and /dev/gptid are searched after
     * /dev/disk/by-uuid, which the second directory stands in for. */
    NSString *source = @"/dev/null";
    NSString *dir = [NSTemporaryDirectory() stringByAppendingPathComponent:
                      [NSString stringWithFormat: @"t_GWVolumeID_%d", (int)getpid()]];
    NSString *plain = [dir stringByAppendingPathComponent: @"plain"];
    NSString *first = [dir stringByAppendingPathComponent: @"by-uuid"];

    [fm removeFileAtPath: dir handler: nil];
    [fm createDirectoryAtPath: dir attributes: nil];
    [fm createSymbolicLinkAtPath: [dir stringByAppendingPathComponent: @"1234-ABCD"]
                     pathContent: source];
    [fm createFileAtPath: plain contents: [NSData data] attributes: nil];

    PASS_EQUAL([GWVolumeID filesystemIdentityForDevice: source
                                         inDirectories: [NSArray arrayWithObject: dir]],
               @"1234-ABCD",
               "MI-IV-87 the identity is the name that links to the volume's device");
    PASS([GWVolumeID filesystemIdentityForDevice: plain
                                   inDirectories: [NSArray arrayWithObject: dir]] == nil,
         "MI-IV-88 something that is not a device has none");
    [fm createDirectoryAtPath: first attributes: nil];
    PASS_EQUAL([GWVolumeID filesystemIdentityForDevice: source
                                         inDirectories: ([NSArray arrayWithObjects: first, dir, nil])],
               @"1234-ABCD",
               "a later directory (ufsid, gptid) is searched when an earlier one has no entry");
    PASS([GWVolumeID filesystemIdentityForDevice: source
                                   inDirectories: [NSArray arrayWithObject: first]] == nil,
         "a device with no entry in any directory has no identity");
    if ([fm fileExistsAtPath: @"/dev/disk/by-uuid"])
      {
        NSString *uuid = [GWVolumeID filesystemIdentityForDevice:
                                       [GWVolumeID mountSourceForPath: @"/"]
                                                   inDirectories:
                                    [NSArray arrayWithObject: @"/dev/disk/by-uuid"]];

        PASS(uuid == nil
             || [[GWVolumeID volumeIDForPath: @"/"]
                  isEqual: [@"uuid_" stringByAppendingString: uuid]],
             "MI-IV-89 a volume with a file system UUID is named after it");
      }
    [fm removeFileAtPath: dir handler: nil];
  }

  [arp release];
  return 0;
}
