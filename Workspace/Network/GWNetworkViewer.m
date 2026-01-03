/* GWNetworkViewer.m
 *  
 * Copyright (C) 2025 Free Software Foundation, Inc.
 *
 * Author: Simon Peter
 * Date: January 2025
 *
 * This file is part of the GNUstep Workspace application
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 * 
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 * 
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 31 Milk Street #960789 Boston, MA 02196 USA.
 */

#import <AppKit/AppKit.h>
#import <GNUstepBase/GNUstep.h>
#import "GWNetworkViewer.h"
#import "GWNetworkIconsView.h"
#import "NetworkServiceManager.h"
#import "NetworkServiceItem.h"
#import "Workspace.h"

static GWNetworkViewer *sharedViewer = nil;

@implementation GWNetworkViewer

+ (instancetype)sharedViewer
{
  if (sharedViewer == nil) {
    sharedViewer = [[GWNetworkViewer alloc] init];
  }
  return sharedViewer;
}

- (instancetype)init
{
  self = [super init];
  if (self) {
    gworkspace = [Workspace gworkspace];
    nc = [NSNotificationCenter defaultCenter];
    displayedServices = [[NSMutableArray alloc] init];
    isActive = NO;
    
    [self createWindow];
    [self setupServiceManager];
  }
  return self;
}

- (void)dealloc
{
  [nc removeObserver:self];
  
  if (serviceManager) {
    [serviceManager stopBrowsing];
  }
  
  RELEASE(displayedServices);
  RELEASE(window);
  
  [super dealloc];
}

- (void)createWindow
{
  unsigned int styleMask = NSTitledWindowMask | NSClosableWindowMask 
                         | NSMiniaturizableWindowMask | NSResizableWindowMask;
  
  NSRect windowFrame = NSMakeRect(200, 200, 600, 400);
  
  window = [[NSWindow alloc] initWithContentRect:windowFrame
                                       styleMask:styleMask
                                         backing:NSBackingStoreBuffered
                                           defer:NO];
  
  [window setTitle:@"Network"];
  [window setMinSize:NSMakeSize(400, 300)];
  [window setDelegate:self];
  [window setReleasedWhenClosed:NO];
  
  /* Create the scroll view */
  NSRect contentRect = [[window contentView] bounds];
  scrollView = [[NSScrollView alloc] initWithFrame:contentRect];
  [scrollView setHasVerticalScroller:YES];
  [scrollView setHasHorizontalScroller:NO];
  [scrollView setAutoresizingMask:(NSViewWidthSizable | NSViewHeightSizable)];
  [scrollView setBorderType:NSNoBorder];
  
  /* Create the icons view */
  iconsView = [[GWNetworkIconsView alloc] initWithFrame:contentRect 
                                              forViewer:self];
  [scrollView setDocumentView:iconsView];
  RELEASE(iconsView);
  
  [[window contentView] addSubview:scrollView];
  RELEASE(scrollView);
  
  NSLog(@"GWNetworkViewer: Window created");
}

- (void)setupServiceManager
{
  serviceManager = [NetworkServiceManager sharedManager];
  
  /* Register for service change notifications */
  [nc addObserver:self
         selector:@selector(servicesDidChange:)
             name:NetworkServicesDidChangeNotification
           object:serviceManager];
  
  [nc addObserver:self
         selector:@selector(serviceDidResolve:)
             name:NetworkServiceDidResolveNotification
           object:serviceManager];
  
  /* Start browsing if mDNS is available */
  if ([serviceManager isMDNSAvailable]) {
    [serviceManager startBrowsing];
    NSLog(@"GWNetworkViewer: Started service browsing");
  } else {
    NSLog(@"GWNetworkViewer: mDNS not available, cannot browse for services");
  }
}

- (void)showWindow
{
  if (![window isVisible]) {
    /* Refresh the display with current services */
    [self updateDisplayedServices];
  }
  
  [window makeKeyAndOrderFront:nil];
  isActive = YES;
  
  NSLog(@"GWNetworkViewer: Window shown with %lu services", 
        (unsigned long)[displayedServices count]);
}

- (NSWindow *)window
{
  return window;
}

- (BOOL)isVisible
{
  return [window isVisible];
}

- (void)activate
{
  [window makeKeyAndOrderFront:nil];
  isActive = YES;
}

- (NSArray *)selectedServices
{
  return [iconsView selectedServices];
}

#pragma mark - Service Updates

- (void)updateDisplayedServices
{
  @synchronized(displayedServices) {
    [displayedServices removeAllObjects];
    [displayedServices addObjectsFromArray:[serviceManager allServices]];
  }
  
  [iconsView reloadServices];
  
  NSLog(@"GWNetworkViewer: Updated display with %lu services", 
        (unsigned long)[displayedServices count]);
}

- (void)servicesDidChange:(NSNotification *)notification
{
  NSLog(@"GWNetworkViewer: Received services changed notification");
  
  /* Update on main thread */
  [self performSelectorOnMainThread:@selector(updateDisplayedServices)
                         withObject:nil
                      waitUntilDone:NO];
}

- (void)serviceDidResolve:(NSNotification *)notification
{
  NetworkServiceItem *service = [[notification userInfo] objectForKey:@"service"];
  NSLog(@"GWNetworkViewer: Service resolved: %@", [service displayName]);
  
  /* Update on main thread */
  [self performSelectorOnMainThread:@selector(updateDisplayedServices)
                         withObject:nil
                      waitUntilDone:NO];
}

#pragma mark - Accessors

- (NSArray *)services
{
  @synchronized(displayedServices) {
    return [[displayedServices copy] autorelease];
  }
}

#pragma mark - NSWindowDelegate

- (void)windowDidBecomeKey:(NSNotification *)notification
{
  isActive = YES;
  NSLog(@"GWNetworkViewer: Window became key");
}

- (void)windowDidResignKey:(NSNotification *)notification
{
  isActive = NO;
}

- (BOOL)windowShouldClose:(id)sender
{
  [window orderOut:nil];
  return NO; /* Don't actually close, just hide */
}

@end
