/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */


#import "DBusConnection.h"
#import <dbus/dbus.h>
#import <sys/select.h>
#import <unistd.h>

// Use typedef to avoid naming conflicts
typedef struct DBusConnection DBusConnectionStruct;

// C callback for libdbus message filter
static DBusHandlerResult dbusMessageFilterHandler(DBusConnection *connection,
                                                   DBusMessage *message,
                                                   void *user_data)
{
    @autoreleasepool {
        GNUDBusConnection *self = (__bridge GNUDBusConnection *)user_data;
        if (self) {
            int msgType = dbus_message_get_type(message);
            
            // Only handle method calls
            if (msgType == DBUS_MESSAGE_TYPE_METHOD_CALL) {
                const char *path = dbus_message_get_path(message);
                const char *interface = dbus_message_get_interface(message);
                const char *member = dbus_message_get_member(message);
                NSDebugLog(@"DBusConnection: Filter handler invoked for %s.%s on %s", 
                      interface ? interface : "(null)", 
                      member ? member : "(null)", 
                      path ? path : "(null)");
                
                // Check if we have a handler for this path/interface
                if (path && interface) {
                    NSString *pathStr = [NSString stringWithUTF8String:path];
                    NSString *interfaceStr = [NSString stringWithUTF8String:interface];
                    NSString *key = [NSString stringWithFormat:@"%@:%@", pathStr, interfaceStr];
                    
                    id handler = [self.messageHandlers objectForKey:key];
                    if (handler) {
                        NSLog(@"DBusConnection: Found handler for %@, calling handleIncomingMessage", key);
                        [self handleIncomingMessage:message];
                        return DBUS_HANDLER_RESULT_HANDLED;
                    }
                }
            }
        }
    }
    return DBUS_HANDLER_RESULT_NOT_YET_HANDLED;
}

// C callback for libdbus object path message handler (not currently used)
static DBusHandlerResult dbusObjectPathMessageHandler(DBusConnection *connection,
                                                       DBusMessage *message,
                                                       void *user_data)
{
    @autoreleasepool {
        GNUDBusConnection *self = (__bridge GNUDBusConnection *)user_data;
        if (self) {
            const char *path = dbus_message_get_path(message);
            const char *interface = dbus_message_get_interface(message);
            const char *member = dbus_message_get_member(message);
            NSLog(@"DBusConnection: C callback invoked for %s.%s on %s", 
                  interface ? interface : "(null)", 
                  member ? member : "(null)", 
                  path ? path : "(null)");
            
            [self handleIncomingMessage:message];
            // Return HANDLED to prevent the default handler from sending UnknownObject error
            return DBUS_HANDLER_RESULT_HANDLED;
        }
        NSLog(@"DBusConnection: C callback invoked but self is NULL!");
    }
    return DBUS_HANDLER_RESULT_NOT_YET_HANDLED;
}

// Forward declaration for internal method
@interface GNUDBusConnection (Private)
- (id)parseDBusMessageIterator:(DBusMessageIter *)iter;
@end

@implementation GNUDBusConnection

+ (GNUDBusConnection *)sessionBus
{
    static GNUDBusConnection *sharedSessionBus = nil;
    @synchronized(self) {
        if (!sharedSessionBus) {
            sharedSessionBus = [[GNUDBusConnection alloc] init];
            [sharedSessionBus connect];
        }
    }
    return sharedSessionBus;
}

- (id)init
{
    self = [super init];
    if (self) {
        self.connection = NULL;
        self.connected = NO;
        self.messageHandlers = [[NSMutableDictionary alloc] init];
    }
    return self;
}

- (BOOL)connect
{
    DBusError error;
    dbus_error_init(&error);
    
    self.connection = dbus_bus_get(DBUS_BUS_SESSION, &error);
    if (dbus_error_is_set(&error)) {
        NSLog(@"DBusConnection: Failed to connect to session bus: %s", error.message);
        dbus_error_free(&error);
        return NO;
    }
    
    if (!self.connection) {
        NSLog(@"DBusConnection: Failed to get session bus connection");
        return NO;
    }
    
    // Add a message filter to intercept incoming method calls
    if (!dbus_connection_add_filter((DBusConnectionStruct *)self.connection,
                                    dbusMessageFilterHandler,
                                    (__bridge void *)self,
                                    NULL)) {
        NSLog(@"DBusConnection: Failed to add message filter");
        dbus_connection_unref((DBusConnectionStruct *)self.connection);
        self.connection = NULL;
        return NO;
    }
    
    NSLog(@"DBusConnection: Added message filter");
    
    self.connected = YES;
    // NSLog(@"DBusConnection: Successfully connected to session bus");
    return YES;
}

- (void)disconnect
{
    if (self.connection) {
        dbus_connection_unref((DBusConnectionStruct *)self.connection);
        self.connection = NULL;
    }
    self.connected = NO;
}

- (BOOL)isConnected
{
    return self.connected;
}

