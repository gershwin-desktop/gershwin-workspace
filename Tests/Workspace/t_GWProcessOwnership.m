/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

/* t_GWProcessOwnership.m - the Dock must only react to applications that run
 * as the current user on the X display/screen this Workspace serves.
 * Headless: child processes get an explicit DISPLAY, no X server is needed. */

#import <Foundation/Foundation.h>
#import "Testing.h"
#include "../../Workspace/GWProcessOwnership.m"

#include <signal.h>
#include <stdlib.h>
#include <sys/wait.h>

/* A sleeping child with exactly the given DISPLAY (nil: no DISPLAY at all),
 * so the ownership check sees a real foreign-display process. */
static NSTask *childWithDisplay(NSString *display)
{
  NSMutableDictionary *env = [NSMutableDictionary dictionary];
  NSTask *task = [NSTask new];

  [env setObject: @"/bin:/usr/bin" forKey: @"PATH"];
  if (display != nil)
    {
      [env setObject: display forKey: @"DISPLAY"];
    }
  [task setLaunchPath: @"/bin/sleep"];
  [task setArguments: [NSArray arrayWithObject: @"30"]];
  [task setEnvironment: env];
  [task launch];
  return [task autorelease];
}

static NSDictionary *infoWithPID(pid_t pid)
{
  return [NSDictionary dictionaryWithObjectsAndKeys:
    @"TextEdit", @"NSApplicationName",
    @"/System/Applications/TextEdit.app", @"NSApplicationPath",
    [NSNumber numberWithInt: (int)pid], @"NSApplicationProcessIdentifier", nil];
}

int main(void)
{
  NSAutoreleasePool *arp = [NSAutoreleasePool new];

  setenv("DISPLAY", ":0", 1);

  /* --- display names name the same display and screen --- */
  {
    Class o = [GWProcessOwnership class];

    PASS([o display: @":0" isSameAsDisplay: @":0"], "identical display names match");
    PASS([o display: @":0" isSameAsDisplay: @":0.0"], "a missing screen number means screen 0");
    PASS([o display: @"unix:0" isSameAsDisplay: @":0"], "unix:N is the local socket like :N");
    PASS([o display: @"host:3.1" isSameAsDisplay: @"host:3.1"], "remote display with screen matches");
    PASS(![o display: @":0" isSameAsDisplay: @":77"], "another display does not match");
    PASS(![o display: @":0.0" isSameAsDisplay: @":0.1"], "another screen does not match");
    PASS(![o display: @":10" isSameAsDisplay: @"localhost:10"],
         "localhost:N is TCP (e.g. ssh forwarding), not the local socket");
    PASS(![o display: @"a:0" isSameAsDisplay: @"b:0"], "another host does not match");
    PASS(![o display: nil isSameAsDisplay: @":0"], "no display never matches");
    PASS(![o display: @"garbage" isSameAsDisplay: @"garbage"], "unparsable names never match");
    PASS(![o display: @":x" isSameAsDisplay: @":x"], "non-numeric display never matches");
    PASS_EQUAL([o currentDisplay], @":0", "the current display is Workspace's DISPLAY");
  }

  /* --- process owner --- */
  {
    PASS([GWProcessOwnership isProcessOwnedByCurrentUser: getpid()],
         "our own process is owned by us");
    if (getuid() != 0)
      {
        PASS(![GWProcessOwnership isProcessOwnedByCurrentUser: 1],
             "init (root) is not owned by us");
      }
    PASS(![GWProcessOwnership isProcessOwnedByCurrentUser: 0], "pid 0 is nobody's app");
    PASS(![GWProcessOwnership isProcessOwnedByCurrentUser: -1], "invalid pid is nobody's app");
  }

  /* --- process display and session membership --- */
  {
    NSTask *same = childWithDisplay(@":0.0");
    NSTask *other = childWithDisplay(@":77");
    NSTask *none = childWithDisplay(nil);
    pid_t samePID = [same processIdentifier];
    pid_t otherPID = [other processIdentifier];
    pid_t nonePID = [none processIdentifier];
    pid_t deadPID;

    PASS_EQUAL([GWProcessOwnership displayOfProcess: otherPID], @":77",
               "the DISPLAY of another process is read from its environment");
    PASS([GWProcessOwnership displayOfProcess: nonePID] == nil,
         "a process without DISPLAY has no display");

    PASS([GWProcessOwnership isProcessInCurrentSession: samePID],
         "our user on our display and screen is in the session");
    PASS(![GWProcessOwnership isProcessInCurrentSession: otherPID],
         "our user on another X display is not in the session");
    PASS(![GWProcessOwnership isProcessInCurrentSession: nonePID],
         "a process without a display is not in the session");
    if (getuid() != 0)
      {
        PASS(![GWProcessOwnership isProcessInCurrentSession: 1],
             "another user's process is not in the session");
      }

    /* --- workspace notification attribution --- */
    PASS([GWProcessOwnership isNotificationInfoInCurrentSession: infoWithPID(samePID)],
         "launch notification of an app on our display is ours");
    PASS(![GWProcessOwnership isNotificationInfoInCurrentSession: infoWithPID(otherPID)],
         "launch notification of an app on another display is not ours");

    {
      NSMutableDictionary *info = [NSMutableDictionary dictionaryWithObjectsAndKeys:
        @"TextEdit", @"NSApplicationName", nil];

      PASS(![GWProcessOwnership isNotificationInfoInCurrentSession: info],
           "a notification that names neither process nor display is not ours");
      [info setObject: @":0.0" forKey: GWLaunchDisplayKey];
      PASS([GWProcessOwnership isNotificationInfoInCurrentSession: info],
           "a launch announced for our display is ours");
      [info setObject: @":77" forKey: GWLaunchDisplayKey];
      PASS(![GWProcessOwnership isNotificationInfoInCurrentSession: info],
           "a launch announced for another display is not ours");
      [info setObject: [NSNumber numberWithInt: (int)otherPID]
               forKey: @"NSApplicationProcessIdentifier"];
      [info setObject: @":0" forKey: GWLaunchDisplayKey];
      PASS(![GWProcessOwnership isNotificationInfoInCurrentSession: info],
           "the process is authoritative over a display stamp");
    }

    [same terminate];
    [other terminate];
    [none terminate];
    [same waitUntilExit];
    [other waitUntilExit];
    [none waitUntilExit];

    deadPID = otherPID;
    PASS(![GWProcessOwnership isProcessInCurrentSession: deadPID],
         "a process that is gone is not in the session");
  }

  [arp release];
  return 0;
}
