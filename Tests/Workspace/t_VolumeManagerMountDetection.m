/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

/* t_VolumeManagerMountDetection.m - VMPathIsActiveMountPoint (VolumeManager.h)
 * must tell a real mount from an ordinary directory that merely exists.
 * The old -isMountPointActive: called statfs() on the path itself, which
 * succeeds for ANY existing directory, mounted or not - so a stale
 * directory left behind by a dead FUSE helper read back as "still
 * mounted" forever. Headless: reads the live kernel mount table, no
 * display, no privileges.
 *
 * VMPathIsActiveMountPoint is declared `static inline` directly in
 * VolumeManager.h so this test can exercise VolumeManager's real mount
 * -detection logic without linking VolumeManager.m's own AppKit/Workspace/
 * FSNode/AVFS dependencies, which a two-line predicate has no need of. */

#import <Foundation/Foundation.h>
#import "Testing.h"
#import "../../Workspace/VolumeManager.h"

int main(void)
{
  NSAutoreleasePool *arp = [NSAutoreleasePool new];
  NSFileManager *fm = [NSFileManager defaultManager];

  /* --- a real mount point must count as mounted --- */
  {
    /* "/" is always in the live mount table, on every platform this must
     * build on (Linux getmntent, the BSDs getmntinfo). */
    PASS(VMPathIsActiveMountPoint(@"/"),
         "the root filesystem's mount point is reported as active");
  }

  /* --- an existing but never-mounted directory must NOT count --- */
  {
    NSString *dir = [NSString stringWithFormat:@"/tmp/t_VolumeManagerMountDetection.%d",
                     (int)getpid()];
    [fm removeItemAtPath:dir error:nil];
    PASS([fm createDirectoryAtPath:dir withIntermediateDirectories:YES
                         attributes:nil error:nil],
         "test fixture directory was created");

    PASS(!VMPathIsActiveMountPoint(dir),
         "an ordinary existing directory is NOT reported as an active mount, "
         "unlike the old statfs()-based check which returned YES for it");

    [fm removeItemAtPath:dir error:nil];
  }

  /* --- a path that does not exist at all must NOT count either --- */
  {
    NSString *missing = [NSString stringWithFormat:@"/tmp/t_VolumeManagerMountDetection-missing.%d",
                         (int)getpid()];
    PASS(!VMPathIsActiveMountPoint(missing),
         "a path with nothing there at all is not reported as mounted");
  }

  [arp release];
  return 0;
}