- (BOOL)registerService:(NSString *)serviceName
{
    if (!self.connected || !self.connection) {
        return NO;
    }
    
    DBusError error;
    dbus_error_init(&error);
    
    int result = dbus_bus_request_name((DBusConnectionStruct *)self.connection, 
                                      [serviceName UTF8String],
                                      DBUS_NAME_FLAG_REPLACE_EXISTING | DBUS_NAME_FLAG_ALLOW_REPLACEMENT,
                                      &error);
    
    if (dbus_error_is_set(&error)) {
        NSLog(@"DBusConnection: Failed to register service %@: %s", serviceName, error.message);
        dbus_error_free(&error);
        return NO;
    }
    
    if (result != DBUS_REQUEST_NAME_REPLY_PRIMARY_OWNER && 
        result != DBUS_REQUEST_NAME_REPLY_ALREADY_OWNER) {
        
        const char *resultStr = "unknown";
        switch (result) {
            case DBUS_REQUEST_NAME_REPLY_IN_QUEUE:
                resultStr = "IN_QUEUE (another service owns the name)";
                break;
            case DBUS_REQUEST_NAME_REPLY_EXISTS:
                resultStr = "EXISTS (name already exists and DBUS_NAME_FLAG_DO_NOT_QUEUE was specified)";
                break;
            default:
                resultStr = "unknown error";
                break;
        }
        
        NSLog(@"DBusConnection: Failed to become owner of service %@ (result: %d - %s)", serviceName, result, resultStr);
        NSLog(@"DBusConnection: Another application may already be providing the AppMenu.Registrar service");
        NSLog(@"DBusConnection: This is normal if multiple menu applications are running");
        return NO;
    }
    
    if (result == DBUS_REQUEST_NAME_REPLY_ALREADY_OWNER) {
        // NSLog(@"DBusConnection: Already owner of service: %@", serviceName);
    } else {
        // NSLog(@"DBusConnection: Successfully registered service: %@", serviceName);
    }
    return YES;
}

- (BOOL)registerObjectPath:(NSString *)objectPath 
                 interface:(NSString *)interfaceName 
                   handler:(id)handler
{
    if (!self.connected || !self.connection) {
        return NO;
    }
    
    // Store the handler for this object path
    NSString *key = [NSString stringWithFormat:@"%@:%@", objectPath, interfaceName];
    [self.messageHandlers setObject:handler forKey:key];
    
    // Register with libdbus so it knows to route messages to us
    // We use a C callback function that will call our handleIncomingMessage
    DBusObjectPathVTable vtable = {
        .unregister_function = NULL,
        .message_function = dbusObjectPathMessageHandler
    };
    
    DBusError error;
    dbus_error_init(&error);
    
    if (!dbus_connection_try_register_object_path((DBusConnectionStruct *)self.connection,
                                                   [objectPath UTF8String],
                                                   &vtable,
                                                   (__bridge void *)self,
                                                   &error)) {
        if (dbus_error_is_set(&error)) {
            NSLog(@"DBusConnection: Failed to register object path %@: %s", objectPath, error.message);
            dbus_error_free(&error);
        } else {
            NSLog(@"DBusConnection: Failed to register object path %@ (unknown error)", objectPath);
        }
        return NO;
    }
    
    NSLog(@"DBusConnection: Registered handler for %@ on %@", interfaceName, objectPath);
    return YES;
}

