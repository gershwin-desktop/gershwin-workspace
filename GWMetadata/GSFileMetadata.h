/* GSFileMetadata.h
 *
 * Metadata model for Mac OS / macOS Finder metadata on GNUstep.
 *
 * GSFileMetadata encapsulates all macOS file metadata:
 *   - Type code and creator code (from FinderInfo)
 *   - Finder flags (custom icon, invisible, locked, alias, stationery, bundle)
 *   - Color label (0-7)
 *   - Icon position in folder (fdLocation)
 *   - Resource fork data
 *   - Finder/Spotlight comment
 *
 * Storage:
 *   Primary:   Extended attributes (user.com.apple.FinderInfo, etc.)
 *   Fallback:  AppleDouble ._ sidecar file (for non-xattr filesystems)
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

#ifndef GSFILEMETADATA_H
#define GSFILEMETADATA_H

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>

/*
 * Four-character codes (OSType) for type/creator.
 * We use uint32_t; on macOS this is defined in CoreServices/UTCoreTypes.h.
 */
typedef uint32_t GSOType;

/*
 * Finder flag bit positions in the FinderInfo fdFlags field
 * (bytes 8-9 of the 32-byte FinderInfo, little-endian on disk).
 *
 * These match the classic Mac OS Finder flags.
 */
typedef NS_OPTIONS(uint16_t, GSFileFinderFlags) {
  GSFileFinderIsOnDesk       = 1 << 0,
  GSFileFinderColorFlag      = 1 << 1,   /* bit 1 + bits 2-3 = label */
  GSFileFinderColorBits      = (1 << 1) | (1 << 2) | (1 << 3),
  GSFileFinderIsShared       = 1 << 4,
  GSFileFinderHasNoINITs     = 1 << 5,
  GSFileFinderHasBeenInited  = 1 << 6,
  GSFileFinderHasCustomIcon  = 1 << 7,
  GSFileFinderIsStationery   = 1 << 8,
  GSFileFinderIsNameLocked   = 1 << 9,
  GSFileFinderHasBundle      = 1 << 10,
  GSFileFinderIsInvisible    = 1 << 11,
  GSFileFinderIsAlias        = 1 << 12,
};

/*
 * Standard Finder label colours (0-7).
 */
typedef NS_ENUM(NSInteger, GSFileLabel) {
  GSFileLabelNone    = 0,
  GSFileLabelGrey    = 1,
  GSFileLabelGreen   = 2,
  GSFileLabelPurple  = 3,
  GSFileLabelBlue    = 4,
  GSFileLabelYellow  = 5,
  GSFileLabelRed     = 6,
  GSFileLabelOrange  = 7,
};

/*
 * Xattr names we use.
 */
#define GSXATTR_FINDERINFO       @"user.com.apple.FinderInfo"
#define GSXATTR_RESOURCEFORK     @"user.com.apple.ResourceFork"
#define GSXATTR_FINDERCOMMENT    @"user.com.apple.metadata:kMDItemFinderComment"
#define GSXATTR_TEXTENCODING     @"user.com.apple.TextEncoding"
#define GSXATTR_QUARANTINE       @"user.com.apple.quarantine"

/**
 * GSFileMetadata encapsulates all macOS file metadata and provides
 * read/write access via xattrs (primary) or AppleDouble sidecar files
 * (fallback for non-xattr filesystems).
 *
 * Lifecycle:
 *   GSFileMetadata *md = [GSFileMetadata metadataForFileAtPath: path];
 *   // ... inspect/modify properties ...
 *   [md writeToFileAtPath: path error: NULL];
 */
@interface GSFileMetadata : NSObject <NSCopying>
{
  /* Raw data backing the properties */
  NSData            *_finderInfo;       // 32 bytes, raw from xattr
  NSData            *_resourceFork;     // Resource fork data
  NSString          *_finderComment;    // Spotlight comment

  /* Cached parsed properties (invalidated when _finderInfo changes) */
  struct {
    BOOL valid;
    GSOType typeCode;
    GSOType creatorCode;
    uint16_t flags;
    NSPoint iconPosition;
    NSInteger labelNumber;
  } _parsed;

  /* Sidecar mode override */
  BOOL _forceSidecar;
}

/* =================================================================
 * Raw data access
 * ================================================================= */

/** Raw 32-byte FinderInfo data. */
@property (nonatomic, copy) NSData *finderInfo;

/** Raw resource fork data. */
@property (copy) NSData *resourceFork;

