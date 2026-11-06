/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

/* t_GWOpenAnimationGate.m - the open animation plays only once an open is
 * committed: not while "Trust This Application?" is asked, not after
 * Cancel, not when no application is found, and only once. */

#import <Foundation/Foundation.h>
#import "Testing.h"
#import "GWOpenAnimationGate.h"

int main(void)
{
  NSAutoreleasePool *arp = [NSAutoreleasePool new];
  GWOpenAnimationGate *gate = [GWOpenAnimationGate new];

  PASS ([gate fire] == nil, "nothing plays when nothing was opened");

  [gate arm: @"doc.txt"];
  PASS ([[gate fire] isEqual: @"doc.txt"], "a committed open plays the animation of the item opened");
  PASS ([gate fire] == nil, "and plays it only once");

  [gate arm: @"tool.AppImage"];
  [gate disarm];   /* Cancel in "Trust This Application?" */
  PASS ([gate fire] == nil, "a cancelled open plays nothing, not even on the next commit");

  [gate arm: @"old.txt"];
  [gate arm: @"new.txt"];
  PASS ([[gate fire] isEqual: @"new.txt"], "a newer open replaces one that never committed");

  [gate release];
  [arp release];
  return 0;
}
