/* t_DockStyle.m - headless coverage for the values of the Dock's three
 * styles: the "dockstyle" default and the rows of the style radios in
 * Preferences both map through DockStyleFromValue() in Dock.h.
 *
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import "Testing.h"
#import "Dock.h"

int
main(void)
{
  NSAutoreleasePool *arp = [NSAutoreleasePool new];

  /* The stored values must never change: they are in users' defaults. */
  PASS(DockStyleClassic == 0 && DockStyleModern == 1 && DockStyle3D == 2,
       "Classic, Modern and 3D are stored as 0, 1 and 2");

  PASS(DockStyleFromValue(0) == DockStyleClassic,
       "dockstyle 0 (and radio row 0) is Classic");
  PASS(DockStyleFromValue(1) == DockStyleModern,
       "dockstyle 1 (and radio row 1) is Modern");
  PASS(DockStyleFromValue(2) == DockStyle3D,
       "dockstyle 2 (and radio row 2) is 3D");
  PASS(DockStyleFromValue(3) == DockStyleClassic
       && DockStyleFromValue(-1) == DockStyleClassic,
       "an unknown dockstyle falls back to Classic");

  {
    /* A missing default reads as 0 through -intValue. */
    NSDictionary *none = [NSDictionary dictionary];

    PASS(DockStyleFromValue([[none objectForKey: @"dockstyle"] intValue])
         == DockStyleClassic,
         "without a dockstyle default the Dock is Classic");
  }

  {
    /* Written as a string by the defaults tool. */
    PASS(DockStyleFromValue([@"2" intValue]) == DockStyle3D,
         "a dockstyle written as the string \"2\" is 3D");
  }

  [arp release];
  return 0;
}
