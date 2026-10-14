/*
 * GWThumbnailSpec.h
 *
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

/* The rules of the shared thumbnail cache in ~/.cache/thumbnails as plain
 * functions: where the cache lives, how an original is named in it, what
 * its PNG text chunks say and whether an entry still describes the
 * original. Foundation and C only, so all of it can be tested headless;
 * the PNG pixel I/O lives in GWThumbnailPNG and the file handling in
 * GWThumbnailStore. */

#ifndef GW_THUMBNAIL_SPEC_H
#define GW_THUMBNAIL_SPEC_H

#import <Foundation/Foundation.h>

extern NSString * const GWThumbnailKeyURI;
extern NSString * const GWThumbnailKeyMTime;
extern NSString * const GWThumbnailKeySize;
extern NSString * const GWThumbnailKeyMimetype;
extern NSString * const GWThumbnailKeySoftware;

/* An original older than this whose whole directory is gone is treated as
 * deleted rather than as sitting on unmounted removable media. */
extern const NSTimeInterval GWThumbnailOrphanAge;

/* What the standard compares an entry against. */
typedef struct
{
  long long mtime;
  long long size;
} GWThumbnailFileStamp;

/* What the sweep knows about the original an entry names. */
typedef struct
{
  BOOL exists;
  BOOL parentExists;
  GWThumbnailFileStamp stamp;
} GWThumbnailOriginalState;

/* $XDG_CACHE_HOME/thumbnails, or $HOME/.cache/thumbnails when the variable
 * is unset, empty or relative (the base directory spec says to ignore a
 * relative value). */
NSString *GWThumbnailCacheDirectory(NSString *xdgCacheHome,
                                    NSString *homeDirectory);

/* The canonical file URI of an absolute path, escaped as GLib's
 * g_filename_to_uri() does, since that is what every other thumbnailer
 * hashes; nil for a relative path. */
NSString *GWThumbnailURIForPath(NSString *absolutePath);

/* The inverse for the sweep: the path of a file: URI, nil for anything
 * else (other schemes, broken escapes). */
NSString *GWThumbnailPathForURI(NSString *uri);

/* Lowercase hex MD5 of the URI plus ".png". */
NSString *GWThumbnailFileNameForURI(NSString *uri);

/* normal, large, x-large, xx-large: the smallest size directory whose box
 * holds the given pixel size, and the largest one above 1024. */
NSString *GWThumbnailSizeDirectoryForPixels(NSUInteger pixels);
NSUInteger GWThumbnailPixelsForSizeDirectory(NSString *directory);
NSArray *GWThumbnailSizeDirectories(void);

/* The fail/ subdirectory a program owns: its name and version. */
NSString *GWThumbnailFailureDirectoryName(NSString *program,
                                          NSString *version);

/* The tEXt chunks ahead of the first IDAT, keys and values read as
 * Latin-1. Stops at IDAT so a sweep can pass just the head of a file;
 * nil when the data is not a PNG. */
NSDictionary *GWThumbnailTextChunksInPNG(NSData *png);

/* The standard's validity check: the URI matches, Thumb::MTime is present
 * and equal, and Thumb::Size is equal when present. */
BOOL GWThumbnailMatchesFile(NSDictionary *text, NSString *uri,
                            GWThumbnailFileStamp stamp);

/* Whether the sweep may delete an entry: only one whose Software key is
 * ours (other programs' thumbnails are never touched), whose original is
 * gone or no longer matches. A missing original whose directory is gone
 * too may sit on unmounted media, so it only counts as deleted once the
 * entry is older than GWThumbnailOrphanAge. */
BOOL GWThumbnailIsStale(NSDictionary *text, NSString *software,
                        GWThumbnailOriginalState original,
                        NSTimeInterval entryAge);

/* The size that fits w x h into a box x box square keeping the aspect
 * ratio, never upscaling. */
void GWThumbnailFitSize(NSUInteger width, NSUInteger height, NSUInteger box,
                        NSUInteger *outWidth, NSUInteger *outHeight);

/* Area-average downscale of 8-bit non-premultiplied RGBA, weighting colour
 * by alpha so transparent pixels do not darken the edges; nil when the
 * buffer does not match the size or the target is larger. */
NSData *GWThumbnailDownscaleRGBA(NSData *rgba,
                                 NSUInteger width, NSUInteger height,
                                 NSUInteger newWidth, NSUInteger newHeight);

#endif