- (id)callMethod:(NSString *)method
      onService:(NSString *)serviceName
    objectPath:(NSString *)objectPath
     interface:(NSString *)interfaceName
     arguments:(NSArray *)arguments
{
    if (!self.connected || !self.connection) {
        NSLog(@"DBusConnection: Cannot call method - not connected");
        return nil;
    }
    
    // Validate inputs
    if (!method || !serviceName || !objectPath || !interfaceName) {
        NSLog(@"DBusConnection: Cannot call method - invalid parameters");
        return nil;
    }
    
    // Debug arguments array at entry point (logging removed)
    // NSLog(@"DBusConnection: callMethod entry - arguments array: %@", arguments);
    // NSLog(@"DBusConnection: callMethod entry - arguments count: %lu", (unsigned long)[arguments count]);
    
    DBusMessage *message = dbus_message_new_method_call([serviceName UTF8String],
                                                       [objectPath UTF8String],
                                                       [interfaceName UTF8String],
                                                       [method UTF8String]);
    if (!message) {
        NSLog(@"DBusConnection: Failed to create method call message");
        return nil;
    }
    
    // Add arguments if provided
    if (arguments && [arguments count] > 0) {
        DBusMessageIter iter;
        dbus_message_iter_init_append(message, &iter);
        
        for (NSUInteger argumentIndex = 0; argumentIndex < [arguments count]; argumentIndex++) {
            id argument = [arguments objectAtIndex:argumentIndex];
            // NSLog(@"DBusConnection: Processing argument[%lu]: %@ (class: %@)", (unsigned long)argumentIndex, argument, [argument class]);
            
            if ([argument isKindOfClass:[NSString class]]) {
                // Check if this is the third argument of an Event method call - should be variant
                if (argumentIndex == 2 && [method isEqualToString:@"Event"]) {
                    // NSLog(@"DBusConnection: Encoding 3rd argument of Event call as VARIANT containing string");
                    // Force third argument to be variant for DBus Event calls
                    DBusMessageIter variantIter;
                    dbus_message_iter_open_container(&iter, DBUS_TYPE_VARIANT, "s", &variantIter);
                    const char *str = [argument UTF8String];
                    dbus_message_iter_append_basic(&variantIter, DBUS_TYPE_STRING, &str);
                    dbus_message_iter_close_container(&iter, &variantIter);
                } else {
                    // NSLog(@"DBusConnection: Encoding as STRING");
                    const char *str = [argument UTF8String];
                    dbus_message_iter_append_basic(&iter, DBUS_TYPE_STRING, &str);
                }
            } else if ([argument isKindOfClass:[NSNull class]]) {
                // NSLog(@"DBusConnection: Encoding NSNull as VARIANT containing empty string");
                // Handle NSNull as an empty variant for DBus Event calls
                DBusMessageIter variantIter;
                dbus_message_iter_open_container(&iter, DBUS_TYPE_VARIANT, "s", &variantIter);
                const char *emptyStr = "";
                dbus_message_iter_append_basic(&variantIter, DBUS_TYPE_STRING, &emptyStr);
                dbus_message_iter_close_container(&iter, &variantIter);
            } else if ([argument isKindOfClass:[NSNumber class]]) {
                const char *objCType = [argument objCType];
                // NSLog(@"DBusConnection: Processing NSNumber with objCType: %s", objCType);
                // NSLog(@"DBusConnection: Comparisons - BOOL: %s, int: %s, long: %s, unsigned int: %s, unsigned long: %s", 
                //       @encode(BOOL), @encode(int), @encode(long), @encode(unsigned int), @encode(unsigned long));
                
                if (strcmp(objCType, @encode(BOOL)) == 0) {
                    // NSLog(@"DBusConnection: Encoding as BOOL");
                    dbus_bool_t val = [argument boolValue];
                    dbus_message_iter_append_basic(&iter, DBUS_TYPE_BOOLEAN, &val);
                } else if (strcmp(objCType, @encode(unsigned int)) == 0 ||
                          strcmp(objCType, @encode(unsigned long)) == 0) {
                    // NSLog(@"DBusConnection: Encoding as UINT32 (objCType matched unsigned)");
                    dbus_uint32_t val = [argument unsignedIntValue];
                    dbus_message_iter_append_basic(&iter, DBUS_TYPE_UINT32, &val);
                } else {
                    // Check if this is a timestamp parameter (4th argument in Event call)
                    // DBusMenu Event signature is (isvu) where the last parameter should be uint32
                    if (argumentIndex == 3 && [method isEqualToString:@"Event"]) {  // 4th argument (0-indexed) - timestamp should be uint32
                        // NSLog(@"DBusConnection: Encoding timestamp parameter as UINT32 (4th argument in Event call)");
                        dbus_uint32_t val = [argument unsignedIntValue];
                        dbus_message_iter_append_basic(&iter, DBUS_TYPE_UINT32, &val);
                    } else {
                        // Default to signed integer for other cases
                        // NSLog(@"DBusConnection: Encoding as INT32 (default for objCType: %s, argIndex: %lu)", objCType, (unsigned long)argumentIndex);
                        dbus_int32_t val = [argument intValue];
                        dbus_message_iter_append_basic(&iter, DBUS_TYPE_INT32, &val);
                    }
                }
            } else if ([argument isKindOfClass:[NSArray class]]) {
                // Handle array arguments - detect the type of the first element
                NSArray *array = (NSArray *)argument;
                if ([array count] > 0) {
                    id firstItem = [array objectAtIndex:0];
                    
                    if ([firstItem isKindOfClass:[NSString class]]) {
                        // String array
                        DBusMessageIter arrayIter;
                        dbus_message_iter_open_container(&iter, DBUS_TYPE_ARRAY, "s", &arrayIter);
                        
                        for (id item in array) {
                            if ([item isKindOfClass:[NSString class]]) {
                                const char *str = [item UTF8String];
                                dbus_message_iter_append_basic(&arrayIter, DBUS_TYPE_STRING, &str);
                            }
                        }
                        
                        dbus_message_iter_close_container(&iter, &arrayIter);
                    } else if ([firstItem isKindOfClass:[NSNumber class]]) {
                        // Number array - check if it's unsigned integers
                        DBusMessageIter arrayIter;
                        const char *objCType = [firstItem objCType];
                        
                        // Debug the objCType to understand what we're getting
                        // NSLog(@"DBusConnection: NSNumber objCType: %s (unsigned int: %s, unsigned long: %s)", 
                              // objCType, @encode(unsigned int), @encode(unsigned long));
                        
                        // Special case: For GTK Start method, we always want unsigned integers
                        // Check if this looks like a GTK method call by looking at the small positive values
                        BOOL forceUnsigned = NO;
                        if ([array count] > 0) {
                            NSNumber *firstNum = [array objectAtIndex:0];
                            if ([firstNum intValue] >= 0 && [firstNum intValue] < 1024) {
                                // Small positive integers are likely GTK subscription IDs
                                forceUnsigned = YES;
                            }
                        }
                        
                        if (strcmp(objCType, @encode(unsigned int)) == 0 ||
                            strcmp(objCType, @encode(unsigned long)) == 0 ||
                            forceUnsigned) {
                            // Unsigned integer array
                            // NSLog(@"DBusConnection: Creating unsigned integer array (au)");
                            dbus_message_iter_open_container(&iter, DBUS_TYPE_ARRAY, "u", &arrayIter);
                            
                            for (id item in array) {
                                if ([item isKindOfClass:[NSNumber class]]) {
                                    dbus_uint32_t val = [item unsignedIntValue];
                                    dbus_message_iter_append_basic(&arrayIter, DBUS_TYPE_UINT32, &val);
                                }
                            }
                            
                            dbus_message_iter_close_container(&iter, &arrayIter);
                        } else {
                            // Signed integer array (fallback)
                            // NSLog(@"DBusConnection: Creating signed integer array (ai) as fallback");
                            dbus_message_iter_open_container(&iter, DBUS_TYPE_ARRAY, "i", &arrayIter);
                            
                            for (id item in array) {
                                if ([item isKindOfClass:[NSNumber class]]) {
                                    dbus_int32_t val = [item intValue];
                                    dbus_message_iter_append_basic(&arrayIter, DBUS_TYPE_INT32, &val);
                                }
                            }
                            
                            dbus_message_iter_close_container(&iter, &arrayIter);
                        }
                    }
                } else {
                    // Empty array - default to string array
                    DBusMessageIter arrayIter;
                    dbus_message_iter_open_container(&iter, DBUS_TYPE_ARRAY, "s", &arrayIter);
                    dbus_message_iter_close_container(&iter, &arrayIter);
                }
            }
        }
    }
    
    // Send message and get reply
    DBusError error;
    dbus_error_init(&error);
    
    DBusMessage *reply = dbus_connection_send_with_reply_and_block((DBusConnectionStruct *)self.connection, 
                                                                  message, 250, &error);
    dbus_message_unref(message);
    
    if (dbus_error_is_set(&error)) {
        NSString *errorMsg = [NSString stringWithUTF8String:error.message ? error.message : "Unknown error"];
        NSLog(@"DBusConnection: Method call failed for %@.%@ on %@%@: %@", 
              interfaceName, method, serviceName, objectPath, errorMsg);
        dbus_error_free(&error);
        return nil;
    }
    
    if (!reply) {
        NSLog(@"DBusConnection: No reply received");
        return nil;
    }
    
    // Parse reply
    id result = nil;
    int messageType = dbus_message_get_type(reply);
    
    if (messageType == DBUS_MESSAGE_TYPE_METHOD_RETURN) {
        // For successful method returns, we default to success indicator
        result = @YES;  // Default success indicator for void methods
        
        DBusMessageIter iter;
        if (dbus_message_iter_init(reply, &iter)) {
            // Check if there are multiple return values
            NSMutableArray *multipleResults = [NSMutableArray array];
            
            do {
                int argType = dbus_message_iter_get_arg_type(&iter);
                if (argType == DBUS_TYPE_INVALID) {
                    break;
                }
                
                id value = [self parseDBusMessageIterator:&iter];
                if (value) {
                    [multipleResults addObject:value];
                }
            } while (dbus_message_iter_next(&iter));
            
            // If there are actual return values, use them instead of the default success indicator
            if ([multipleResults count] == 1) {
                result = [multipleResults objectAtIndex:0];
            } else if ([multipleResults count] > 1) {
                result = multipleResults;
            }
            // If count is 0, keep the default @YES success indicator
        }
    } else if (messageType == DBUS_MESSAGE_TYPE_ERROR) {
        // Handle error replies
        const char *errorName = dbus_message_get_error_name(reply);
        NSString *errorNameStr = errorName ? [NSString stringWithUTF8String:errorName] : @"Unknown";
        
        // Try to get error message from reply arguments
        NSString *errorMessage = @"";
        DBusMessageIter iter;
        if (dbus_message_iter_init(reply, &iter)) {
            int argType = dbus_message_iter_get_arg_type(&iter);
            if (argType == DBUS_TYPE_STRING) {
                char *str;
                dbus_message_iter_get_basic(&iter, &str);
                errorMessage = str ? [NSString stringWithUTF8String:str] : @"";
            }
        }
        
        NSLog(@"DBusConnection: Method call %@.%@ returned error '%@': %@", 
              interfaceName, method, errorNameStr, errorMessage);
        result = nil;
    } else {
        NSLog(@"DBusConnection: Unexpected message type %d for method call %@.%@", 
              messageType, interfaceName, method);
        result = nil;
    }
    
    dbus_message_unref(reply);
    
    // NSLog(@"DBusConnection: Method call %@.%@ completed", interfaceName, method);
    return result;
}

