/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-2.0-only
 */

#ifndef LOWDISKWARN_H
#define LOWDISKWARN_H

#import <Foundation/Foundation.h>

@interface LowDiskWarn : NSObject
{
  NSTimer *timer;
  BOOL checking;
}

- (void)startMonitoring;
- (void)stopMonitoring;

@end

#endif
