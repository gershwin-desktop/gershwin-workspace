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
 * FileManagerDBusInterface implements the org.freedesktop.FileManager1 DBus interface.
 * This interface allows applications to interact with the file manager for common operations
 * such as showing folders, selecting items, and displaying file properties.
 *
 * The interface is registered on the session bus at:
 * - Service: org.freedesktop.FileManager1
 * - Object Path: /org/freedesktop/FileManager1
 * - Interface: org.freedesktop.FileManager1
 */
@interface FileManagerDBusInterface : NSObject

@property (nonatomic, assign) Workspace *workspace;
@property (nonatomic, strong) GNUDBusConnection *dbusConnection;

/**
 * Initialize with a reference to the Workspace application.
 * @param workspace The Workspace application instance
 * @return Initialized interface object
 */
- (id)initWithWorkspace:(Workspace *)workspace;

/**
 * Register this interface on the DBus session bus.
 * @return YES if registration succeeded, NO otherwise
 */
- (BOOL)registerOnDBus;

/**
 * Handle incoming DBus method calls for the FileManager interface.
 * @param callInfo Dictionary containing message, path, interface, and method information
 */
- (void)handleDBusMethodCall:(NSDictionary *)callInfo;

/**
 * ShowFolders - Open file manager windows showing the contents of the specified folders.
 * @param uris Array of URI strings representing folder locations
 * @param startupId Startup notification ID (can be empty)
 */
- (void)showFolders:(NSArray *)uris startupId:(NSString *)startupId;

/**
 * ShowItems - Open file manager windows with the specified items selected within their parent folders.
 * @param uris Array of URI strings representing file/folder locations
 * @param startupId Startup notification ID (can be empty)
 */
- (void)showItems:(NSArray *)uris startupId:(NSString *)startupId;

/**
 * ShowItemProperties - Display a properties window for the specified items.
 * @param uris Array of URI strings representing file/folder locations
 * @param startupId Startup notification ID (can be empty)
 */
- (void)showItemProperties:(NSArray *)uris startupId:(NSString *)startupId;

@end