- (id)callGTKActivateMethod:(NSString *)actionName
                  parameter:(NSArray *)parameter
               platformData:(NSDictionary *)platformData
                  onService:(NSString *)serviceName
                 objectPath:(NSString *)objectPath
{
    if (!self.connected || !self.connection) {
        return nil;
    }
    
    // NSLog(@"DBusConnection: Creating GTK Activate method call for action: %@", actionName);
    
    DBusMessage *message = dbus_message_new_method_call([serviceName UTF8String],
                                                       [objectPath UTF8String],
                                                       "org.gtk.Actions",
                                                       "Activate");
    if (!message) {
        NSLog(@"DBusConnection: Failed to create GTK Activate method call");
        return nil;
    }
    
    // Build the method signature: Activate(s action_name, av parameter, a{sv} platform_data)
    DBusMessageIter iter, variantIter, dictIter;
    dbus_message_iter_init_append(message, &iter);
    
    // 1. Action name (string)
    const char *actionNameStr = [actionName UTF8String];
    dbus_message_iter_append_basic(&iter, DBUS_TYPE_STRING, &actionNameStr);
    
    // 2. Parameter array (av - array of variants)
    dbus_message_iter_open_container(&iter, DBUS_TYPE_ARRAY, "v", &variantIter);
    
    for (id param in parameter) {
        DBusMessageIter paramVariantIter;
        
        if ([param isKindOfClass:[NSNumber class]]) {
            // Wrap the parameter in a variant
            if (strcmp([param objCType], @encode(BOOL)) == 0) {
                dbus_message_iter_open_container(&variantIter, DBUS_TYPE_VARIANT, "b", &paramVariantIter);
                dbus_bool_t val = [param boolValue];
                dbus_message_iter_append_basic(&paramVariantIter, DBUS_TYPE_BOOLEAN, &val);
                dbus_message_iter_close_container(&variantIter, &paramVariantIter);
            } else {
                dbus_message_iter_open_container(&variantIter, DBUS_TYPE_VARIANT, "i", &paramVariantIter);
                dbus_int32_t val = [param intValue];
                dbus_message_iter_append_basic(&paramVariantIter, DBUS_TYPE_INT32, &val);
                dbus_message_iter_close_container(&variantIter, &paramVariantIter);
            }
        } else if ([param isKindOfClass:[NSString class]]) {
            dbus_message_iter_open_container(&variantIter, DBUS_TYPE_VARIANT, "s", &paramVariantIter);
            const char *str = [param UTF8String];
            dbus_message_iter_append_basic(&paramVariantIter, DBUS_TYPE_STRING, &str);
            dbus_message_iter_close_container(&variantIter, &paramVariantIter);
        }
    }
    
    dbus_message_iter_close_container(&iter, &variantIter);
    
    // 3. Platform data (a{sv} - array of dict entries with string keys and variant values)
    dbus_message_iter_open_container(&iter, DBUS_TYPE_ARRAY, "{sv}", &dictIter);
    
    for (NSString *key in platformData) {
        DBusMessageIter dictEntryIter, keyVariantIter;
        
        // Open dict entry {sv}
        dbus_message_iter_open_container(&dictIter, DBUS_TYPE_DICT_ENTRY, NULL, &dictEntryIter);
        
        // Add key (string)
        const char *keyStr = [key UTF8String];
        dbus_message_iter_append_basic(&dictEntryIter, DBUS_TYPE_STRING, &keyStr);
        
        // Add value (variant)
        id value = [platformData objectForKey:key];
        if ([value isKindOfClass:[NSString class]]) {
            dbus_message_iter_open_container(&dictEntryIter, DBUS_TYPE_VARIANT, "s", &keyVariantIter);
            const char *valueStr = [value UTF8String];
            dbus_message_iter_append_basic(&keyVariantIter, DBUS_TYPE_STRING, &valueStr);
            dbus_message_iter_close_container(&dictEntryIter, &keyVariantIter);
        } else if ([value isKindOfClass:[NSNumber class]]) {
            if (strcmp([value objCType], @encode(BOOL)) == 0) {
                dbus_message_iter_open_container(&dictEntryIter, DBUS_TYPE_VARIANT, "b", &keyVariantIter);
                dbus_bool_t val = [value boolValue];
                dbus_message_iter_append_basic(&keyVariantIter, DBUS_TYPE_BOOLEAN, &val);
                dbus_message_iter_close_container(&dictEntryIter, &keyVariantIter);
            } else {
                dbus_message_iter_open_container(&dictEntryIter, DBUS_TYPE_VARIANT, "i", &keyVariantIter);
                dbus_int32_t val = [value intValue];
                dbus_message_iter_append_basic(&keyVariantIter, DBUS_TYPE_INT32, &val);
                dbus_message_iter_close_container(&dictEntryIter, &keyVariantIter);
            }
        }
        
        dbus_message_iter_close_container(&dictIter, &dictEntryIter);
    }
    
    dbus_message_iter_close_container(&iter, &dictIter);
    
    // Send message and get reply
    DBusError error;
    dbus_error_init(&error);
    
    DBusMessage *reply = dbus_connection_send_with_reply_and_block((DBusConnectionStruct *)self.connection, 
                                                                  message, 250, &error);
    dbus_message_unref(message);
    
    if (dbus_error_is_set(&error)) {
        NSLog(@"DBusConnection: GTK Activate call failed for %@ on %@%@: %s", 
              actionName, serviceName, objectPath, error.message);
        dbus_error_free(&error);
        return nil;
    }
    
    if (!reply) {
        NSLog(@"DBusConnection: No reply received for GTK Activate call");
        return nil;
    }
    
    // NSLog(@"DBusConnection: GTK Activate call succeeded for action: %@", actionName);
    dbus_message_unref(reply);
    return @YES;
}

