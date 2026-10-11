/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 */

/* The window bars Finder 10.6 shows or hides for all its windows at once,
 * not per folder [O:E13]: the path bar of the browsing windows and the
 * status bar of the spatial ones.  Kept under Finder's own default names. */

#import <Foundation/Foundation.h>

/* Posted after either setting changed, so open windows follow at once. */
extern NSString *const GWViewerChromeDidChangeNotification;

@interface GWViewerChrome : NSObject

+ (BOOL)showsPathBar;
+ (void)setShowsPathBar:(BOOL)flag;

+ (BOOL)showsStatusBar;
+ (void)setShowsStatusBar:(BOOL)flag;

@end
