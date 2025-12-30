/*
 * Copyright (c) 2025 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */


#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>

// DBus connection wrapper for GNUstep
@interface GNUDBusConnection : NSObject

@property (nonatomic, assign) void *connection; // DBusConnection pointer (opaque)
@property (nonatomic, assign) BOOL connected;
@property (nonatomic, strong) NSMutableDictionary *messageHandlers;

+ (GNUDBusConnection *)sessionBus;
- (BOOL)connect;
- (void)disconnect;
- (BOOL)isConnected;
- (BOOL)registerService:(NSString *)serviceName;
- (BOOL)registerObjectPath:(NSString *)objectPath 
                 interface:(NSString *)interfaceName 
                   handler:(id)handler;
- (id)callMethod:(NSString *)method
      onService:(NSString *)serviceName
    objectPath:(NSString *)objectPath
     interface:(NSString *)interfaceName
     arguments:(NSArray *)arguments;
- (id)callGTKActivateMethod:(NSString *)actionName
                  parameter:(NSArray *)parameter
               platformData:(NSDictionary *)platformData
                  onService:(NSString *)serviceName
                 objectPath:(NSString *)objectPath;
- (void)processMessages;
- (void *)rawConnection;
- (int)getFileDescriptor;

@end
