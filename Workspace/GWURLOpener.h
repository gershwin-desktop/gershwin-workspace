/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 */

#ifndef GWURLOPENER_H
#define GWURLOPENER_H

#import <Foundation/Foundation.h>
#import "GWURLSchemeRegistry.h"

/**
 * Opens a non-file URL with whatever is registered for its scheme: a
 * GNUstep application through NSWorkspace, a freedesktop handler as a
 * detached process.  Workspace decides what to show when this fails.
 */
@interface GWURLOpener : NSObject <GWSchemeApplicationSource>

/** Returns YES when a handler was started.  Returns NO without an error
 * when nothing is registered for the scheme, and NO with an error when the
 * registered handler is broken or could not be started. */
- (BOOL)openURL:(NSURL *)url error:(NSError **)error;

@end

#endif
