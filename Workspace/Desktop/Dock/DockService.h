/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

#ifndef DOCKSERVICE_H
#define DOCKSERVICE_H

#import <Foundation/NSObject.h>

@class NSString;
@class DockIcon;

extern NSString * const kDockServiceName;

@protocol DockService <NSObject>

- (void)registerAppWithName:(NSString *)appName;
- (void)setBadgeCount:(int64_t)count;
- (void)setCountVisible:(BOOL)visible;
- (void)setProgressValue:(double)value;
- (void)setProgressVisible:(BOOL)visible;
- (void)setUrgent:(BOOL)urgent;
- (void)clearAll;

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
