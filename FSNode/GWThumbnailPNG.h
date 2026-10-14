/*
 * GWThumbnailPNG.h
 *
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

/* The PNG pixel I/O of the thumbnail store, on libpng directly: every
 * stored file carries its source's path and stamp in tEXt chunks, which
 * NSBitmapImageRep can neither write nor hand back, and decoding to plain
 * RGBA here needs no graphics context, so it is safe on the background
 * threads that fill the store. */

#ifndef GW_THUMBNAIL_PNG_H
#define GW_THUMBNAIL_PNG_H

#import <Foundation/Foundation.h>

/* No real icon needs more; it bounds what a hostile .DirIcon can make
 * Workspace allocate while decoding. */
#define GW_THUMBNAIL_MAX_DECODE_SIDE 4096

/* Any PNG, expanded to 8-bit non-premultiplied RGBA; nil when the data is
 * not a PNG libpng can decode, or larger than maxSide on either side (a
 * hostile .DirIcon must not make Workspace allocate gigabytes). */
NSData *GWThumbnailPNGDecodeRGBA(NSData *png, NSUInteger maxSide,
                                 NSUInteger *width, NSUInteger *height);

/* An 8-bit RGBA PNG of the pixels, with the given tEXt chunks written
 * ahead of the image data so readers of only the head of the file find
 * them; keys and values must be Latin-1. nil on any libpng error. */
NSData *GWThumbnailPNGEncodeRGBA(NSData *rgba, NSUInteger width,
                                 NSUInteger height, NSDictionary *text);

#endif
