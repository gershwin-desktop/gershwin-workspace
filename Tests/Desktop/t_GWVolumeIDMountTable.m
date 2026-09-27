/* t_GWVolumeIDMountTable.m - proves +[GWVolumeID mountedFilesystemsFromTable:]
 * lists every entry of a mount table by READING it (getmntent), including a
 * FUSE (sshfs) mount and an NFS mount - the two kinds of mount whose
 * underlying filesystem must never be probed, because a wedged network
 * share or a hung FUSE helper blocks forever inside statfs() (this is what
 * MPointWatcher's old 1.5s timer did to every Workspace on this machine
 * once, via NSWorkspace's statfs-per-mount implementation; see the commit
 * this test accompanies).
 *
 * The fixture's mount points (under /nonexistent/mnt/...) do not exist on
 * this machine, so a statfs()/stat() on them would fail; the test would
 * then see those entries silently dropped if the parser tried to confirm
 * them that way. Getting the exact fixture entries back proves the parser
 * works from the table TEXT alone. The evidence directory also carries an
 * `strace -c` run of this same binary showing zero statfs/stat/access
 * calls.
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */
#import <Foundation/Foundation.h>
#import "Testing.h"
#import "../../Workspace/FileViewer/GWVolumeID.h"

int main(void)
{
  NSAutoreleasePool *arp = [NSAutoreleasePool new];

#if defined(__linux__)
  NSString *thisFile = [NSString stringWithUTF8String: __FILE__];
  NSString *fixture = [[thisFile stringByDeletingLastPathComponent]
                         stringByAppendingPathComponent: @"fixture_proc_mounts.txt"];

  NSArray *entries = [GWVolumeID mountedFilesystemsFromTable: fixture];

  PASS(entries != nil && [entries count] == 6,
       "every line of the fixture mount table comes back, none skipped");

  {
    BOOL foundFuse = NO, foundNfs = NO, foundRoot = NO;
    NSDictionary *e;

    for (e in entries)
      {
        NSString *mp   = [e objectForKey: @"mountPoint"];
        NSString *type = [e objectForKey: @"fsType"];

        if ([mp isEqualToString: @"/nonexistent/mnt/remote"]
            && [type isEqualToString: @"fuse.sshfs"])
          foundFuse = YES;
        if ([mp isEqualToString: @"/nonexistent/mnt/nfsshare"]
            && [type isEqualToString: @"nfs4"])
          foundNfs = YES;
        if ([mp isEqualToString: @"/"] && [type isEqualToString: @"ext4"])
          foundRoot = YES;
      }

    PASS(foundFuse,
         "a FUSE (sshfs) mount at a nonexistent path is listed from table text alone");
    PASS(foundNfs,
         "an NFS mount at a nonexistent path is listed from table text alone");
    PASS(foundRoot, "the real root filesystem is listed alongside the others");
  }

  PASS([GWVolumeID mountedFilesystemsFromTable: @"/nonexistent-table-path"] != nil,
       "an unreadable table path returns an empty array, not a crash");
  PASS([[GWVolumeID mountedFilesystemsFromTable: @"/nonexistent-table-path"] count] == 0,
       "an unreadable table path returns zero entries");
#else
  /* The BSDs have no on-disk mount table to point a fixture at -
   * getmntinfo(3) always reads the live kernel list. Cover the live path
   * instead: it must return without touching any filesystem. */
  NSArray *live = [GWVolumeID mountedFilesystems];
  PASS(live != nil, "the live mount table (getmntinfo) reads without crashing");
#endif

  [arp release];
  return 0;
}
