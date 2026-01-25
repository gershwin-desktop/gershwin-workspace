/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "FileManagerDBusInterface.h"
#import "DBusConnection.h"
#import "Workspace.h"
#import <dbus/dbus.h>
#import "../FSNode/FSNode.h"
#import "FileViewer/GWViewersManager.h"
#import "Desktop/GWDesktopManager.h"
#import <dispatch/dispatch.h>
#include <unistd.h>
#include <string.h>
#include <stdlib.h>

// Use typedef to avoid naming conflicts
typedef struct DBusConnection DBusConnectionStruct;

@implementation FileManagerDBusInterface

- (id)initWithWorkspace:(Workspace *)workspace
{
    self = [super init];
    if (self) {
        self.workspace = workspace;
        self.dbusConnection = [GNUDBusConnection sessionBus];
    }
    return self;
}

- (void)dealloc
{
    self.workspace = nil;
    self.dbusConnection = nil;
    [super dealloc];
}

- (BOOL)registerOnDBus
{
    if (!self.dbusConnection || ![self.dbusConnection isConnected]) {
        NSLog(@"FileManagerDBusInterface: Cannot register - DBus not connected");
        return NO;
    }
    
    // Register the org.freedesktop.FileManager1 service name
    BOOL serviceRegistered = [self.dbusConnection registerService:@"org.freedesktop.FileManager1"];
    if (!serviceRegistered) {
        NSLog(@"FileManagerDBusInterface: Failed to register org.freedesktop.FileManager1 service");
        return NO;
    }
    
    // Register the object path /org/freedesktop/FileManager1
    BOOL objectRegistered = [self.dbusConnection registerObjectPath:@"/org/freedesktop/FileManager1"
                                                          interface:@"org.freedesktop.FileManager1"
                                                            handler:self];
    if (!objectRegistered) {
        NSLog(@"FileManagerDBusInterface: Failed to register object path");
        return NO;
    }
    
    NSLog(@"FileManagerDBusInterface: Successfully registered org.freedesktop.FileManager1 on DBus");
    return YES;
}

- (void)handleDBusMethodCall:(NSDictionary *)callInfo
{
    NSValue *messageValue = [callInfo objectForKey:@"message"];
    NSString *method = [callInfo objectForKey:@"method"];
    NSString *path = [callInfo objectForKey:@"path"];
    NSString *interface = [callInfo objectForKey:@"interface"];
    
    NSLog(@"FileManagerDBusInterface: handleDBusMethodCall invoked");
    NSLog(@"  Path: %@", path);
    NSLog(@"  Interface: %@", interface);
    NSLog(@"  Method: %@", method);
    
    if (!messageValue || !method) {
        NSLog(@"FileManagerDBusInterface: Invalid method call info");
        return;
    }
    
    DBusMessage *message = (DBusMessage *)[messageValue pointerValue];
    
    // Parse method arguments
    DBusMessageIter iter;
    if (!dbus_message_iter_init(message, &iter)) {
        NSLog(@"FileManagerDBusInterface: Method %@ called with no arguments", method);
        [self sendEmptyReply:message];
        return;
    }
    
    // First argument: array of URIs (as)
    if (dbus_message_iter_get_arg_type(&iter) != DBUS_TYPE_ARRAY) {
        NSLog(@"FileManagerDBusInterface: Expected array of strings for URIs");
        [self sendErrorReply:message errorName:"org.freedesktop.DBus.Error.InvalidArgs"
                errorMessage:"Expected array of URI strings"];
        return;
    }
    
    DBusMessageIter arrayIter;
    dbus_message_iter_recurse(&iter, &arrayIter);
    
    NSMutableArray *uris = [NSMutableArray array];
    while (dbus_message_iter_get_arg_type(&arrayIter) == DBUS_TYPE_STRING) {
        char *uri;
        dbus_message_iter_get_basic(&arrayIter, &uri);
        if (uri) {
            [uris addObject:[NSString stringWithUTF8String:uri]];
        }
        dbus_message_iter_next(&arrayIter);
    }
    
    // Second argument: startup ID (s)
    dbus_message_iter_next(&iter);
    NSString *startupId = @"";
    if (dbus_message_iter_get_arg_type(&iter) == DBUS_TYPE_STRING) {
        char *sid;
        dbus_message_iter_get_basic(&iter, &sid);
        if (sid) {
            startupId = [NSString stringWithUTF8String:sid];
        }
    }
    
    NSLog(@"FileManagerDBusInterface: Method %@ called with %lu URIs, startupId='%@'",
          method, (unsigned long)[uris count], startupId);
    
    // Dispatch to appropriate handler
    if ([method isEqualToString:@"ShowFolders"]) {
        [self showFolders:uris startupId:startupId];
    } else if ([method isEqualToString:@"ShowItems"]) {
        [self showItems:uris startupId:startupId];
    } else if ([method isEqualToString:@"ShowItemProperties"]) {
        [self showItemProperties:uris startupId:startupId];
    } else {
        NSLog(@"FileManagerDBusInterface: Unknown method: %@", method);
        [self sendErrorReply:message errorName:"org.freedesktop.DBus.Error.UnknownMethod"
                errorMessage:[[NSString stringWithFormat:@"Unknown method: %@", method] UTF8String]];
        return;
    }
    
    // Send empty success reply
    [self sendEmptyReply:message];
}

