/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "FileChooserDBusInterface.h"
#import "DBusConnection.h"
#import "Workspace.h"
#import <dbus/dbus.h>

// Use typedef to avoid naming conflicts
typedef struct DBusConnection DBusConnectionStruct;

@implementation FileChooserDBusInterface

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
        NSLog(@"FileChooserDBusInterface: Cannot register - DBus not connected");
        return NO;
    }

    BOOL serviceRegistered = [self.dbusConnection registerService:@"org.freedesktop.portal.Desktop"];
    if (!serviceRegistered) {
        NSLog(@"FileChooserDBusInterface: Failed to register org.freedesktop.portal.Desktop service");
        return NO;
    }

    BOOL objectRegistered = [self.dbusConnection registerObjectPath:@"/org/freedesktop/portal/desktop"
                                                          interface:@"org.freedesktop.portal.FileChooser"
                                                            handler:self];
    if (!objectRegistered) {
        NSLog(@"FileChooserDBusInterface: Failed to register file chooser object path");
        return NO;
    }

    NSLog(@"FileChooserDBusInterface: Successfully registered FileChooser portal on DBus");
    return YES;
}

- (void)handleDBusMethodCall:(NSDictionary *)callInfo
{
    NSValue *messageValue = [callInfo objectForKey:@"message"];
    NSString *method = [callInfo objectForKey:@"method"];

    if (!messageValue || !method) {
        NSLog(@"FileChooserDBusInterface: Invalid method call info");
        return;
    }

    DBusMessage *message = (DBusMessage *)[messageValue pointerValue];

    NSString *parentWindow = nil;
    NSString *title = nil;
    NSDictionary *options = [NSDictionary dictionary];

    DBusMessageIter iter;
    if (dbus_message_iter_init(message, &iter)) {
        parentWindow = [self stringFromIterator:&iter];
        if (dbus_message_iter_next(&iter)) {
            title = [self stringFromIterator:&iter];
        }
        if (dbus_message_iter_next(&iter)) {
            options = [self optionsFromIterator:&iter];
        }
    }

    if (![method isEqualToString:@"OpenFile"] &&
        ![method isEqualToString:@"SaveFile"] &&
        ![method isEqualToString:@"SaveFiles"]) {
        [self sendErrorReply:message
                   errorName:"org.freedesktop.DBus.Error.UnknownMethod"
                errorMessage:[[NSString stringWithFormat:@"Unknown method: %@", method] UTF8String]];
        return;
    }

    NSString *requestPath = [self requestPathForMessage:message options:options];
    if (![self sendHandleReply:message requestPath:requestPath]) {
        return;
    }

    [self handleFileChooserRequest:method
                       parentWindow:parentWindow
                              title:title
                            options:options
                        requestPath:requestPath];
}

- (NSString *)stringFromIterator:(DBusMessageIter *)iter
{
    if (dbus_message_iter_get_arg_type(iter) != DBUS_TYPE_STRING) {
        return nil;
    }
    char *value = NULL;
    dbus_message_iter_get_basic(iter, &value);
    if (!value) {
        return nil;
    }
    return [NSString stringWithUTF8String:value];
}

- (NSDictionary *)optionsFromIterator:(DBusMessageIter *)iter
{
    NSMutableDictionary *options = [NSMutableDictionary dictionary];

    if (dbus_message_iter_get_arg_type(iter) != DBUS_TYPE_ARRAY) {
        return options;
    }

    DBusMessageIter arrayIter;
    dbus_message_iter_recurse(iter, &arrayIter);

    while (dbus_message_iter_get_arg_type(&arrayIter) == DBUS_TYPE_DICT_ENTRY) {
        DBusMessageIter dictIter;
        dbus_message_iter_recurse(&arrayIter, &dictIter);

        NSString *key = nil;
        if (dbus_message_iter_get_arg_type(&dictIter) == DBUS_TYPE_STRING) {
            char *keyValue = NULL;
            dbus_message_iter_get_basic(&dictIter, &keyValue);
            if (keyValue) {
                key = [NSString stringWithUTF8String:keyValue];
            }
        }

        if (key && dbus_message_iter_next(&dictIter) &&
            dbus_message_iter_get_arg_type(&dictIter) == DBUS_TYPE_VARIANT) {
            DBusMessageIter variantIter;
            dbus_message_iter_recurse(&dictIter, &variantIter);
            id value = [self valueFromVariant:&variantIter];
            if (value) {
                [options setObject:value forKey:key];
            }
        }

        dbus_message_iter_next(&arrayIter);
    }

    return options;
}

