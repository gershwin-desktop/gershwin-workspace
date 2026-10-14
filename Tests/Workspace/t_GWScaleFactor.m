/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

/* t_GWScaleFactor.m - the scale factor an application is launched with.
 * Workspace starts applications through GWApplicationLauncher (Cmd-O, a
 * double click, the Dock, Open With, Run External, the URL opener all end in
 * one NSTask there), and a Qt application scales itself only from
 * QT_SCALE_FACTOR.  These are the numbers the child process receives, and
 * they have to survive a user's locale, because `defaults read` prints this
 * user's GSScaleFactor as "1,2" and a child parses it with strtod().
 * Headless: the whole of GWScaleFactor is Foundation only. */

#include "../../Workspace/GWScaleFactor.m"
#import "Testing.h"
#import <Foundation/Foundation.h>

/* The scale factor these tests see, set for this process only, so they
 * neither depend on nor change the user's own GSScaleFactor. */
static void setTestScaleFactor(id value)
{
  NSUserDefaults *defs = [NSUserDefaults standardUserDefaults];

  [defs removeVolatileDomainForName:NSArgumentDomain];
  [defs setVolatileDomain:[NSDictionary dictionaryWithObject:value forKey:@"GSScaleFactor"]
                  forName:NSArgumentDomain];
}

int main(void)
{
  NSAutoreleasePool *arp = [NSAutoreleasePool new];

  setTestScaleFactor([NSNumber numberWithFloat:1.2f]);
  PASS(fabsf(GWScaleFactor() - 1.2f) < 0.0001f,
       "a fractional GSScaleFactor is the factor an application is launched at");
  PASS_EQUAL(GWScaleFactorString(), @"1.2",
             "1.2 is written with a dot, as a child process parses it");

  setTestScaleFactor([NSNumber numberWithFloat:2.0f]);
  PASS_EQUAL(GWScaleFactorString(), @"2", "a whole factor is written without a spurious .0");

  setTestScaleFactor([NSNumber numberWithFloat:1.25f]);
  PASS_EQUAL(GWScaleFactorString(), @"1.25", "1.25 keeps both of its decimals");

  /* A plist written by hand, or a value inherited in the environment, is a
   * string; it has to read as the number it spells. */
  setTestScaleFactor(@"1.5");
  PASS(fabsf(GWScaleFactor() - 1.5f) < 0.0001f,
       "a GSScaleFactor stored as a string is still read as a number");

  /* Zero or a negative factor would shrink every window to nothing, so it
   * falls back to 1:1 rather than being handed on. */
  setTestScaleFactor([NSNumber numberWithInt:0]);
  PASS_EQUAL(GWScaleFactorString(), @"1", "a zero factor falls back to 1");
  setTestScaleFactor([NSNumber numberWithInt:-2]);
  PASS_EQUAL(GWScaleFactorString(), @"1", "a negative factor falls back to 1");

  /* The environment the child gets is the one it would have inherited, plus
   * the scale: a Qt application needs DISPLAY, the session bus and the
   * GTK/Qt menu-bar modules as much as it needs the scale, and none of them
   * may be dropped on the way. */
  setTestScaleFactor([NSNumber numberWithFloat:1.25f]);
  {
    NSDictionary *base = [NSDictionary
        dictionaryWithObjectsAndKeys:@":0", @"DISPLAY", @"1.25", @"QT_SCALE_FACTOR", nil];
    NSDictionary *env = GWEnvironmentWithScaleFactor(base);

    PASS_EQUAL([env objectForKey:@"DISPLAY"], @":0",
               "the rest of the environment is passed on unchanged");
    PASS_EQUAL([env objectForKey:@"QT_SCALE_FACTOR"], @"1.25",
               "QT_SCALE_FACTOR carries the desktop's scale factor");
    PASS_EQUAL([base objectForKey:@"QT_SCALE_FACTOR"], @"1.25",
               "the caller's dictionary is not modified");
  }

  /* nil means "the launching process' own environment", which is what NSTask
   * would have inherited anyway - so DISPLAY really does reach a child. */
  {
    NSDictionary *own = [[NSProcessInfo processInfo] environment];
    NSDictionary *env = GWEnvironmentWithScaleFactor(nil);

    PASS([env count] >= [own count], "a nil environment is filled from this process' own");
    PASS_EQUAL([env objectForKey:@"QT_SCALE_FACTOR"], @"1.25",
               "the scale factor is added to the inherited environment too");
  }

  [arp release];
  return 0;
}