- (id)parseDBusMessageIterator:(DBusMessageIter *)iter
{
    int argType = dbus_message_iter_get_arg_type(iter);
    
    switch (argType) {
        case DBUS_TYPE_INVALID:
            NSLog(@"DBusConnection: Invalid DBus type encountered");
            return nil;
            
        case DBUS_TYPE_STRING: {
            char *str;
            dbus_message_iter_get_basic(iter, &str);
            NSString *result = [NSString stringWithUTF8String:str ? str : ""];
            return result;
        }
        
        case DBUS_TYPE_INT32: {
            dbus_int32_t val;
            dbus_message_iter_get_basic(iter, &val);
            NSNumber *result = [NSNumber numberWithInt:val];
            // NSLog(@"DBusConnection: Parsed int32: %@", result);
            return result;
        }
        
        case DBUS_TYPE_UINT32: {
            dbus_uint32_t val;
            dbus_message_iter_get_basic(iter, &val);
            NSNumber *result = [NSNumber numberWithUnsignedInt:val];
            // NSLog(@"DBusConnection: Parsed uint32: %@", result);
            return result;
        }
        
        case DBUS_TYPE_BOOLEAN: {
            dbus_bool_t val;
            dbus_message_iter_get_basic(iter, &val);
            NSNumber *result = [NSNumber numberWithBool:(val == TRUE)];
            // NSLog(@"DBusConnection: Parsed boolean: %@", result);
            return result;
        }
        
        case DBUS_TYPE_DOUBLE: {
            double val;
            dbus_message_iter_get_basic(iter, &val);
            NSNumber *result = [NSNumber numberWithDouble:val];
            // NSLog(@"DBusConnection: Parsed double: %@", result);
            return result;
        }
        
        case DBUS_TYPE_OBJECT_PATH: {
            char *path;
            dbus_message_iter_get_basic(iter, &path);
            NSString *result = [NSString stringWithUTF8String:path ? path : ""];
            // NSLog(@"DBusConnection: Parsed object path: '%@'", result);
            return result;
        }
        
        case DBUS_TYPE_SIGNATURE: {
            char *sig;
            dbus_message_iter_get_basic(iter, &sig);
            NSString *result = [NSString stringWithUTF8String:sig ? sig : ""];
            // NSLog(@"DBusConnection: Parsed signature: '%@'", result);
            return result;
        }
        
        case DBUS_TYPE_ARRAY: {
            // NSLog(@"DBusConnection: Parsing array");
            DBusMessageIter subIter;
            dbus_message_iter_recurse(iter, &subIter);
            
            NSMutableArray *array = [NSMutableArray array];
            do {
                int subType = dbus_message_iter_get_arg_type(&subIter);
                if (subType == DBUS_TYPE_INVALID) {
                    break;
                }
                
                id value = [self parseDBusMessageIterator:&subIter];
                if (value) {
                    [array addObject:value];
                }
            } while (dbus_message_iter_next(&subIter));
            
            // NSLog(@"DBusConnection: Parsed array with %lu elements", (unsigned long)[array count]);
            return array;
        }
        
        case DBUS_TYPE_STRUCT: {
            // NSLog(@"DBusConnection: Parsing struct");
            DBusMessageIter subIter;
            dbus_message_iter_recurse(iter, &subIter);
            
            NSMutableArray *structArray = [NSMutableArray array];
            do {
                int subType = dbus_message_iter_get_arg_type(&subIter);
                if (subType == DBUS_TYPE_INVALID) {
                    break;
                }
                
                id value = [self parseDBusMessageIterator:&subIter];
                if (value) {
                    [structArray addObject:value];
                } else {
                    [structArray addObject:[NSNull null]];
                }
            } while (dbus_message_iter_next(&subIter));
            
            // NSLog(@"DBusConnection: Parsed struct with %lu elements", (unsigned long)[structArray count]);
            return structArray;
        }
        
        case DBUS_TYPE_DICT_ENTRY: {
            // NSLog(@"DBusConnection: Parsing dict entry");
            DBusMessageIter subIter;
            dbus_message_iter_recurse(iter, &subIter);
            
            // First element is key
            id key = nil;
            if (dbus_message_iter_get_arg_type(&subIter) != DBUS_TYPE_INVALID) {
                key = [self parseDBusMessageIterator:&subIter];
                dbus_message_iter_next(&subIter);
            }
            
            // Second element is value
            id value = nil;
            if (dbus_message_iter_get_arg_type(&subIter) != DBUS_TYPE_INVALID) {
                value = [self parseDBusMessageIterator:&subIter];
            }
            
            if (key && value) {
                NSDictionary *result = [NSDictionary dictionaryWithObject:value forKey:key];
                // NSLog(@"DBusConnection: Parsed dict entry: %@ -> %@", key, value);
                return result;
            } else {
                NSLog(@"DBusConnection: Invalid dict entry (missing key or value)");
                return nil;
            }
        }
        
        case DBUS_TYPE_VARIANT: {
            // NSLog(@"DBusConnection: Parsing variant");
            DBusMessageIter subIter;
            dbus_message_iter_recurse(iter, &subIter);
            
            id value = [self parseDBusMessageIterator:&subIter];
            // NSLog(@"DBusConnection: Parsed variant containing: %@", value);
            return value;
        }
        
        default:
            NSLog(@"DBusConnection: Unsupported DBus type: %c (%d)", (char)argType, argType);
            return nil;
    }
}