- (id)valueFromVariant:(DBusMessageIter *)iter
{
    int type = dbus_message_iter_get_arg_type(iter);
    switch (type) {
        case DBUS_TYPE_STRING: {
            char *value = NULL;
            dbus_message_iter_get_basic(iter, &value);
            return value ? [NSString stringWithUTF8String:value] : nil;
        }
        case DBUS_TYPE_BOOLEAN: {
            dbus_bool_t value = FALSE;
            dbus_message_iter_get_basic(iter, &value);
            return [NSNumber numberWithBool:(value == TRUE)];
        }
        case DBUS_TYPE_UINT32: {
            dbus_uint32_t value = 0;
            dbus_message_iter_get_basic(iter, &value);
            return [NSNumber numberWithUnsignedInt:value];
        }
        case DBUS_TYPE_ARRAY: {
            int elementType = dbus_message_iter_get_element_type(iter);
            DBusMessageIter arrayIter;
            dbus_message_iter_recurse(iter, &arrayIter);

            if (elementType == DBUS_TYPE_BYTE) {
                NSMutableData *data = [NSMutableData data];
                while (dbus_message_iter_get_arg_type(&arrayIter) == DBUS_TYPE_BYTE) {
                    unsigned char byte = 0;
                    dbus_message_iter_get_basic(&arrayIter, &byte);
                    [data appendBytes:&byte length:1];
                    dbus_message_iter_next(&arrayIter);
                }
                return data;
            }

            NSMutableArray *array = [NSMutableArray array];
            while (dbus_message_iter_get_arg_type(&arrayIter) != DBUS_TYPE_INVALID) {
                id value = [self valueFromVariant:&arrayIter];
                if (value) {
                    [array addObject:value];
                }
                dbus_message_iter_next(&arrayIter);
            }
            return array;
        }
        case DBUS_TYPE_OBJECT_PATH: {
            char *value = NULL;
            dbus_message_iter_get_basic(iter, &value);
            return value ? [NSString stringWithUTF8String:value] : nil;
        }
        default:
            return nil;
    }
}

- (NSString *)requestPathForMessage:(DBusMessage *)message options:(NSDictionary *)options
{
    NSString *token = [options objectForKey:@"handle_token"];
    if (![token isKindOfClass:[NSString class]] || [token length] == 0) {
        token = [[NSProcessInfo processInfo] globallyUniqueString];
    }

    const char *sender = dbus_message_get_sender(message);
    NSString *senderString = sender ? [NSString stringWithUTF8String:sender] : @"unknown";
    NSMutableString *safeSender = [senderString mutableCopy];
    if ([safeSender hasPrefix:@":"]) {
        [safeSender deleteCharactersInRange:NSMakeRange(0, 1)];
    }
    [safeSender replaceOccurrencesOfString:@"."
                                 withString:@"_"
                                    options:0
                                      range:NSMakeRange(0, [safeSender length])];
    [safeSender replaceOccurrencesOfString:@":"
                                 withString:@"_"
                                    options:0
                                      range:NSMakeRange(0, [safeSender length])];

    NSString *path = [NSString stringWithFormat:@"/org/freedesktop/portal/desktop/request/%@/%@", safeSender, token];
    [safeSender release];
    return path;
}

