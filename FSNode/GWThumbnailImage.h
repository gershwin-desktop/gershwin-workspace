/*
 * GWThumbnailImage.h
 *
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

/* Between images and the plain RGBA the thumbnail store keeps, without
 * ever drawing: NSImage's own resizing draws through lockFocus, a round
 * trip to the X server per image (about 9 ms an icon, measured), and
 * drawing is not safe off the main thread, while these functions are. */

#ifndef GW_THUMBNAIL_IMAGE_H
#define GW_THUMBNAIL_IMAGE_H

#import <AppKit/AppKit.h>

/* 8-bit non-premultiplied RGBA of the largest bitmap in an image, of
 * encoded image data (PNG through libpng, everything else NSImage can
 * read through NSBitmapImageRep), or of one bitmap. nil when there is no
 * bitmap (a vector image), when its colour space is not grey or RGB, or
 * when it is larger than maxSide. */
NSData *GWThumbnailRGBAFromImage(NSImage *image, NSUInteger maxSide,
                                 NSUInteger *width, NSUInteger *height);
NSData *GWThumbnailRGBAFromData(NSData *data, NSUInteger maxSide,
                                NSUInteger *width, NSUInteger *height);
NSData *GWThumbnailRGBAFromBitmap(NSBitmapImageRep *rep, NSUInteger maxSide,
                                  NSUInteger *width, NSUInteger *height);

/* An image of at most points x points for a display scaled by scale,
 * made from a stored PNG: decoded and scaled down in plain C to exactly
 * the pixels needed, never up. nil when png cannot be decoded. */
NSImage *GWThumbnailImageFromPNG(NSData *png, CGFloat points, CGFloat scale);

#endif
