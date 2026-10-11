/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-2.0-or-later
 */

/* t_GWSingleInstance.m - which Workspace a starting Workspace may replace.
 * Headless: only the decision and the selection naming are exercised. */

#import <Foundation/Foundation.h>
#import "Testing.h"
#include "../../Workspace/GWSingleInstance.m"

int main(void)
{
  NSAutoreleasePool *arp = [NSAutoreleasePool new];

  PASS(GWSingleInstanceVictim(0, 100) == 0,
       "no owner of the selection on this display: nothing to replace");
  PASS(GWSingleInstanceVictim(-1, 100) == 0,
       "an owner without a readable PID is never signalled");
  PASS(GWSingleInstanceVictim(100, 100) == 0,
       "never replace ourselves");
  PASS(GWSingleInstanceVictim(4242, 100) == 4242,
       "the previous owner on this display is replaced");

  PASS(strcmp(GWSingleInstanceSelectionName(0), "_GERSHWIN_WORKSPACE_S0") == 0,
       "selection name for screen 0");
  PASS(strcmp(GWSingleInstanceSelectionName(3), "_GERSHWIN_WORKSPACE_S3") == 0,
       "selection name for screen 3");
  PASS(strcmp(GWSingleInstanceSelectionName(0), "WM_S0") != 0,
       "never the window manager selection");

  [arp release];
  return 0;
}