/** Finder/Spotlight comment (kMDItemFinderComment). */
@property (copy) NSString *finderComment;

/* =================================================================
 * Convenient parsed properties from FinderInfo
 * ================================================================= */

/** Mac OS type code (e.g. 'TEXT', 'APPL'). */
@property GSOType typeCode;

/** Mac OS creator code (e.g. 'MSWD', 'ttxt'). */
@property GSOType creatorCode;

/** Raw Finder flags (fdFlags). */
@property uint16_t finderFlags;

/** File is locked (name locked in Finder). */
@property (getter=isLocked) BOOL locked;

/** File has a custom icon (check resource fork for icns data). */
@property (getter=hasCustomIcon) BOOL customIcon;

/** File is invisible in the Finder. */
@property (getter=isInvisible) BOOL invisible;

/** File is an alias/symlink in Mac terms. */
@property (getter=isAlias) BOOL alias;

/** File is stationery (template). */
@property (getter=isStationery) BOOL stationery;

/** Directory has bundle bit set. */
@property (getter=hasBundle) BOOL hasBundle;

/**
 * Icon position in the parent folder (fdLocation).
 * A position of (-1, -1) means "not set" / automatic.
 */
@property NSPoint iconPosition;

/**
 * Finder colour label (0-7). 0 = none.
 * Note: labelNumber 0 maps to GSFileLabelNone.
 */
@property NSInteger labelNumber;

/* =================================================================
 * Read / Write
 * ================================================================= */

/**
 * Create metadata by reading from a file path.
 * Tries xattrs first; falls back to AppleDouble ._ sidecar file.
 * Returns nil if no metadata is found.
 */
+ (GSFileMetadata *)metadataForFileAtPath:(NSString *)path;

/**
 * Create metadata by reading from a file path.
 * If `forceSidecar` is YES, only reads from the ._ sidecar file,
 * skipping xattr lookup.
 */
+ (GSFileMetadata *)metadataForFileAtPath:(NSString *)path
                             forceSidecar:(BOOL)forceSidecar;

/**
 * Cache control for +metadataForFileAtPath:.  The default read path caches
 * results (including "no metadata") keyed by path.  Callers that change a
 * file's metadata out of band should invalidate; the shared read caches are
 * also flushed wholesale on directory refresh.
 */
+ (void)invalidateAllCachedMetadata;
+ (void)invalidateCachedMetadataForPath:(NSString *)path;

/**
 * Write metadata to a file path.
 * Tries xattrs first; falls back to creating/updating a ._ sidecar file.
 * Returns YES on success, NO on failure (error is set if provided).
 */
- (BOOL)writeToFileAtPath:(NSString *)path error:(NSError **)error;

/**
 * Write metadata using only sidecar ._ file (even if xattrs are available).
 */
- (BOOL)writeSidecarToFileAtPath:(NSString *)path error:(NSError **)error;

/* =================================================================
 * AppleDouble conversion
 * ================================================================= */

/**
 * Convert the metadata to an AppleDouble V2 binary blob.
 * This is used when writing zip archives via libarchive.
 */
- (NSData *)appleDoubleData;

/**
 * Create metadata from an AppleDouble V2 binary blob.
 * This is used when reading zip archives created on macOS.
 */
+ (GSFileMetadata *)metadataFromAppleDoubleData:(NSData *)data;

/* =================================================================
 * Custom icon support
 * ================================================================= */

/**
 * Extract custom icon data from the resource fork.
 * Looks for an 'icns' resource (type 'icns', ID -16455 / kCustomIconResource).
 * Returns the raw icns data if found, nil otherwise.
 */
- (NSData *)customIconData;

/**
 * Extract custom icon as an NSImage for display.
 */
- (NSImage *)customIconAsImage;

/**
 * Utility: return the sidecar path for a given file path
 * (e.g. /foo/bar.txt -> /foo/._bar.txt).
 */
+ (NSString *)sidecarPathForFilePath:(NSString *)filePath;

/**
 * Utility: check if a path is a sidecar ._ path.
 */
+ (BOOL)isSidecarPath:(NSString *)path;

/**
 * Return the NSColor for a given Finder label number (0-7).
 * Returns nil for label 0 (none).
 */
+ (NSColor *)colorForLabel:(GSFileLabel)label;

/**
 * Whether we should use sidecar mode (xattrs unavailable or forced).
 */
@property BOOL forceSidecar;

@end
#endif /* GSFILEMETADATA_H */
