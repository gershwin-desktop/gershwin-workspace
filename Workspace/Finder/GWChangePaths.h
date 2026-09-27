/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

#ifndef GWCHANGEPATHS_H
#define GWCHANGEPATHS_H

#import <Foundation/Foundation.h>

/* A destroy/recycle file operation carries no "destination" key
 * (performFileOperation: in WorkspaceApplication.m omits it when nil), so
 * Finder's fileSystemDidChange: builds a dstpaths array shorter than
 * srcpaths - indexing dstpaths by the same j used for srcpaths then raises
 * NSRangeException. Kept as its own Foundation-only function so the
 * boundary check is reviewable and testable without the rest of Finder. */
NSString *GWChangePathsDestinationAtIndex(NSArray *dstpaths, NSUInteger j);

#endif /* GWCHANGEPATHS_H */