- (void)processMessages
{
    if (!self.connected || !self.connection) {
        return;
    }
    
    @try {
        // Process pending messages with timeout
        dbus_connection_read_write_dispatch((DBusConnectionStruct *)self.connection, 0);
        
        // Check for incoming messages
        DBusMessage *message;
        while ((message = dbus_connection_pop_message((DBusConnectionStruct *)self.connection)) != NULL) {
            // Recheck connection validity in case it closed during processing
            if (!self.connected || !self.connection) {
                dbus_message_unref(message);
                break;
            }
            [self handleIncomingMessage:message];
            dbus_message_unref(message);
        }
    }
    @catch (NSException *exception) {
        NSLog(@"DBusConnection: Exception during message processing: %@", exception);
    }
}

- (void *)rawConnection
{
    return (void *)self.connection;
}

- (int)getFileDescriptor
{
    if (!self.connected || !self.connection) {
        NSLog(@"DBusConnection: Cannot get file descriptor - not connected");
        return -1;
    }
    
    @try {
        // Get the Unix file descriptor from the DBus connection
        int fd = -1;
        if (dbus_connection_get_unix_fd((DBusConnectionStruct *)self.connection, &fd)) {
            // NSLog(@"DBusConnection: Got file descriptor: %d", fd);
            // Validate file descriptor
            if (fd < 0) {
                NSLog(@"DBusConnection: Invalid file descriptor: %d", fd);
                return -1;
            }
            return fd;
        } else {
            NSLog(@"DBusConnection: Failed to get file descriptor");
            return -1;
        }
    } @catch (NSException *exception) {
        NSLog(@"DBusConnection: Exception getting file descriptor: %@", exception);
        return -1;
    }
}

