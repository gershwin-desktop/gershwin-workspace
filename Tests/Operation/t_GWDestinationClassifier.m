/* t_GWDestinationClassifier.m - which destinations count as removable or
 * network: filesystem types, mountinfo parsing, and removable detection
 * from sysfs trees built the way the kernel lays them out.  Headless.
 *
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

/* The unit below needs the GNU declarations, which must come before the
 * first system header. */
#if defined(__linux__) && !defined(_GNU_SOURCE)
#define _GNU_SOURCE
#endif
#import <Foundation/Foundation.h>
#import "Testing.h"
#include "../../Operation/GWDestinationClassifier.m"

static NSString *root;

static void
mkdirs(NSString *rel)
{
  [[NSFileManager defaultManager]
    createDirectoryAtPath: [root stringByAppendingPathComponent: rel]
    withIntermediateDirectories: YES
    attributes: nil
    error: NULL];
}

static void
attr(NSString *rel, NSString *value)
{
  NSString *p = [root stringByAppendingPathComponent: rel];

  mkdirs([rel stringByDeletingLastPathComponent]);
  [[value stringByAppendingString: @"\n"] writeToFile: p atomically: NO];
}

/* A relative link, as sysfs has them, so the tree works wherever it is. */
static void
link_(NSString *rel, NSString *target)
{
  NSString *p = [root stringByAppendingPathComponent: rel];

  mkdirs([rel stringByDeletingLastPathComponent]);
  symlink([target fileSystemRepresentation], [p fileSystemRepresentation]);
}

/* A disk under `devpath' (relative to devices/), with partitions, its
 * /sys/dev/block links and its class/block link. */
static void
disk(NSString *devpath, NSString *name, NSString *majmin, NSString *removable)
{
  NSString *blk = [NSString stringWithFormat: @"devices/%@/block/%@",
                            devpath, name];

  attr([blk stringByAppendingPathComponent: @"removable"], removable);
  link_([blk stringByAppendingPathComponent: @"device"], @"../..");
  link_([@"dev/block" stringByAppendingPathComponent: majmin],
        [@"../../" stringByAppendingString: blk]);
  link_([@"class/block" stringByAppendingPathComponent: name],
        [@"../../" stringByAppendingString: blk]);
}

static void
partition(NSString *devpath, NSString *diskName, NSString *name,
          NSString *majmin)
{
  NSString *p = [NSString stringWithFormat: @"devices/%@/block/%@/%@",
                          devpath, diskName, name];

  attr([p stringByAppendingPathComponent: @"partition"], @"1");
  link_([@"dev/block" stringByAppendingPathComponent: majmin],
        [@"../../" stringByAppendingString: p]);
  link_([@"class/block" stringByAppendingPathComponent: name],
        [@"../../" stringByAppendingString: p]);
}

/* A device-mapper or md device built on `slaves' (class/block names). */
static void
virtualDisk(NSString *name, NSString *majmin, NSArray *slaves)
{
  NSString *blk = [@"devices/virtual/block" stringByAppendingPathComponent: name];
  NSEnumerator *en = [slaves objectEnumerator];
  NSString *s;

  attr([blk stringByAppendingPathComponent: @"removable"], @"0");
  link_([@"dev/block" stringByAppendingPathComponent: majmin],
        [@"../../" stringByAppendingString: blk]);
  link_([@"class/block" stringByAppendingPathComponent: name],
        [@"../../" stringByAppendingString: blk]);
  while ((s = [en nextObject]) != nil)
    {
      link_([[blk stringByAppendingPathComponent: @"slaves"]
              stringByAppendingPathComponent: s],
            [@"../../../../../class/block" stringByAppendingPathComponent: s]);
    }
}

static GWDestinationClassifier *
newClassifier(NSString *mountinfo)
{
  return AUTORELEASE([[GWDestinationClassifier alloc]
                       initWithSysfsRoot: root
                           mountInfoPath: mountinfo]);
}

