/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

#import "DockServiceDBus.h"
#import <AppKit/AppKit.h>
#import "DockService.h"
#import "Dock.h"
#import "DockIcon.h"
#import "DBusConnection.h"
#import <dbus/dbus.h>
#import <dispatch/dispatch.h>

typedef struct DBusConnection DBusConnectionStruct;

static DockServiceDBus *sharedDBusService = nil;

@implementation DockServiceDBus

- (id)initWithDock:(Dock *)dock
{
  self = [super init];
  if (self)
    {
      self.dock = dock;
      self.dbusConnection = [GNUDBusConnection sessionBus];
    }
  return self;
}

- (void)dealloc
{
  [processTimer invalidate];
  processTimer = nil;
  self.dock = nil;
  self.dbusConnection = nil;
  [super dealloc];
}

- (BOOL)registerOnDBus
{
  if (!self.dbusConnection || ![self.dbusConnection isConnected])
    {
      NSDebugLLog(@"gwspace", @"DockServiceDBus: DBus not connected");
      return NO;
    }

  BOOL serviceRegistered = [self.dbusConnection registerService:@"com.canonical.Unity.LauncherEntry"];
  if (!serviceRegistered)
    {
      NSDebugLLog(@"gwspace", @"DockServiceDBus: Failed to register com.canonical.Unity.LauncherEntry");
      return NO;
    }

  BOOL objectRegistered = [self.dbusConnection
    registerObjectPath:@"/com/canonical/unity/launcherentry"
            interface:@"com.canonical.Unity.LauncherEntry"
              handler:self];
  if (!objectRegistered)
    {
      NSDebugLLog(@"gwspace", @"DockServiceDBus: Failed to register object path");
      return NO;
    }

  /* Start a 100ms timer to process incoming D-Bus messages independently
     of FileManagerDBusInterface's file descriptor monitoring. */
  processTimer = [NSTimer scheduledTimerWithTimeInterval:0.1
                                                  target:self
                                                selector:@selector(processDBusMessages:)
                                                userInfo:nil
                                                 repeats:YES];

  NSDebugLLog(@"gwspace", @"DockServiceDBus: Registered com.canonical.Unity.LauncherEntry on DBus");
  return YES;
}

- (void)processDBusMessages:(NSTimer *)timer
{
  [self.dbusConnection processMessages];
}

- (void)handleDBusMethodCall:(NSDictionary *)callInfo
{
  NSValue *messageValue = [callInfo objectForKey:@"message"];
  NSString *method = [callInfo objectForKey:@"method"];

  if (!messageValue || !method)
    return;

  DBusMessage *message = (DBusMessage *)[messageValue pointerValue];

  if ([method isEqualToString:@"Update"])
    {
      [self handleUpdate:message];
    }
  else
    {
      NSDebugLLog(@"gwspace", @"DockServiceDBus: Unknown method: %@", method);
      [self sendErrorReply:message
                errorName:"org.freedesktop.DBus.Error.UnknownMethod"
              errorMessage:[[NSString stringWithFormat:@"Unknown method: %@", method] UTF8String]];
    }
}

- (void)handleUpdate:(DBusMessage *)message
{
  DBusMessageIter iter;
  if (!dbus_message_iter_init(message, &iter))
    {
      [self sendErrorReply:message errorName:"org.freedesktop.DBus.Error.InvalidArgs"
              errorMessage:"Update requires at least 2 arguments"];
      return;
    }

  /* First argument: app_id (string) */
  if (dbus_message_iter_get_arg_type(&iter) != DBUS_TYPE_STRING)
    {
      [self sendErrorReply:message errorName:"org.freedesktop.DBus.Error.InvalidArgs"
              errorMessage:"First argument must be a string (app_id)"];
      return;
    }

  char *appIdStr;
  dbus_message_iter_get_basic(&iter, &appIdStr);
  NSString *appId = [NSString stringWithUTF8String:appIdStr];

  dbus_message_iter_next(&iter);

  /* Second argument: properties (array of dict entries) */
  if (dbus_message_iter_get_arg_type(&iter) != DBUS_TYPE_ARRAY)
    {
      [self sendErrorReply:message errorName:"org.freedesktop.DBus.Error.InvalidArgs"
              errorMessage:"Second argument must be an array (dict properties)"];
      return;
    }

  NSDictionary *properties = [self parsePropertiesDict:&iter];
  if (properties == nil)
    {
      properties = [NSDictionary dictionary];
    }

  NSString *appName = DockServiceAppNameFromUri(appId);
  if (appName == nil)
    {
      [self sendEmptyReply:message];
      return;
    }

  dispatch_async(dispatch_get_main_queue(), ^{
    DockIcon *icon = [self.dock iconForApplicationPath:appName];
    if (icon)
      {
        DockServiceApplyProperties(properties, icon);
      }
  });

  [self sendEmptyReply:message];
}

