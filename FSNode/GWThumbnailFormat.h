/*
 * GWThumbnailFormat.h
 *
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

/* The decisions behind Workspace's thumbnail store, as plain functions:
 * what an index entry and a PNG's text chunks say, whether an entry still
 * describes its source, which entries a cleanup may drop, and how a bitmap
 * is fitted into the one stored size. Foundation and C only, so all of it
 * can be tested headless; the files themselves are GWThumbnailStore's. */

#ifndef GW_THUMBNAIL_FORMAT_H
#define GW_THUMBNAIL_FORMAT_H

#import <Foundation/Foundation.h>

/* What an entry holds: a thumbnail from a Thumbnailer bundle (the only
 * kind thumbnail views show), an icon (AppImage, application, custom
 * icon), or the record that a source could not be read. */
extern NSString * const GWThumbnailKindThumbnail;
extern NSString * const GWThumbnailKindIcon;
extern NSString * const GWThumbnailKindFailure;

/* Keys of an index entry, the value thumbnails.plist holds per source. */
extern NSString * const GWThumbnailEntryName;
extern NSString * const GWThumbnailEntryKind;
extern NSString * const GWThumbnailEntryMTime;
extern NSString * const GWThumbnailEntrySize;
extern NSString * const GWThumbnailEntryCTime;
extern NSString * const GWThumbnailEntrySource;

/* The same facts in each PNG's tEXt chunks, so a lost index can be rebuilt
 * from the files alone. */
extern NSString * const GWThumbnailTextPath;
extern NSString * const GWThumbnailTextKind;
extern NSString * const GWThumbnailTextMTime;
extern NSString * const GWThumbnailTextSize;
extern NSString * const GWThumbnailTextCTime;
extern NSString * const GWThumbnailTextSource;
extern NSString * const GWThumbnailTextSoftware;

/* A source whose whole directory has been gone this long is taken as
 * deleted rather than as sitting on unmounted removable media. */
extern const NSTimeInterval GWThumbnailOrphanAge;

typedef struct
{
  long long mtime;
  long long size;
  long long ctime;
} GWThumbnailFileStamp;

typedef struct
{
  BOOL exists;
  BOOL parentExists;
  GWThumbnailFileStamp stamp;
} GWThumbnailSourceState;

/* An index value of any age as an entry: a dictionary as it is, a bare
 * file name (what thumbnails.plist held before entries carried metadata)
 * as a thumbnail entry without stamp; nil for anything else. */
NSDictionary *GWThumbnailEntryFromIndexValue(id value);

/* A new entry. ctime is recorded only when watchCTime is set, for sources
 * whose content can change without touching mtime or size (an icon kept
 * in extended attributes). */
NSDictionary *GWThumbnailMakeEntry(NSString *name, NSString *kind,
                                   NSString *source,
                                   GWThumbnailFileStamp stamp,
                                   BOOL watchCTime);

/* The file the entry is validated against: its own source when it has
 * one (an application's icon file), the indexed path otherwise. */
NSString *GWThumbnailEntrySourcePath(NSDictionary *entry, NSString *path);

/* mtime and size present and equal, ctime equal when recorded. */
BOOL GWThumbnailEntryMatches(NSDictionary *entry, GWThumbnailFileStamp stamp);

/* Whether a cleanup may drop the entry: its source is gone or changed. A
 * missing source whose directory is gone too may be on unmounted media,
 * so it only counts once the entry is older than GWThumbnailOrphanAge. */
BOOL GWThumbnailEntryIsStale(NSDictionary *entry, GWThumbnailSourceState source,
                             NSTimeInterval entryAge);

/* The text chunks written into an entry's PNG, and the way back. */
NSDictionary *GWThumbnailTextForEntry(NSString *path, NSDictionary *entry,
                                      NSString *software);
NSDictionary *GWThumbnailEntryFromText(NSDictionary *text, NSString *name,
                                       NSString **outPath);

/* The tEXt chunks ahead of the first IDAT, read as Latin-1. Stops at IDAT
 * so the head of a file is enough; nil when the data is not a PNG. */
NSDictionary *GWThumbnailTextChunksInPNG(NSData *png);

/* Width and height from a PNG's IHDR, without decoding it. */
BOOL GWThumbnailPNGDimensions(NSData *png, NSUInteger *width, NSUInteger *height);

/* The counter a stored file name was made from (hex, as GWThumbnailer
 * always named them), -1 for a name that is not one. */
long GWThumbnailNameCounter(NSString *name);

/* The path of a file: URI, nil for anything else; only needed to read the
 * entries an earlier Workspace build kept under ~/.cache/thumbnails. */
NSString *GWThumbnailPathForFileURI(NSString *uri);

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