- (NSString *)pathFromURI:(NSString *)uri
{
    // Per freedesktop.org file: URI standard:
    // file: URIs are "file://<hostname>/<path>" where hostname can be empty.
    // The unescaped byte string is NOT in a specified encoding and must
    // correspond exactly to the UNIX filename bytes.
    
    const char *cstr = [uri UTF8String];
    if (!cstr) {
        return nil;
    }
    
    // Handle file:// URIs (standard)
    if (strncmp(cstr, "file://", 7) == 0) {
        const char *afterScheme = cstr + 7;
        
        // Skip hostname if present - look for next '/'
        const char *pathStart = strchr(afterScheme, '/');
        if (!pathStart) {
            NSLog(@"FileManagerDBusInterface: Invalid file: URI (no path): %@", uri);
            return nil;
        }
        
        // Check hostname part (between // and /)
        size_t hostnameLen = pathStart - afterScheme;
        if (hostnameLen > 0) {
            // Hostname present - verify it's localhost or matches current host
            char hostname[256];
            if (hostnameLen < sizeof(hostname)) {
                memcpy(hostname, afterScheme, hostnameLen);
                hostname[hostnameLen] = '\0';
                
                char currentHost[256];
                if (gethostname(currentHost, sizeof(currentHost)) == 0) {
                    if (strcmp(hostname, "localhost") != 0 && strcmp(hostname, currentHost) != 0) {
                        NSLog(@"FileManagerDBusInterface: file: URI references remote host '%s', not local", hostname);
                        return nil;
                    }
                }
            }
        }
        
        // Decode percent-encoding WITHOUT assuming any encoding
        // This preserves the exact bytes as used in UNIX system calls
        return [self percentDecodePathBytes:pathStart];
    }
    
    // Handle file:/ URIs (backward compatibility - non-standard but common)
    if (strncmp(cstr, "file:/", 6) == 0 && cstr[6] != '/') {
        const char *pathStart = cstr + 5;  // Point to the '/' after "file:"
        return [self percentDecodePathBytes:pathStart];
    }
    
    // If it's already an absolute path, return it
    if ([uri hasPrefix:@"/"]) {
        return uri;
    }
    
    NSLog(@"FileManagerDBusInterface: Unsupported URI scheme: %@", uri);
    return nil;
}

- (NSString *)percentDecodePathBytes:(const char *)encodedPath
{
    // Decode percent-encoding while preserving exact byte values
    // Does NOT assume UTF-8 or any other encoding
    if (!encodedPath) {
        return nil;
    }
    
    size_t len = strlen(encodedPath);
    NSMutableData *data = [NSMutableData dataWithCapacity:len];
    
    for (size_t i = 0; i < len; i++) {
        if (encodedPath[i] == '%' && i + 2 < len) {
            // Decode hex sequence
            char hex[3] = { encodedPath[i+1], encodedPath[i+2], 0 };
            char *endptr;
            long byte = strtol(hex, &endptr, 16);
            if (endptr == hex + 2) {
                unsigned char b = (unsigned char)byte;
                [data appendBytes:&b length:1];
                i += 2;
                continue;
            }
        }
        // Copy literal byte
        unsigned char b = encodedPath[i];
        [data appendBytes:&b length:1];
    }
    
    // Create NSString from raw bytes using UTF-8 first (recommended for DBus)
    // Fallback to default C string encoding
    NSString *path = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (!path) {
        path = [[NSString alloc] initWithData:data 
                                       encoding:[NSString defaultCStringEncoding]];
    }
    
    return [path autorelease];
}

