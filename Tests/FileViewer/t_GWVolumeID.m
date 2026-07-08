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

  [arp release];
  return 0;
}