- (BOOL)sendReply:(void *)reply
{
    if (!self.connected || !self.connection || !reply) {
        return NO;
    }
    
    dbus_bool_t result = dbus_connection_send((DBusConnectionStruct *)self.connection, (DBusMessage *)reply, NULL);
    return result == TRUE;
}

- (void)handleIncomingMessage:(DBusMessage*)message
{
    if (!message) return;
    
    const char *path = dbus_message_get_path(message);
    const char *interface = dbus_message_get_interface(message);
    const char *method = dbus_message_get_member(message);
    
    if (!path || !interface || !method) {
        return;
    }
    
    NSString *pathStr = [NSString stringWithUTF8String:path];
    NSString *interfaceStr = [NSString stringWithUTF8String:interface];
    NSString *methodStr = [NSString stringWithUTF8String:method];
    
    // NSLog(@"DBusConnection: Received method call: %@.%@ on %@", interfaceStr, methodStr, pathStr);
    
    // Handle introspection requests
    if ([interfaceStr isEqualToString:@"org.freedesktop.DBus.Introspectable"] && 
        [methodStr isEqualToString:@"Introspect"]) {
        [self handleIntrospectRequest:message];
        return;
    }
    
    // Find and call the appropriate handler
    NSString *key = [NSString stringWithFormat:@"%@:%@", pathStr, interfaceStr];
    id handler = [self.messageHandlers objectForKey:key];
    
    if (handler && [handler respondsToSelector:@selector(handleDBusMethodCall:)]) {
        NSDictionary *callInfo = @{
            @"message": [NSValue valueWithPointer:message],
            @"path": pathStr,
            @"interface": interfaceStr,
            @"method": methodStr
        };
        [handler performSelector:@selector(handleDBusMethodCall:) withObject:callInfo];
    } else {
        // Only log unhandled methods for debugging rare cases
        if (![interfaceStr isEqualToString:@"org.freedesktop.DBus.Properties"]) {
            // NSLog(@"DBusConnection: No handler found for %@.%@ on %@", interfaceStr, methodStr, pathStr);
        }
    }
}

- (void)handleIntrospectRequest:(DBusMessage*)message
{
    const char *path = dbus_message_get_path(message);
    NSString *pathStr = [NSString stringWithUTF8String:path];
    NSLog(@"DBusConnection: Introspect request for path: %@", pathStr);
    
    NSString *introspectionXML = [self getIntrospectionXMLForPath:pathStr];
    NSLog(@"DBusConnection: Returning introspection XML:\n%@", introspectionXML);
    
    DBusMessage *reply = dbus_message_new_method_return(message);
    if (reply) {
        const char *xmlStr = [introspectionXML UTF8String];
        dbus_message_append_args(reply, DBUS_TYPE_STRING, &xmlStr, DBUS_TYPE_INVALID);
        
        dbus_connection_send((DBusConnectionStruct *)self.connection, reply, NULL);
        dbus_message_unref(reply);
        
        // NSLog(@"DBusConnection: Sent introspection XML for path %s", path);
    }
}

