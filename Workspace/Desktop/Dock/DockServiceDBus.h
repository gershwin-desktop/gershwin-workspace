/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

#ifndef DOCKSERVICEDBUS_H
#define DOCKSERVICEDBUS_H

#import <Foundation/Foundation.h>

@class GNUDBusConnection;
@class Dock;

@interface DockServiceDBus : NSObject
{
  NSTimer *processTimer;
}

@property (nonatomic, assign) Dock *dock;
@property (nonatomic, strong) GNUDBusConnection *dbusConnection;

- (id)initWithDock:(Dock *)dock;
- (BOOL)registerOnDBus;
- (void)handleDBusMethodCall:(NSDictionary *)callInfo;

@end

#endif