- (void)showFolders:(NSArray *)uris startupId:(NSString *)startupId
{
    NSLog(@"FileManagerDBusInterface: ShowFolders called with %lu URIs", (unsigned long)[uris count]);
    
    for (NSString *uri in uris) {
        NSString *path = [self pathFromURI:uri];
        if (!path) {
            NSLog(@"FileManagerDBusInterface: Skipping invalid URI: %@", uri);
            continue;
        }
        
        NSLog(@"FileManagerDBusInterface: Opening folder: %@", path);
        
        // Check if path exists and is a directory
        BOOL isDirectory;
        if (![[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&isDirectory]) {
            NSLog(@"FileManagerDBusInterface: Path does not exist: %@", path);
            continue;
        }
        
        if (!isDirectory) {
            NSLog(@"FileManagerDBusInterface: Path is not a directory: %@", path);
            continue;
        }
        
        // Open the folder in Workspace
        // Use the main thread to interact with the UI
        dispatch_async(dispatch_get_main_queue(), ^{
          [self openFolderOnMainThread:path];
        });
    }
}

- (void)openFolderOnMainThread:(NSString *)path
{
    @try {
        // Try to find the folder icon in the desktop, viewer, or Dock to animate from it
        GWViewersManager *vwrsManager = [self.workspace viewersManager];
        GWDesktopManager *dtopManager = [self.workspace desktopManager];
        BOOL foundIcon = NO;
        // Check if any viewer window has an icon for this path
        NSArray *viewerWindows = [vwrsManager viewerWindows];
        for (NSWindow *win in viewerWindows)
          {
            id viewer = [vwrsManager viewerWithWindow: win];
            if (viewer)
              {
                id vnodeView = [viewer nodeView];
                if (vnodeView && [vnodeView respondsToSelector: @selector(repOfSubnodePath:)])
                  {
                    id icon = [vnodeView repOfSubnodePath: path];
                    if (icon && [icon respondsToSelector: @selector(window)])
                      {
                        NSRect iconBounds = [icon bounds];
                        NSRect rectInWindow = [icon convertRect: iconBounds toView: nil];
                        NSRect rectOnScreen = [[icon window] convertRectToScreen: rectInWindow];
                        [vwrsManager setPendingOpenAnimationRect: rectOnScreen];
                        foundIcon = YES;
                        NSLog(@"FileManagerDBusInterface: Setting animation rect from viewer icon in window %@ at %@", 
                              [win title], NSStringFromRect(rectOnScreen));
                        break;
                      }
                  }
              }
          }
        
        // If not found in viewers, check the desktop
        if (!foundIcon && [dtopManager desktopView])
          {
            id desktopView = [dtopManager desktopView];
            if ([desktopView respondsToSelector: @selector(repOfSubnodePath:)])
              {
                id icon = [desktopView repOfSubnodePath: path];
                if (icon && [icon respondsToSelector: @selector(window)])
                  {
                    NSRect iconBounds = [icon bounds];
                    NSRect rectInWindow = [icon convertRect: iconBounds toView: nil];
                    NSRect rectOnScreen = [[icon window] convertRectToScreen: rectInWindow];
                    [vwrsManager setPendingOpenAnimationRect: rectOnScreen];
                    foundIcon = YES;
                    NSLog(@"FileManagerDBusInterface: Setting animation rect from desktop icon at %@", 
                          NSStringFromRect(rectOnScreen));
                  }
              }
          }
        
        // If we didn't find it in a viewer/desktop, check the Dock
        if (!foundIcon)
          {
            // Try to get the Dock
            id dock = [dtopManager valueForKey:@"dock"];
            if (dock)
              {
                // Get the icons array from the dock
                NSArray *dockIcons = [dock valueForKey:@"icons"];
                if (dockIcons)
                  {
                    for (id dockIcon in dockIcons)
                      {
                        // Get the node from the dock icon
                        id node = [dockIcon valueForKey:@"node"];
                        if (node)
                          {
                            NSString *nodePath = [node path];
                            if (nodePath && [nodePath isEqualToString:path])
                              {
                                // Found a matching dock icon!
                                if ([dockIcon respondsToSelector:@selector(bounds)] &&
                                    [dockIcon respondsToSelector:@selector(window)])
                                  {
                                    NSRect iconBounds = [dockIcon bounds];
                                    NSRect rectInWindow = [dockIcon convertRect:iconBounds toView:nil];
                                    NSRect rectOnScreen = [[dockIcon window] convertRectToScreen:rectInWindow];
                                    [vwrsManager setPendingOpenAnimationRect: rectOnScreen];
                                    foundIcon = YES;
                                    NSLog(@"FileManagerDBusInterface: Setting animation rect from Dock icon at %@",
                                          NSStringFromRect(rectOnScreen));
                                    break;
                                  }
                              }
                          }
                      }
                  }
              }
          }
        
        [self.workspace newViewerAtPath:path];
    } @catch (NSException *exception) {
        NSLog(@"FileManagerDBusInterface: Exception opening folder %@: %@", path, exception);
    }
}

- (void)showItems:(NSArray *)uris startupId:(NSString *)startupId
{
    NSLog(@"FileManagerDBusInterface: ShowItems called with %lu URIs", (unsigned long)[uris count]);
    
    NSMutableArray *paths = [NSMutableArray array];
    
    for (NSString *uri in uris) {
        NSString *path = [self pathFromURI:uri];
        if (!path) {
            NSLog(@"FileManagerDBusInterface: Skipping invalid URI: %@", uri);
            continue;
        }
        
        // Check if path exists
        if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
            NSLog(@"FileManagerDBusInterface: Path does not exist: %@", path);
            continue;
        }
        
        [paths addObject:path];
    }
    
    if ([paths count] == 0) {
        NSLog(@"FileManagerDBusInterface: No valid paths to show");
        return;
    }
    
    // For ShowItems, we need to:
    // 1. Open the parent directory
    // 2. Select the items within it
    
    // Group items by parent directory
    NSMutableDictionary *itemsByParent = [NSMutableDictionary dictionary];
    for (NSString *path in paths) {
        NSString *parentPath = [path stringByDeletingLastPathComponent];
        NSMutableArray *items = [itemsByParent objectForKey:parentPath];
        if (!items) {
            items = [NSMutableArray array];
            [itemsByParent setObject:items forKey:parentPath];
        }
        [items addObject:path];
    }
    
    // Open parent directories and select items
    dispatch_async(dispatch_get_main_queue(), ^{
      [self showItemsOnMainThread:itemsByParent];
    });
}

