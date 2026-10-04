/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

/* A NetBIOS node status answer lists many names; the file server name
 * (suffix 0x20) and the workgroup (group name, suffix 0x00) are the ones that
 * identify an SMB host in the Network folder. */

#import <Foundation/Foundation.h>
#import "Testing.h"
#import "SMBDiscovery.h"

static NSDictionary *
entry(NSString *name, int type, BOOL group)
{
  return [NSDictionary dictionaryWithObjectsAndKeys:
            name, @"name",
            [NSNumber numberWithInt: type], @"type",
            [NSNumber numberWithBool: group], @"group",
            nil];
}

int
main(void)
{
  NSAutoreleasePool *arp = [NSAutoreleasePool new];

  START_SET("node status names")
    {
      NSArray *names = [NSArray arrayWithObjects:
                         entry(@"MUSIC", 0x00, NO),
                         entry(@"WORKGROUP", 0x00, YES),
                         entry(@"MUSIC", 0x20, NO),
                         entry(@"WORKGROUP", 0x1e, YES),
                         nil];
      NSDictionary *record = [SMBDiscovery hostRecordFromNodeStatusNames: names];

      PASS([[record objectForKey: @"name"] isEqual: @"MUSIC"],
           "the file server name is the 0x20 entry");
      PASS([[record objectForKey: @"workgroup"] isEqual: @"WORKGROUP"],
           "the workgroup is the 0x00 group entry");

      PASS([SMBDiscovery hostRecordFromNodeStatusNames:
              [NSArray arrayWithObject: entry(@"MUSIC", 0x00, NO)]] == nil,
           "a host without a file server name is not an SMB host");
      PASS([SMBDiscovery hostRecordFromNodeStatusNames: nil] == nil,
           "nil yields nil");
    }
  END_SET("node status names")

  [arp release];
  return 0;
}