- (void)handleFileChooserRequest:(NSString *)method
                     parentWindow:(NSString *)parentWindow
                            title:(NSString *)title
                          options:(NSDictionary *)options
                      requestPath:(NSString *)requestPath
{
    BOOL isSave = [method hasPrefix:@"Save"];
    BOOL allowMultiple = [[options objectForKey:@"multiple"] boolValue];
    BOOL chooseDirectory = [[options objectForKey:@"directory"] boolValue];

    NSString *currentName = [options objectForKey:@"current_name"];
    if (![currentName isKindOfClass:[NSString class]]) {
        currentName = nil;
    }

    NSString *acceptLabel = [options objectForKey:@"accept_label"];
    if (![acceptLabel isKindOfClass:[NSString class]]) {
        acceptLabel = nil;
    }

    NSString *currentFolder = [self pathFromOptionValue:[options objectForKey:@"current_folder"]];
    NSString *currentFile = [self pathFromOptionValue:[options objectForKey:@"current_file"]];
    if (!currentFolder && [currentFile length] > 0) {
        currentFolder = [currentFile stringByDeletingLastPathComponent];
    }
    if (!currentName && isSave && [currentFile length] > 0) {
        currentName = [currentFile lastPathComponent];
    }

    NSArray *selectedPaths = nil;
    if (isSave) {
        selectedPaths = [self runSavePanelWithTitle:title
                                       acceptLabel:acceptLabel
                                      currentFolder:currentFolder
                                        currentName:currentName];
    } else {
        selectedPaths = [self runOpenPanelWithTitle:title
                                       acceptLabel:acceptLabel
                                      currentFolder:currentFolder
                                     allowMultiple:allowMultiple
                                    chooseDirectory:chooseDirectory];
    }

    BOOL cancelled = (selectedPaths == nil);
    NSArray *uris = cancelled ? nil : [self urisFromPaths:selectedPaths];
    [self sendResponseForRequestPath:requestPath cancelled:cancelled uris:uris parentWindow:parentWindow];
}

- (NSString *)pathFromOptionValue:(id)value
{
    if (!value) {
        return nil;
    }

    if ([value isKindOfClass:[NSData class]]) {
        NSData *data = (NSData *)value;
        if ([data length] == 0) {
            return nil;
        }
        return [[NSFileManager defaultManager] stringWithFileSystemRepresentation:(const char *)[data bytes]
                                                                           length:[data length]];
    }

    if ([value isKindOfClass:[NSString class]]) {
        return (NSString *)value;
    }

    return nil;
}

- (NSArray *)runOpenPanelWithTitle:(NSString *)title
                       acceptLabel:(NSString *)acceptLabel
                      currentFolder:(NSString *)currentFolder
                     allowMultiple:(BOOL)allowMultiple
                    chooseDirectory:(BOOL)chooseDirectory
{
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    if ([title length] > 0) {
        [panel setTitle:title];
    }
    if ([acceptLabel length] > 0 && [panel respondsToSelector:@selector(setPrompt:)]) {
        [panel setPrompt:acceptLabel];
    }

    [panel setAllowsMultipleSelection:allowMultiple];
    [panel setCanChooseDirectories:chooseDirectory];
    [panel setCanChooseFiles:!chooseDirectory];

    NSInteger result = [panel runModalForDirectory:currentFolder file:nil types:nil];
    if (result != NSOKButton) {
        return nil;
    }

    if (allowMultiple) {
        return [panel filenames];
    }

    NSString *filename = [panel filename];
    if (!filename) {
        return nil;
    }
    return [NSArray arrayWithObject:filename];
}

- (NSArray *)runSavePanelWithTitle:(NSString *)title
                       acceptLabel:(NSString *)acceptLabel
                      currentFolder:(NSString *)currentFolder
                        currentName:(NSString *)currentName
{
    NSSavePanel *panel = [NSSavePanel savePanel];
    if ([title length] > 0) {
        [panel setTitle:title];
    }
    if ([acceptLabel length] > 0 && [panel respondsToSelector:@selector(setPrompt:)]) {
        [panel setPrompt:acceptLabel];
    }

    NSInteger result = [panel runModalForDirectory:currentFolder file:currentName];
    if (result != NSOKButton) {
        return nil;
    }

    NSString *filename = [panel filename];
    if (!filename) {
        return nil;
    }
    return [NSArray arrayWithObject:filename];
}

