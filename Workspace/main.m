/* main.m
 *  
 * Copyright (C) 2003-2010 Free Software Foundation, Inc.
 *
 * Author: Enrico Sersale <enrico@imago.ro>
 * Date: August 2001
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

#include "config.h"

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <GNUstepBase/GNUstep.h>
#include <unistd.h>

#include "Workspace.h"
  
int main(int argc, char **argv, char **env)
{
	CREATE_AUTORELEASE_POOL (pool);
  Workspace *gw = [Workspace gworkspace];
  
  // If GTK_MODULES indicates appmenu integration, wait up to 2sec for the
  // Canonical AppMenu registrar to appear on the session bus so subsequent
  // menu setup and scans can find dbusmenu-providing services.
#if HAVE_DBUS
  if ([gw waitForAppMenuRegistrarWithTimeoutMs:5000]) {
    NSLog(@"Workspace: AppMenu registrar present");
    // Wait for an additional 50ms
    usleep(50 * 1000);
  } else {
    NSLog(@"Workspace: AppMenu registrar did not appear within 5000ms (or GTK_MODULES does not request appmenu)");
  }
#else
  NSLog(@"Workspace: DBus support not available");
#endif
  
	NSApplication *app = [NSApplication sharedApplication];
  
  [app setDelegate: gw];    
	[app run];
	RELEASE (pool);
  
  return 0;
}