- (void)showItemsOnMainThread:(NSDictionary *)itemsByParent
{
    for (NSString *parentPath in itemsByParent) {
        NSArray *items = [itemsByParent objectForKey:parentPath];
        @try {
            // For each item, try to select them in an existing viewer; if that fails,
            // open the parent folder and retry, then fall back to root viewer selection
            NSLog(@"FileManagerDBusInterface: Selecting %lu files in viewer rooted at %@", 
                  (unsigned long)[items count], parentPath);

            // Verify parent exists and is a directory
            BOOL isDir = NO;
            if (![[NSFileManager defaultManager] fileExistsAtPath:parentPath isDirectory:&isDir] || !isDir) {
                NSLog(@"FileManagerDBusInterface: Parent path does not exist or is not a directory: %@", parentPath);
                continue;
            }

            BOOL success = [self.workspace selectFiles:items inFileViewerRootedAtPath:parentPath];
            if (!success) {
                NSLog(@"FileManagerDBusInterface: Initial select failed for %@, attempting to open viewer and retry", parentPath);

                // Open the parent folder in a new viewer and try again
                [self.workspace newViewerAtPath:parentPath];

                // Retry the selection
                success = [self.workspace selectFiles:items inFileViewerRootedAtPath:parentPath];
                if (success) {
                    NSLog(@"FileManagerDBusInterface: Selection succeeded after opening viewer at %@", parentPath);
                    continue;
                }

                // Try selecting in the root viewer as a further fallback
                NSLog(@"FileManagerDBusInterface: Retry select failed for %@; attempting root viewer selection", parentPath);
                [self.workspace rootViewerSelectFiles:items];

                // As a last resort set the selected paths directly (inspector/selection based fallbacks)
                [self.workspace setSelectedPaths:items];

                NSLog(@"FileManagerDBusInterface: Finished fallback sequence for %@", parentPath);
            }
        } @catch (NSException *exception) {
            NSLog(@"FileManagerDBusInterface: Exception showing items in %@: %@", 
                  parentPath, exception);
        }
    }
}

