/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

/* GWScaleFactor.m - the desktop's scale factor as an environment variable for
 * the applications Workspace starts.  See GWScaleFactor.h. */

#import "GWScaleFactor.h"

#include <stdio.h>

/* Enough for any float a scale factor can be written as, with its sign,
 * a decimal point and a handful of digits: "%g" never emits an exponent for
 * a factor between 0.01 and 1e6. */
#define GW_SCALE_FACTOR_CHARS 32

float GWScaleFactor(void)
{
  id val = [[NSUserDefaults standardUserDefaults] objectForKey:@"GSScaleFactor"];
  float factor = val ? [val floatValue] : 0.0F;

  return (factor > 0.0F) ? factor : 1.0F;
}

NSString *GWScaleFactorString(void)
{
  char buf[GW_SCALE_FACTOR_CHARS];

  /* snprintf, not -[NSString stringWithFormat:]: %g there is C-locale only on
     some bases, and a child that cannot parse the number scales itself by 1.0
     silently instead of failing loudly.  %g keeps 1.2 out of the 1.2000000 a
     fixed "%f" would hand Qt, and drops the ".0" of a whole 2. */
  snprintf(buf, sizeof(buf), "%g", (double)GWScaleFactor());
  return [NSString stringWithUTF8String:buf];
}

NSDictionary *GWEnvironmentWithScaleFactor(NSDictionary *environment)
{
  NSMutableDictionary *env;

  if (environment == nil) {
    environment = [[NSProcessInfo processInfo] environment];
  }

  env = [environment mutableCopy];
  [env setObject:GWScaleFactorString() forKey:@"QT_SCALE_FACTOR"];

  return [env autorelease];
}