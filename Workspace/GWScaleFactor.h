/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

#ifndef GWSCALEFACTOR_H
#define GWSCALEFACTOR_H

#import <Foundation/Foundation.h>

/* The desktop's scale factor: the GSScaleFactor user default every Gershwin
 * window and GNUstep view is laid out with, 1.0 when it is unset or not a
 * positive number (a bogus or zero value must never shrink a window to
 * nothing).  The one place that reads it for a launch, so every way of
 * starting an application - Cmd-O, a double click, the Dock, Open With, Run
 * External, the URL opener - hands the child the same number.  Foundation
 * only, so a headless test can exercise it without AppKit. */
extern float GWScaleFactor(void);

/* GWScaleFactor() formatted for an environment variable: "1", "1.25", "1.2".
 * Always a dot, never the comma this user's locale prints: `defaults read
 * NSGlobalDomain GSScaleFactor` answers "1,2" here, and a Qt application
 * parses QT_SCALE_FACTOR with a plain C strtod(), which stops at the comma. */
extern NSString *GWScaleFactorString(void);

/* A copy of `environment` with QT_SCALE_FACTOR set to GWScaleFactorString(),
 * so an application launched from the desktop comes up at the desktop's
 * scale instead of at 1:1 - the same reason GNUstep's own GSScaleFactor
 * exists, read by the toolkits that were not written for it.  A nil
 * `environment` means the launching process' own environment, which is what
 * NSTask would have inherited anyway; nothing else in it is changed, so
 * DISPLAY, the session bus and the GTK/Qt menu-bar modules still reach the
 * child exactly as before. */
extern NSDictionary *GWEnvironmentWithScaleFactor(NSDictionary *environment);

#endif