- (void)showItemProperties:(NSArray *)uris startupId:(NSString *)startupId
{
    NSLog(@"FileManagerDBusInterface: ShowItemProperties called with %lu URIs", 
          (unsigned long)[uris count]);
    
    NSMutableArray *paths = [NSMutableArray array];
    
    for (NSString *uri in uris) {
        NSString *path = [self pathFromURI:uri];
        if (!path) {
            NSLog(@"FileManagerDBusInterface: Skipping invalid URI: %@", uri);
            continue;
        }
        
        // Check if path exists
        if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
            NSLog(@"FileManagerDBusInterface: Path does not exist: %@", path);
            continue;
        }
        
        [paths addObject:path];
    }
    
    if ([paths count] == 0) {
        NSLog(@"FileManagerDBusInterface: No valid paths for properties");
        return;
    }
    
    // Show properties for the items using the Inspector
    dispatch_async(dispatch_get_main_queue(), ^{
      [self showPropertiesOnMainThread:paths];
    });
}

- (void)showPropertiesOnMainThread:(NSArray *)paths
{
    @try {
        // Set the selection to the items we want to show properties for
        [self.workspace setSelectedPaths:paths];
        
        // Activate the inspector to show properties
        // The inspector will automatically show info for the selected paths
        id inspector = [self.workspace valueForKey:@"inspector"];
        if (inspector && [inspector respondsToSelector:@selector(activate)]) {
            [inspector performSelector:@selector(activate)];
            
            // Show the attributes (properties) panel
            if ([inspector respondsToSelector:@selector(showAttributes)]) {
                [inspector performSelector:@selector(showAttributes)];
            }
        } else {
            NSLog(@"FileManagerDBusInterface: Inspector not available");
        }
    } @catch (NSException *exception) {
        NSLog(@"FileManagerDBusInterface: Exception showing properties: %@", exception);
    }
}

- (void)sendEmptyReply:(DBusMessage *)message
{
    NSLog(@"FileManagerDBusInterface: Sending empty reply");
    DBusMessage *reply = dbus_message_new_method_return(message);
    if (reply) {
        void *conn = [self.dbusConnection rawConnection];
        if (conn) {
            dbus_bool_t result = dbus_connection_send((DBusConnectionStruct *)conn, reply, NULL);
            NSLog(@"FileManagerDBusInterface: dbus_connection_send returned: %d", result);
            dbus_connection_flush((DBusConnectionStruct *)conn);
        } else {
            NSLog(@"FileManagerDBusInterface: Warning - could not get raw DBus connection");
        }
        dbus_message_unref(reply);
    } else {
        NSLog(@"FileManagerDBusInterface: Error - could not create method return");
    }
}

- (void)sendErrorReply:(DBusMessage *)message 
             errorName:(const char *)errorName 
          errorMessage:(const char *)errorMessage
{
    NSLog(@"FileManagerDBusInterface: Sending error reply: %s - %s", errorName, errorMessage);
    DBusMessage *reply = dbus_message_new_error(message, errorName, errorMessage);
    if (reply) {
        void *conn = [self.dbusConnection rawConnection];
        if (conn) {
            dbus_bool_t result = dbus_connection_send((DBusConnectionStruct *)conn, reply, NULL);
            NSLog(@"FileManagerDBusInterface: dbus_connection_send returned: %d", result);
            dbus_connection_flush((DBusConnectionStruct *)conn);
        } else {
            NSLog(@"FileManagerDBusInterface: Warning - could not get raw DBus connection");
        }
        dbus_message_unref(reply);
    } else {
        NSLog(@"FileManagerDBusInterface: Error - could not create error reply");
    }
}

@end
