/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>

@class GNUDBusConnection;
@class Workspace;

/**
 * FileChooserDBusInterface implements the org.freedesktop.portal.FileChooser DBus interface.
 * This interface allows non-GNUstep applications to open GNUstep native file dialogs.
 *
 * The interface is registered on the session bus at:
 * - Service: org.freedesktop.portal.Desktop
 * - Object Path: /org/freedesktop/portal/desktop
 * - Interface: org.freedesktop.portal.FileChooser
 */
@interface FileChooserDBusInterface : NSObject

@property (nonatomic, assign) Workspace *workspace;
@property (nonatomic, strong) GNUDBusConnection *dbusConnection;

- (id)initWithWorkspace:(Workspace *)workspace;
- (BOOL)registerOnDBus;
- (void)handleDBusMethodCall:(NSDictionary *)callInfo;

@end
