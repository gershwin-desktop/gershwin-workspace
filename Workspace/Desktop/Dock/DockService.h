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

/* oneway: callers must never wait for the Dock.  The WindowManager reports
 * its progress through this service, and while it waited for a reply it
 * stopped drawing the screen. */
@protocol DockService <NSObject>

- (oneway void)setBadgeCount:(int64_t)count;
- (oneway void)setCountVisible:(BOOL)visible;
- (oneway void)setProgressValue:(double)value;
- (oneway void)setProgressVisible:(BOOL)visible;
- (oneway void)setUrgent:(BOOL)urgent;
- (oneway void)clearAll;

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