- (NSDictionary *)parsePropertiesDict:(DBusMessageIter *)iter
{
  DBusMessageIter arrayIter;
  dbus_message_iter_recurse(iter, &arrayIter);

  NSMutableDictionary *dict = [NSMutableDictionary dictionary];

  while (dbus_message_iter_get_arg_type(&arrayIter) == DBUS_TYPE_DICT_ENTRY)
    {
      DBusMessageIter entryIter;
      dbus_message_iter_recurse(&arrayIter, &entryIter);

      /* Key (string) */
      if (dbus_message_iter_get_arg_type(&entryIter) != DBUS_TYPE_STRING)
        {
          dbus_message_iter_next(&arrayIter);
          continue;
        }

      char *keyStr;
      dbus_message_iter_get_basic(&entryIter, &keyStr);
      NSString *key = [NSString stringWithUTF8String:keyStr];

      dbus_message_iter_next(&entryIter);

      /* Value (variant) */
      if (dbus_message_iter_get_arg_type(&entryIter) != DBUS_TYPE_VARIANT)
        {
          dbus_message_iter_next(&arrayIter);
          continue;
        }

      DBusMessageIter variantIter;
      dbus_message_iter_recurse(&entryIter, &variantIter);

      id value = [self parseVariantValue:&variantIter];
      if (value)
        {
          [dict setObject:value forKey:key];
        }

      dbus_message_iter_next(&arrayIter);
    }

  return dict;
}

- (id)parseVariantValue:(DBusMessageIter *)variantIter
{
  int type = dbus_message_iter_get_arg_type(variantIter);

  switch (type)
    {
    case DBUS_TYPE_BOOLEAN:
      {
        dbus_bool_t val;
        dbus_message_iter_get_basic(variantIter, &val);
        return [NSNumber numberWithBool:val];
      }
    case DBUS_TYPE_INT32:
      {
        dbus_int32_t val;
        dbus_message_iter_get_basic(variantIter, &val);
        return [NSNumber numberWithInt:val];
      }
    case DBUS_TYPE_UINT32:
      {
        dbus_uint32_t val;
        dbus_message_iter_get_basic(variantIter, &val);
        return [NSNumber numberWithUnsignedInt:val];
      }
    case DBUS_TYPE_INT64:
      {
        dbus_int64_t val;
        dbus_message_iter_get_basic(variantIter, &val);
        return [NSNumber numberWithLongLong:val];
      }
    case DBUS_TYPE_DOUBLE:
      {
        double val;
        dbus_message_iter_get_basic(variantIter, &val);
        return [NSNumber numberWithDouble:val];
      }
    case DBUS_TYPE_STRING:
      {
        char *val;
        dbus_message_iter_get_basic(variantIter, &val);
        return [NSString stringWithUTF8String:val];
      }
    default:
      return nil;
    }
}

- (void)sendEmptyReply:(DBusMessage *)message
{
  DBusMessage *reply = dbus_message_new_method_return(message);
  if (reply)
    {
      void *conn = [self.dbusConnection rawConnection];
      if (conn)
        {
          dbus_connection_send((DBusConnectionStruct *)conn, reply, NULL);
          dbus_connection_flush((DBusConnectionStruct *)conn);
        }
      dbus_message_unref(reply);
    }
}

- (void)sendErrorReply:(DBusMessage *)message
             errorName:(const char *)errorName
          errorMessage:(const char *)errorMessage
{
  DBusMessage *reply = dbus_message_new_error(message, errorName, errorMessage);
  if (reply)
    {
      void *conn = [self.dbusConnection rawConnection];
      if (conn)
        {
          dbus_connection_send((DBusConnectionStruct *)conn, reply, NULL);
          dbus_connection_flush((DBusConnectionStruct *)conn);
        }
      dbus_message_unref(reply);
    }
}

@end

void DockServiceDBusStart(id dock)
{
  if (sharedDBusService == nil)
    {
      sharedDBusService = [[DockServiceDBus alloc] initWithDock:dock];
      [sharedDBusService registerOnDBus];
    }
}

void DockServiceDBusStop(void)
{
  if (sharedDBusService)
    {
      DESTROY(sharedDBusService);
    }
}
