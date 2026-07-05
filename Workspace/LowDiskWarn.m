/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-2.0-only
 */

#include "config.h"

#import "LowDiskWarn.h"
#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <GNUstepBase/GNUstep.h>
#include <sys/statvfs.h>

@implementation LowDiskWarn

- (void)dealloc
{
  [self stopMonitoring];
  [super dealloc];
}

- (void)startMonitoring
{
  [NSApplication sharedApplication];
  checking = NO;
  [self checkDiskSpace: nil];
  timer = [NSTimer scheduledTimerWithTimeInterval: 120.0
                                           target: self
                                         selector: @selector(checkDiskSpace:)
                                         userInfo: nil
                                          repeats: YES];
}

- (void)stopMonitoring
{
  if (timer && [timer isValid])
    {
      [timer invalidate];
    }
  timer = nil;
}

- (void)checkDiskSpace:(NSTimer *)aTimer
{
  if (checking)
    return;
  checking = YES;

  struct statvfs buf;
  int ret = statvfs("/", &buf);

  if (ret == 0)
    {
      unsigned long long total = (unsigned long long)buf.f_blocks
                                  * (unsigned long long)buf.f_frsize;
      unsigned long long available = (unsigned long long)buf.f_bavail
                                      * (unsigned long long)buf.f_frsize;

      if (total > 0)
        {
          double freePercent = ((double)available / (double)total) * 100.0;

          if (freePercent < 3.0)
            {
              NSAlert *alert = [[NSAlert alloc] init];
              [alert setMessageText: _(@"Low Disk Space")];
              [alert setInformativeText: [NSString stringWithFormat:
                _(@"The startup disk has less than 3%% free space.\n\n"
                  @"Only %.1f%% (%llu MB) available."),
                freePercent, available / (1024 * 1024)]];
              [alert setAlertStyle: NSWarningAlertStyle];
              [alert addButtonWithTitle: _(@"OK")];
              [alert runModal];
              [alert release];
            }
        }
    }

  checking = NO;
}

@end
