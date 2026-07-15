/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>

@protocol DockService
- (void)update:(NSString *)appUri properties:(NSDictionary *)properties;
@end

@interface ProgressTestDelegate : NSObject
{
  NSWindow *window;
  NSProgressIndicator *indicator;
  id proxy;
  NSTimer *timer;
  double progress;
  int direction;
}
@end

@implementation ProgressTestDelegate

- (id)init
{
  self = [super init];
  if (self)
    {
      progress = 0.0;
      direction = 1;

      NSString *name = @"com.canonical.Unity.LauncherEntry";
      NSConnection *conn;
      conn = [NSConnection connectionWithRegisteredName:name host:nil];
      if (conn)
        {
          proxy = [[conn rootProxy] retain];
        }
      else
        {
          NSLog(@"Failed to connect to Dock service.");
        }
    }
  return self;
}

- (void)dealloc
{
  [timer invalidate];
  [proxy release];
  [super dealloc];
}

- (void)stepProgress:(NSTimer *)t
{
  progress += 0.02 * direction;
  if (progress >= 1.0)
    {
      progress = 1.0;
      direction = -1;
    }
  else if (progress <= 0.0)
    {
      progress = 0.0;
      direction = 1;
    }

  [indicator setDoubleValue:progress * 100.0];
  [proxy update:@"ProgressTest" properties:@{
    @"progress": @(progress),
    @"progress-visible": @YES
  }];
}

- (void)applicationDidFinishLaunching:(NSNotification *)notif
{
  NSMenu *mainMenu = [[NSMenu alloc] init];
  id<NSMenuItem> appItem = [mainMenu addItemWithTitle:@"ProgressTest"
                                            action:NULL
                                     keyEquivalent:@""];
  NSMenu *appMenu = [[NSMenu alloc] init];
  [mainMenu setSubmenu:appMenu forItem:appItem];
  [appMenu addItemWithTitle:@"About ProgressTest"
                     action:@selector(orderFrontStandardInfoPanel:)
              keyEquivalent:@""];
  [appMenu addItem:[NSMenuItem separatorItem]];
  NSMenuItem *quitItem;
  quitItem = [[NSMenuItem alloc] initWithTitle:@"Quit"
                                        action:@selector(terminate:)
                                 keyEquivalent:@"q"];
  [quitItem setTarget:NSApp];
  [quitItem setKeyEquivalentModifierMask:NSCommandKeyMask];
  [appMenu addItem:quitItem];
  [quitItem release];
  [appMenu release];
  [NSApp setMainMenu:mainMenu];
  [mainMenu release];

  NSRect r = NSMakeRect(0, 0, 300, 100);
  window = [[NSWindow alloc] initWithContentRect:r
                                       styleMask:NSTitledWindowMask
                                                | NSClosableWindowMask
                                                | NSMiniaturizableWindowMask
                                         backing:NSBackingStoreBuffered
                                           defer:NO];
  [window setTitle:@"ProgressTest"];
  [window setDelegate:self];
  [window center];

  NSView *content = [window contentView];

  indicator = [[NSProgressIndicator alloc] initWithFrame:NSMakeRect(20, 35, 260, 24)];
  [indicator setStyle:NSProgressIndicatorBarStyle];
  [indicator setIndeterminate:NO];
  [indicator setMinValue:0.0];
  [indicator setMaxValue:100.0];
  [indicator setDoubleValue:0.0];
  [content addSubview:indicator];

  NSTextField *desc = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 65, 260, 20)];
  [desc setStringValue:@"Dock icon progress animation"];
  [desc setAlignment:NSCenterTextAlignment];
  [desc setBezeled:NO];
  [desc setEditable:NO];
  [desc setSelectable:NO];
  [desc setDrawsBackground:NO];
  [content addSubview:desc];
  [desc release];

  [NSApp activateIgnoringOtherApps:YES];
  [window makeKeyAndOrderFront:nil];

  timer = [NSTimer scheduledTimerWithTimeInterval:0.05
                                           target:self
                                         selector:@selector(stepProgress:)
                                         userInfo:nil
                                          repeats:YES];
}

- (void)windowWillClose:(NSNotification *)notif
{
  [NSApp terminate:nil];
}

@end

int main(int argc, const char *argv[])
{
  NSAutoreleasePool *pool = [NSAutoreleasePool new];
  [NSApplication sharedApplication];
  ProgressTestDelegate *del = [[ProgressTestDelegate alloc] init];
  [NSApp setDelegate:del];
  [NSApp run];
  [del release];
  [pool release];
  return 0;
}
