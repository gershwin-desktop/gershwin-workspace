/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause OR GPL-3.0-or-later
 */

#ifndef _FSNALIASICON_H_
#define _FSNALIASICON_H_

#import <Foundation/Foundation.h>

/* The icon an alias file carries in its resource fork as 'icns' -16496, drawn
 * here from our own artwork: a generic document or folder with the alias
 * arrow.  It needs no display, so alias files can be written by tools. */
@interface FSNAliasIcon : NSObject

/* icns container with 128 and 256 pixel PNG images ('ic07', 'ic08'). */
+ (NSData *)icnsDataForDirectory:(BOOL)isDirectory;

@end

#endif
