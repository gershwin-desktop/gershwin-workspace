/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>

@protocol DockService
- (void)setBadgeCount:(int64_t)count;
- (void)setCountVisible:(BOOL)visible;
@end

@interface BadgeTestDelegate : NSObject
{
  NSWindow *window;
  NSTextField *label;
  int count;
  id proxy;
}
@end

@implementation BadgeTestDelegate

- (id)init
{
  self = [super init];
  if (self)
    {
      count = 5;

      NSString *name = @"DockIcon";
      NSConnection *conn;
      conn = [NSConnection connectionWithRegisteredName:name host:nil];
      if (conn)
        {
          proxy = [[conn rootProxy] retain];
          [proxy setBadgeCount:count];
          [proxy setCountVisible:(count > 0)];
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
  [proxy release];
  [super dealloc];
}

- (void)applyBadge
{
  [proxy setBadgeCount:count];
  [proxy setCountVisible:(count > 0)];
  [label setIntValue:count];
}

- (void)increment:(id)sender
{
  count++;
  [self applyBadge];
}

- (void)decrement:(id)sender
{
  count--;
  if (count < 0)
    count = 0;
  [self applyBadge];
}

- (void)applicationDidFinishLaunching:(NSNotification *)notif
{
  NSMenu *mainMenu = [[NSMenu alloc] init];
  id<NSMenuItem> appItem = [mainMenu addItemWithTitle:@"BadgeTest"
                                            action:NULL
                                     keyEquivalent:@""];
  NSMenu *appMenu = [[NSMenu alloc] init];
  [mainMenu setSubmenu:appMenu forItem:appItem];
  [appMenu addItemWithTitle:@"About BadgeTest"
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

  NSRect r = NSMakeRect(0, 0, 280, 120);
  window = [[NSWindow alloc] initWithContentRect:r
                                       styleMask:NSTitledWindowMask
                                                | NSClosableWindowMask
                                                | NSMiniaturizableWindowMask
                                         backing:NSBackingStoreBuffered
                                           defer:NO];
  [window setTitle:@"BadgeTest"];
  [window setDelegate:self];
  [window center];

  NSView *content = [window contentView];

  label = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 60, 240, 30)];
  [label setAlignment:NSCenterTextAlignment];
  [label setFont:[NSFont boldSystemFontOfSize:20]];
  [label setBezeled:NO];
  [label setEditable:NO];
  [label setSelectable:NO];
  [label setDrawsBackground:NO];
  [[window contentView] addSubview:label];

  NSButton *up = [[NSButton alloc] initWithFrame:NSMakeRect(80, 20, 50, 28)];
  [up setTitle:@"+1"];
  [up setTarget:self];
  [up setAction:@selector(increment:)];
  [content addSubview:up];
  [up release];

  NSButton *down = [[NSButton alloc] initWithFrame:NSMakeRect(150, 20, 50, 28)];
  [down setTitle:@"-1"];
  [down setTarget:self];
  [down setAction:@selector(decrement:)];
  [content addSubview:down];
  [down release];

  [self applyBadge];
  [NSApp activateIgnoringOtherApps:YES];
  [window makeKeyAndOrderFront:nil];
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
  BadgeTestDelegate *del = [[BadgeTestDelegate alloc] init];
  [NSApp setDelegate:del];
  [NSApp run];
  [del release];
  [pool release];
  return 0;
}
