/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 */

#import "GWViewerChrome.h"

NSString *const GWViewerChromeDidChangeNotification = @"GWViewerChromeDidChangeNotification";

static NSString *const GWShowPathBarKey = @"ShowPathbar";
static NSString *const GWShowStatusBarKey = @"ShowStatusBar";

/* Both bars are shown unless the user turned one off, as in Finder. */
static BOOL
shownForKey(NSString *key)
{
  id value = [[NSUserDefaults standardUserDefaults] objectForKey: key];

  return value ? [value boolValue] : YES;
}

static void
setShownForKey(NSString *key, BOOL flag)
{
  [[NSUserDefaults standardUserDefaults] setBool: flag forKey: key];
  [[NSNotificationCenter defaultCenter]
    postNotificationName: GWViewerChromeDidChangeNotification object: nil];
}

@implementation GWViewerChrome

+ (BOOL)showsPathBar
{
  return shownForKey(GWShowPathBarKey);
}

+ (void)setShowsPathBar:(BOOL)flag
{
  setShownForKey(GWShowPathBarKey, flag);
}

+ (BOOL)showsStatusBar
{
  return shownForKey(GWShowStatusBarKey);
}

+ (void)setShowsStatusBar:(BOOL)flag
{
  setShownForKey(GWShowStatusBarKey, flag);
}

@end
