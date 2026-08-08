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

/* Forward declaration of UI testing enable function */
extern void WorkspaceUITestingSetEnabled(BOOL enabled);

/* Real UID of a process, or -1 if it cannot be determined.  The
 * single-instance check below must not touch another user's instance: a
 * second desktop session on a separate X display (e.g. a UI-test run under
 * Xvfb as a different user) must not kill the logged-in user's Workspace.
 * Linux exposes /proc/<pid>/status; the BSDs lack that layout, so fall back
 * to `ps -o uid= -p <pid>`. */
static int processUid(pid_t pid)
{
#if defined(__linux__)
    char path[64];
    snprintf(path, sizeof(path), "/proc/%d/status", pid);
    FILE *f = fopen(path, "r");
    if (!f) return -1;
    char line[256];
    int uid = -1;
    while (fgets(line, sizeof(line), f)) {
        if (strncmp(line, "Uid:", 4) == 0) {
            sscanf(line + 4, "%d", &uid);
            break;
        }
    }
    fclose(f);
    return uid;
#else
    char cmd[64];
    snprintf(cmd, sizeof(cmd), "ps -o uid= -p %d", pid);
    FILE *f = popen(cmd, "r");
    if (!f) return -1;
    int uid = -1;
    if (fscanf(f, "%d", &uid) != 1) uid = -1;
    pclose(f);
    return uid;
#endif
}

static void killOtherInstances(const char *myBasename, pid_t myPid)
{
    DIR *procDir;
    struct dirent *entry;
    int killedCount = 0;
    
    fprintf(stderr, "Workspace: Checking for other instances of '%s' (my PID: %d)\n", 
            myBasename, (int)myPid);
    
    procDir = opendir("/proc");
    if (!procDir) {
        fprintf(stderr, "Workspace: Warning - cannot open /proc: %s\n", strerror(errno));
        return;
    }
    
    while ((entry = readdir(procDir)) != NULL) {
        // Skip non-numeric entries (only PIDs are numeric)
        char *endptr;
        long pid = strtol(entry->d_name, &endptr, 10);
        if (*endptr != '\0' || pid <= 0) {
            continue;
        }
        
        // Skip our own PID
        if (pid == myPid) {
            continue;
        }
        
        /* Only this user's instances: a Workspace on another display/session
         * belongs to a different (test) user and must be left alone. */
        if (processUid((pid_t)pid) != (int)getuid()) {
            continue;
        }
        
        // Read the process name from /proc/[pid]/comm
        char commPath[512];
        snprintf(commPath, sizeof(commPath), "/proc/%ld/comm", pid);
        
        FILE *commFile = fopen(commPath, "r");
        if (commFile) {
            char procName[256];
            if (fgets(procName, sizeof(procName), commFile)) {
                // Remove trailing newline
                size_t len = strlen(procName);
                if (len > 0 && procName[len-1] == '\n') {
                    procName[len-1] = '\0';
                }
                
                // Compare basename
                if (strcmp(procName, myBasename) == 0) {
                    fprintf(stderr, "Workspace: Found other instance with PID %ld, sending SIGKILL\n", pid);
                    if (kill(pid, SIGKILL) == 0) {
                        killedCount++;
                        fprintf(stderr, "Workspace: Successfully sent SIGKILL to PID %ld\n", pid);
                    } else {
                        fprintf(stderr, "Workspace: Failed to kill PID %ld: %s\n", 
                                pid, strerror(errno));
                    }
                }
            }
            fclose(commFile);
        }
    }
    
    closedir(procDir);
    
    if (killedCount > 0) {
        fprintf(stderr, "Workspace: Terminated %d other instance(s), waiting 500ms for cleanup\n", 
                killedCount);
        usleep(500000); // Wait 500ms for processes to terminate
    } else {
        fprintf(stderr, "Workspace: No other instances found\n");
    }
}

int main(int argc, char **argv, char **env)
{
    // Kill any other instances of this application FIRST, before anything else
    pid_t myPid = getpid();
    const char *myBasename = "Workspace";
    
    // Extract basename from argv[0] if available
    if (argc > 0 && argv[0]) {
        const char *lastSlash = strrchr(argv[0], '/');
        if (lastSlash) {
            myBasename = lastSlash + 1;
        } else {
            myBasename = argv[0];
        }
    }
    
    killOtherInstances(myBasename, myPid);
    
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

