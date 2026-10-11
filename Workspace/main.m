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
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <dirent.h>
#include <signal.h>
#include <sys/types.h>
#include <errno.h>

#include "Workspace.h"
#include "FinderInfoLocker.h"
#include "GWSingleInstance.h"

/* Forward declaration of UI testing enable function */
extern void WorkspaceUITestingSetEnabled(BOOL enabled);

int main(int argc, char **argv, char **env)
{
    /* Privileged re-exec from the Inspector (sudo -A <Workspace> --set-immutable
     * <plist>): do the one action and leave before anything below runs, since
     * the single-instance check would kill the user's own Workspace. */
    if (argc >= 3 && strcmp(argv[1], FinderInfoLockHelperFlag) == 0)
        return FinderInfoLockHelperMain(argv[2]);

#ifndef _WIN32
    /* A DO write to a dead peer (an app the user closed, a crashed connection)
     * raises SIGPIPE; GNUstep ignores it at NSObject init, but a library can
     * reset it to SIG_DFL later, and then the default action terminates the
     * Workspace mid-operation (a button click that sends a DO message crashed
     * the app under the UI tests).  Ignore it here so a broken pipe is never
     * fatal. */
    signal(SIGPIPE, SIG_IGN);

    /* Only a Workspace on this X display is replaced: a Workspace of the
     * same user on another display (a test session) must keep running, which
     * a scan of all processes by name cannot tell apart. */
    /* Debug hook: lets a second Workspace run under a debugger next to the
     * live one without taking over its display. */
    if (getenv("GW_NO_KILL_INSTANCES") == NULL)
      {
        if (!GWSingleInstanceClaimDisplay())
          {
            return 1;
          }
      }
#endif /* !_WIN32 */
    
	CREATE_AUTORELEASE_POOL (pool);
  
  /* Check for debug/UI testing flag */
  BOOL debugMode = NO;
  for (int i = 1; i < argc; i++) {
    if (strcmp(argv[i], "-d") == 0 || strcmp(argv[i], "--debug") == 0) {
      debugMode = YES;
      break;
    }
  }
  
  Workspace *gw = [Workspace gworkspace];
  
  /* Enable UI testing if debug mode is enabled */
  if (debugMode) {
    WorkspaceUITestingSetEnabled(YES);
  }
  
	NSApplication *app = [NSApplication sharedApplication];
  
  [app setDelegate: gw];    
	[app run];
	RELEASE (pool);
  
  return 0;
}

