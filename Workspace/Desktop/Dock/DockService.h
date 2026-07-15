/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

#ifndef DOCKSERVICE_H
#define DOCKSERVICE_H

#import <Foundation/NSObject.h>

@class NSString;
@class NSDictionary;
@class DockIcon;

extern NSString * const kDockServiceName;
extern NSString * const kDockObjectPath;

@protocol DockService <NSObject>

- (void)update:(NSString *)appUri properties:(NSDictionary *)properties;
- (NSDictionary *)query;

@end

void DockServiceStart(id dock);
void DockServiceStop(void);

NSString *DockServiceAppNameFromUri(NSString *appUri);
void DockServiceApplyProperties(NSDictionary *properties, DockIcon *icon);

#if HAVE_DBUS
void DockServiceDBusStart(id dock);
void DockServiceDBusStop(void);
#endif

#endif
