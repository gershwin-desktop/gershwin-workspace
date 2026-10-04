/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

/* SMB hosts are shown in the Network folder with an "(smb)" suffix, like
 * the other protocols. */

#import <Foundation/Foundation.h>
#import "Testing.h"
#import "NetworkServiceItem.h"

int
main(void)
{
  NSAutoreleasePool *arp = [NSAutoreleasePool new];

  START_SET("smb item")
    {
      NetworkServiceItem *item = [[[NetworkServiceItem alloc] init] autorelease];
      item.name = @"MUSIC";
      item.type = @"_smb._tcp.";
      item.domain = @"local.";

      PASS([item isSMBService], "_smb._tcp. is an SMB service");
      PASS(![item isSFTPService] && ![item isAFPService]
           && ![item isWebDAVService], "and no other kind");
      PASS([[item displayName] isEqual: @"MUSIC (smb)"],
           "the display name carries the (smb) suffix");

      item.type = @"_sftp-ssh._tcp.";
      PASS(![item isSMBService], "an SFTP service is not an SMB service");
    }
  END_SET("smb item")

  [arp release];
  return 0;
}