- (NSString *)getIntrospectionXMLForPath:(NSString *)path
{
    if ([path isEqualToString:@"/com/canonical/AppMenu/Registrar"]) {
        return @"<!DOCTYPE node PUBLIC \"-//freedesktop//DTD D-BUS Object Introspection 1.0//EN\"\n"
               @"\"http://www.freedesktop.org/standards/dbus/1.0/introspect.dtd\">\n"
               @"<node>\n"
               @"  <interface name=\"org.freedesktop.DBus.Introspectable\">\n"
               @"    <method name=\"Introspect\">\n"
               @"      <arg name=\"xml_data\" type=\"s\" direction=\"out\"/>\n"
               @"    </method>\n"
               @"  </interface>\n"
               @"</node>";
    }

    // This is needed so that applications know we implement the FileManager1 interface
    if ([path isEqualToString:@"/org/freedesktop/FileManager1"]) {
        return @"<!DOCTYPE node PUBLIC \"-//freedesktop//DTD D-BUS Object Introspection 1.0//EN\"\n"
               @"\"http://www.freedesktop.org/standards/dbus/1.0/introspect.dtd\">\n"
               @"<node name=\"/org/freedesktop/FileManager1\">\n"
               @"  <interface name=\"org.freedesktop.DBus.Introspectable\">\n"
               @"    <method name=\"Introspect\">\n"
               @"      <arg name=\"xml_data\" type=\"s\" direction=\"out\"/>\n"
               @"    </method>\n"
               @"  </interface>\n"
               @"  <interface name=\"org.freedesktop.FileManager1\">\n"
               @"    <method name=\"ShowFolders\">\n"
               @"      <arg name=\"URIs\" type=\"as\" direction=\"in\"/>\n"
               @"      <arg name=\"StartupId\" type=\"s\" direction=\"in\"/>\n"
               @"    </method>\n"
               @"    <method name=\"ShowItems\">\n"
               @"      <arg name=\"URIs\" type=\"as\" direction=\"in\"/>\n"
               @"      <arg name=\"StartupId\" type=\"s\" direction=\"in\"/>\n"
               @"    </method>\n"
               @"    <method name=\"ShowItemProperties\">\n"
               @"      <arg name=\"URIs\" type=\"as\" direction=\"in\"/>\n"
               @"      <arg name=\"StartupId\" type=\"s\" direction=\"in\"/>\n"
               @"    </method>\n"
               @"  </interface>\n"
               @"</node>";
    }

    if ([path isEqualToString:@"/org/freedesktop/portal/desktop"]) {
        return @"<!DOCTYPE node PUBLIC \"-//freedesktop//DTD D-BUS Object Introspection 1.0//EN\"\n"
               @"\"http://www.freedesktop.org/standards/dbus/1.0/introspect.dtd\">\n"
               @"<node name=\"/org/freedesktop/portal/desktop\">\n"
               @"  <interface name=\"org.freedesktop.DBus.Introspectable\">\n"
               @"    <method name=\"Introspect\">\n"
               @"      <arg name=\"xml_data\" type=\"s\" direction=\"out\"/>\n"
               @"    </method>\n"
               @"  </interface>\n"
               @"  <interface name=\"org.freedesktop.portal.FileChooser\">\n"
               @"    <method name=\"OpenFile\">\n"
               @"      <arg name=\"parent_window\" type=\"s\" direction=\"in\"/>\n"
               @"      <arg name=\"title\" type=\"s\" direction=\"in\"/>\n"
               @"      <arg name=\"options\" type=\"a{sv}\" direction=\"in\"/>\n"
               @"      <arg name=\"handle\" type=\"o\" direction=\"out\"/>\n"
               @"    </method>\n"
               @"    <method name=\"SaveFile\">\n"
               @"      <arg name=\"parent_window\" type=\"s\" direction=\"in\"/>\n"
               @"      <arg name=\"title\" type=\"s\" direction=\"in\"/>\n"
               @"      <arg name=\"options\" type=\"a{sv}\" direction=\"in\"/>\n"
               @"      <arg name=\"handle\" type=\"o\" direction=\"out\"/>\n"
               @"    </method>\n"
               @"    <method name=\"SaveFiles\">\n"
               @"      <arg name=\"parent_window\" type=\"s\" direction=\"in\"/>\n"
               @"      <arg name=\"title\" type=\"s\" direction=\"in\"/>\n"
               @"      <arg name=\"options\" type=\"a{sv}\" direction=\"in\"/>\n"
               @"      <arg name=\"handle\" type=\"o\" direction=\"out\"/>\n"
               @"    </method>\n"
               @"  </interface>\n"
               @"</node>";
    }

    if ([path hasPrefix:@"/org/freedesktop/portal/desktop/request/"]) {
        return @"<!DOCTYPE node PUBLIC \"-//freedesktop//DTD D-BUS Object Introspection 1.0//EN\"\n"
               @"\"http://www.freedesktop.org/standards/dbus/1.0/introspect.dtd\">\n"
               @"<node>\n"
               @"  <interface name=\"org.freedesktop.DBus.Introspectable\">\n"
               @"    <method name=\"Introspect\">\n"
               @"      <arg name=\"xml_data\" type=\"s\" direction=\"out\"/>\n"
               @"    </method>\n"
               @"  </interface>\n"
               @"  <interface name=\"org.freedesktop.portal.Request\">\n"
               @"    <signal name=\"Response\">\n"
               @"      <arg name=\"response\" type=\"u\"/>\n"
               @"      <arg name=\"results\" type=\"a{sv}\"/>\n"
               @"    </signal>\n"
               @"  </interface>\n"
               @"</node>";
    }
    
    return @"<!DOCTYPE node PUBLIC \"-//freedesktop//DTD D-BUS Object Introspection 1.0//EN\"\n"
           @"\"http://www.freedesktop.org/standards/dbus/1.0/introspect.dtd\">\n"
           @"<node>\n"
           @"</node>";
}

- (void *)connection
{
    return _connection;
}

@end