- (NSArray *)urisFromPaths:(NSArray *)paths
{
    NSMutableArray *uris = [NSMutableArray arrayWithCapacity:[paths count]];
    for (NSString *path in paths) {
        if (![path isKindOfClass:[NSString class]]) {
            continue;
        }
        NSURL *url = [NSURL fileURLWithPath:path];
        if (url) {
            [uris addObject:[url absoluteString]];
        }
    }
    return uris;
}

- (BOOL)sendHandleReply:(DBusMessage *)message requestPath:(NSString *)requestPath
{
    if (!requestPath) {
        return NO;
    }

    DBusMessage *reply = dbus_message_new_method_return(message);
    if (!reply) {
        return NO;
    }

    const char *path = [requestPath UTF8String];
    dbus_message_append_args(reply, DBUS_TYPE_OBJECT_PATH, &path, DBUS_TYPE_INVALID);

    void *conn = [self.dbusConnection rawConnection];
    if (conn) {
        dbus_connection_send((DBusConnectionStruct *)conn, reply, NULL);
        dbus_connection_flush((DBusConnectionStruct *)conn);
    }

    dbus_message_unref(reply);
    return YES;
}

- (void)sendResponseForRequestPath:(NSString *)requestPath
                         cancelled:(BOOL)cancelled
                              uris:(NSArray *)uris
                      parentWindow:(NSString *)parentWindow
{
    (void)parentWindow;
    if (!requestPath) {
        return;
    }

    DBusMessage *signal = dbus_message_new_signal([requestPath UTF8String],
                                                  "org.freedesktop.portal.Request",
                                                  "Response");
    if (!signal) {
        return;
    }

    DBusMessageIter iter;
    dbus_message_iter_init_append(signal, &iter);

    dbus_uint32_t responseCode = cancelled ? 1 : 0;
    dbus_message_iter_append_basic(&iter, DBUS_TYPE_UINT32, &responseCode);

    DBusMessageIter dictIter;
    dbus_message_iter_open_container(&iter, DBUS_TYPE_ARRAY, "{sv}", &dictIter);

    if (!cancelled && [uris count] > 0) {
        DBusMessageIter entryIter;
        dbus_message_iter_open_container(&dictIter, DBUS_TYPE_DICT_ENTRY, NULL, &entryIter);

        const char *key = "uris";
        dbus_message_iter_append_basic(&entryIter, DBUS_TYPE_STRING, &key);

        DBusMessageIter variantIter;
        dbus_message_iter_open_container(&entryIter, DBUS_TYPE_VARIANT, "as", &variantIter);

        DBusMessageIter arrayIter;
        dbus_message_iter_open_container(&variantIter, DBUS_TYPE_ARRAY, "s", &arrayIter);

        for (NSString *uri in uris) {
            const char *uriStr = [uri UTF8String];
            dbus_message_iter_append_basic(&arrayIter, DBUS_TYPE_STRING, &uriStr);
        }

        dbus_message_iter_close_container(&variantIter, &arrayIter);
        dbus_message_iter_close_container(&entryIter, &variantIter);
        dbus_message_iter_close_container(&dictIter, &entryIter);
    }

    dbus_message_iter_close_container(&iter, &dictIter);

    void *conn = [self.dbusConnection rawConnection];
    if (conn) {
        dbus_connection_send((DBusConnectionStruct *)conn, signal, NULL);
        dbus_connection_flush((DBusConnectionStruct *)conn);
    }

    dbus_message_unref(signal);
}

- (void)sendErrorReply:(DBusMessage *)message
             errorName:(const char *)errorName
          errorMessage:(const char *)errorMessage
{
    DBusMessage *reply = dbus_message_new_error(message, errorName, errorMessage);
    if (reply) {
        void *conn = [self.dbusConnection rawConnection];
        if (conn) {
            dbus_connection_send((DBusConnectionStruct *)conn, reply, NULL);
            dbus_connection_flush((DBusConnectionStruct *)conn);
        }
        dbus_message_unref(reply);
    }
}

@end