int
main(void)
{
  NSAutoreleasePool *arp = [NSAutoreleasePool new];
  NSFileManager *fm = [NSFileManager defaultManager];
  NSString *usb = @"pci0000:00/0000:00:14.0/usb2/2-1/2-1:1.0/host6/target6:0:0/6:0:0:0";
  NSString *usbssd = @"pci0000:00/0000:00:14.0/usb2/2-2/2-2:1.0/host7/target7:0:0/7:0:0:0";
  NSString *sata = @"pci0000:00/0000:00:17.0/ata1/host0/target0:0:0/0:0:0:0";
  NSString *sd = @"platform/fe320000.mmc/mmc_host/mmc0/mmc0:aaaa";
  NSString *emmc = @"platform/fe330000.mmc/mmc_host/mmc1/mmc1:0001";
  NSString *nvme = @"pci0000:00/0000:00:1d.0/0000:3a:00.0/nvme/nvme0";

  unsetenv("GW_COPY_DESTINATION");
  root = [NSTemporaryDirectory() stringByAppendingPathComponent:
           [NSString stringWithFormat: @"t_GWDestinationClassifier-%d", getpid()]];
  [fm removeFileAtPath: root handler: nil];
  /* realpath() of the fixture must agree with the root we compare to. */
  mkdirs(@"devices");
  root = realPath(root);

  disk(usb, @"sdb", @"8:16", @"1");
  partition(usb, @"sdb", @"sdb1", @"8:17");
  disk(usbssd, @"sdc", @"8:32", @"0");
  partition(usbssd, @"sdc", @"sdc1", @"8:33");
  attr(@"devices/pci0000:00/0000:00:14.0/usb2/2-2/removable", @"removable");
  attr(@"devices/pci0000:00/0000:00:14.0/usb2/removable", @"unknown");
  disk(sata, @"sda", @"8:0", @"0");
  partition(sata, @"sda", @"sda2", @"8:2");
  disk(sd, @"mmcblk0", @"179:0", @"0");
  partition(sd, @"mmcblk0", @"mmcblk0p1", @"179:1");
  attr([@"devices" stringByAppendingPathComponent:
          [sd stringByAppendingPathComponent: @"type"]], @"SD");
  disk(emmc, @"mmcblk1", @"179:32", @"0");
  attr([@"devices" stringByAppendingPathComponent:
          [emmc stringByAppendingPathComponent: @"type"]], @"MMC");
  disk(nvme, @"nvme0n1", @"259:0", @"0");
  attr(@"devices/pci0000:00/0000:00:1d.0/0000:3a:00.0/removable", @"fixed");
  virtualDisk(@"dm-0", @"254:0", @[ @"sdb1" ]);
  virtualDisk(@"dm-1", @"254:1", @[ @"sda2" ]);
  virtualDisk(@"md0", @"9:0", @[ @"sda2", @"sdc1" ]);
  virtualDisk(@"dm-2", @"254:2", @[ @"md0" ]);

  START_SET("filesystem types")
    PASS([GWDestinationClassifier classOfFilesystemType: @"nfs4" source: @"srv:/x"]
         == GWFilesystemNetwork, "nfs4 is network");
    PASS([GWDestinationClassifier classOfFilesystemType: @"cifs" source: @"//s/x"]
         == GWFilesystemNetwork, "cifs is network");
    PASS([GWDestinationClassifier classOfFilesystemType: @"smb3" source: @"//s/x"]
         == GWFilesystemNetwork, "smb3 is network");
    PASS([GWDestinationClassifier classOfFilesystemType: @"ceph" source: @"m:/"]
         == GWFilesystemNetwork, "ceph is network");
    PASS([GWDestinationClassifier classOfFilesystemType: @"fuse.glusterfs"
                                                 source: @"srv:/vol"]
         == GWFilesystemNetwork, "glusterfs is network");
    PASS([GWDestinationClassifier classOfFilesystemType: @"9p" source: @"share"]
         == GWFilesystemNetwork, "9p is network");
    PASS([GWDestinationClassifier classOfFilesystemType: @"fuse.sshfs"
                                                 source: @"me@host:"]
         == GWFilesystemNetwork, "sshfs is network");
    PASS([GWDestinationClassifier classOfFilesystemType: @"fuse.rclone"
                                                 source: @"drive:"]
         == GWFilesystemNetwork, "rclone is network");
    PASS([GWDestinationClassifier classOfFilesystemType: @"fuse.somefs"
                                                 source: @"somefs"]
         == GWFilesystemNetwork, "FUSE without a device counts as network");
    PASS([GWDestinationClassifier classOfFilesystemType: @"fuseblk"
                                                 source: @"/dev/sdb1"]
         == GWFilesystemDeviceBacked, "fuseblk (ntfs-3g) is decided by its disk");
    PASS([GWDestinationClassifier classOfFilesystemType: @"vfat"
                                                 source: @"/dev/sdb1"]
         == GWFilesystemDeviceBacked, "vfat is decided by its disk");
    PASS([GWDestinationClassifier classOfFilesystemType: @"tmpfs" source: @"tmpfs"]
         == GWFilesystemVirtual, "tmpfs is local without a device");
  END_SET("filesystem types")

  START_SET("mount table")
    NSDictionary *m = [GWDestinationClassifier parseMountInfoLine:
      @"412 29 8:17 / /media/admin/MY\\040STICK rw,nosuid,nodev,relatime shared:220 - vfat /dev/sdb1 rw,fmask=0022"];
    NSArray *mounts = @[ @{ @"mountPoint": @"/" },
                         @{ @"mountPoint": @"/mnt/a" },
                         @{ @"mountPoint": @"/mnt/ab" } ];

    PASS([[m objectForKey: @"mountID"] intValue] == 412
         && [[m objectForKey: @"major"] intValue] == 8
         && [[m objectForKey: @"minor"] intValue] == 17,
         "mount id and device numbers are read");
    PASS_EQUAL([m objectForKey: @"mountPoint"], @"/media/admin/MY STICK",
               "escaped blanks in the mount point are decoded");
    PASS_EQUAL([m objectForKey: @"type"], @"vfat", "the type follows the dash");
    PASS_EQUAL([m objectForKey: @"source"], @"/dev/sdb1", "and the source");
    PASS([GWDestinationClassifier parseMountInfoLine: @"garbage"] == nil,
         "a broken line is no mount");
    PASS_EQUAL([[GWDestinationClassifier mountForPath: @"/mnt/ab/x"
                                             inMounts: mounts]
                 objectForKey: @"mountPoint"], @"/mnt/ab",
               "the longest mount point containing the path wins");
    PASS_EQUAL([[GWDestinationClassifier mountForPath: @"/mnt/abc"
                                             inMounts: mounts]
                 objectForKey: @"mountPoint"], @"/",
               "a name prefix is not a parent folder");
  END_SET("mount table")

  START_SET("BSD disks")
    PASS_EQUAL([GWDestinationClassifier diskNameOfMountSource: @"/dev/da0p1"],
               @"da0", "FreeBSD partition to disk");
    PASS_EQUAL([GWDestinationClassifier diskNameOfMountSource: @"/dev/sd1i"],
               @"sd1", "OpenBSD partition to disk");
    PASS([GWDestinationClassifier diskNameOfMountSource: @"/dev/msdosfs/STICK"]
         == nil, "a label names no disk");
    PASS([GWDestinationClassifier diskNameOfMountSource: @"srv:/export"] == nil,
         "a server names no disk");
    PASS([GWDestinationClassifier isRemovableBSDDisk: @"da0"
                                             daFlags: @"0x8<PACK_REMOVABLE>"],
         "a da disk with the removable-medium flag is removable");
    PASS(![GWDestinationClassifier isRemovableBSDDisk: @"da0" daFlags: @"0"],
         "a da disk without it is not");
    PASS([GWDestinationClassifier isRemovableBSDDisk: @"mmcsd0" daFlags: nil],
         "an SD card is removable");
    PASS(![GWDestinationClassifier isRemovableBSDDisk: @"ada0" daFlags: nil],
         "a SATA disk is not");
  END_SET("BSD disks")

  START_SET("sysfs removable detection")
    GWDestinationClassifier *c = newClassifier(@"/nonexistent");

    PASS([c isRemovableDeviceMajor: 8 minor: 16],
         "a disk with the removable flag");
    PASS([c isRemovableDeviceMajor: 8 minor: 17],
         "a partition of it, through its disk");
    PASS([c isRemovableDeviceMajor: 8 minor: 33],
         "a USB disk without the flag, on a port the kernel marks removable");
    PASS(![c isRemovableDeviceMajor: 8 minor: 2], "an internal SATA disk");
    PASS([c isRemovableDeviceMajor: 179 minor: 1], "an SD card");
    PASS(![c isRemovableDeviceMajor: 179 minor: 32], "built-in eMMC");
    PASS(![c isRemovableDeviceMajor: 259 minor: 0], "NVMe in a fixed slot");
    PASS([c isRemovableDeviceMajor: 254 minor: 0],
         "an encrypted volume on a USB stick");
    PASS(![c isRemovableDeviceMajor: 254 minor: 1],
         "an encrypted volume on the internal disk");
    PASS([c isRemovableDeviceMajor: 254 minor: 2],
         "LVM on RAID with one USB member");
    PASS(![c isRemovableDeviceMajor: 7 minor: 99], "an unknown device");

    attr([NSString stringWithFormat: @"devices/%@/block/sdb/removable", usb], @"0");
    PASS([c isRemovableDeviceMajor: 8 minor: 16],
         "the answer is cached per device");
  END_SET("sysfs removable detection")

  START_SET("destination of a folder")
    NSString *dir = NSTemporaryDirectory();
    NSString *info = [root stringByAppendingPathComponent: @"mountinfo"];
    long mid = -1;
    struct stat st;
    NSString *line;
    GWDestination *d;

#if defined(STATX_MNT_ID)
    {
      struct statx stx;

      statx(AT_FDCWD, [dir fileSystemRepresentation], 0, STATX_MNT_ID, &stx);
      mid = (long)stx.stx_mnt_id;
    }
#endif
    stat([dir fileSystemRepresentation], &st);

    line = [NSString stringWithFormat:
      @"%ld 1 %u:%u / /fixture rw - vfat /dev/sdb1 rw\n",
      mid, major(st.st_dev), minor(st.st_dev)];
    [line writeToFile: info atomically: NO];
    /* Not the fixture's 8:17: what decides is the device, so point the
     * fixture's numbers at the removable disk. */
    attr([NSString stringWithFormat: @"devices/%@/block/sdb/removable", usb], @"1");
    link_([NSString stringWithFormat: @"dev/block/%u:%u",
                    major(st.st_dev), minor(st.st_dev)],
          [NSString stringWithFormat: @"../../devices/%@/block/sdb", usb]);
    d = [newClassifier(info) destinationForDirectory: dir];
    PASS([d kind] == GWDestinationRemovable && [d needsFinalFlush]
         && [d usesWriteWindows] && [d windowCap] == GW_COPY_WINDOW_CAP,
         "a folder on a removable disk: windows and the final flush");
    PASS_EQUAL([d mountPoint], @"/fixture", "the mount is found");

    [[NSString stringWithFormat: @"%ld 1 0:77 / /fixture rw - cifs //srv/x rw\n", mid]
      writeToFile: info atomically: NO];
    if (mid < 0)
      {
        [[NSString stringWithFormat: @"%ld 1 %u:%u / /fixture rw - cifs //srv/x rw\n",
                   mid, major(st.st_dev), minor(st.st_dev)]
          writeToFile: info atomically: NO];
      }
    d = [newClassifier(info) destinationForDirectory: dir];
    PASS([d kind] == GWDestinationNetwork && ![d needsFinalFlush]
         && [d usesWriteWindows] && [d windowCap] == GW_COPY_CIFS_WINDOW_CAP,
         "a folder on a CIFS share: windows of up to 128 MiB, no final flush");

    [[NSString stringWithFormat: @"%ld 1 0:77 / /fixture rw - tmpfs tmpfs rw\n", mid]
      writeToFile: info atomically: NO];
    if (mid < 0)
      {
        [[NSString stringWithFormat: @"%ld 1 %u:%u / /fixture rw - tmpfs tmpfs rw\n",
                   mid, major(st.st_dev), minor(st.st_dev)]
          writeToFile: info atomically: NO];
      }
    d = [newClassifier(info) destinationForDirectory: dir];
    PASS([d kind] == GWDestinationLocal && ![d usesWriteWindows]
         && ![d needsFinalFlush], "a local folder stays as it was");

    setenv("GW_COPY_DESTINATION", "removable", 1);
    d = [newClassifier(info) destinationForDirectory: dir];
    PASS([d kind] == GWDestinationRemovable,
         "the environment can force the removable path for tests");
    unsetenv("GW_COPY_DESTINATION");
  END_SET("destination of a folder")

  [fm removeFileAtPath: root handler: nil];
  [arp release];
  return 0;
}
