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
/* Bit positions match Apple's canonical fdFlags (see CarbonCore Finder.h /
 * TN1150): the Finder flag word is big-endian on disk.  These MUST agree
 * with what macOS actually writes/reads - if they drift, Gershwin mis-parses
 * real Mac files (and the interop fixtures silently encode the wrong bits).
 *   kIsOnDesk      0x0001  bit 0
 *   kColor         0x000E  bits 1-3 (label colour)
 *   kIsShared      0x0040  bit 6
 *   kHasNoINITs    0x0080  bit 7
 *   kHasBeenInited 0x0100  bit 8
 *   kHasCustomIcon 0x0400  bit 10
 *   kIsStationery  0x0800  bit 11
 *   kNameLocked    0x1000  bit 12
 *   kHasBundle     0x2000  bit 13
 *   kIsInvisible   0x4000  bit 14
 *   kIsAlias       0x8000  bit 15 */
typedef NS_OPTIONS(uint16_t, GSFileFinderFlags) {
  GSFileFinderIsOnDesk       = 1 << 0,
  GSFileFinderColorFlag      = 1 << 1,   /* bit 1 + bits 2-3 = label colour */
  GSFileFinderColorBits      = (1 << 1) | (1 << 2) | (1 << 3),
  GSFileFinderIsExtensionHidden = 1 << 4, /* 0x0010 kExtensionIsHidden */
  GSFileFinderIsShared       = 1 << 6,   /* 0x0040 */
  GSFileFinderHasNoINITs     = 1 << 7,   /* 0x0080 */
  GSFileFinderHasBeenInited  = 1 << 8,   /* 0x0100 */
  GSFileFinderHasCustomIcon  = 1 << 10,  /* 0x0400 kHasCustomIcon */
  GSFileFinderIsStationery   = 1 << 11,  /* 0x0800 */
  GSFileFinderIsNameLocked   = 1 << 12,  /* 0x1000 */
  GSFileFinderHasBundle      = 1 << 13,  /* 0x2000 */
  GSFileFinderIsInvisible    = 1 << 14,  /* 0x4000 kIsInvisible */
  GSFileFinderIsAlias        = 1 << 15,  /* 0x8000 */
};

/*
 * Standard label colours (0-7) in menu order: 1=Red, 2=Orange, 3=Yellow,
 * 4=Green, 5=Blue, 6=Purple, 7=Grey.  GSFileLabel is deliberately identical
 * to DSStoreLabelColor, and every label API of this class speaks it.
 *
 * The FinderInfo fdFlags kColor field (bits 1-3) does NOT use these values
 * but Finder's own colour numbers, observed on a 10.6 Finder (evidence E24)
 * and used by NSURLLabelNumberKey and the "Name\nN" tags of later systems:
 * 1=Grey, 2=Green, 3=Purple, 4=Blue, 5=Yellow, 6=Red, 7=Orange.
 * +labelForFinderColor: / +finderColorForLabel: are the only conversion.
 */
typedef NS_ENUM(NSInteger, GSFileLabel) {
  GSFileLabelNone    = 0,
  GSFileLabelRed     = 1,
  GSFileLabelOrange  = 2,
  GSFileLabelYellow  = 3,
  GSFileLabelGreen   = 4,
  GSFileLabelBlue    = 5,
  GSFileLabelPurple  = 6,
  GSFileLabelGrey    = 7,
};

/*
 * Xattr names we use.
 */
#define GSXATTR_FINDERINFO       @"user.com.apple.FinderInfo"
#define GSXATTR_RESOURCEFORK     @"user.com.apple.ResourceFork"
#define GSXATTR_FINDERCOMMENT    @"user.com.apple.metadata:kMDItemFinderComment"
#define GSXATTR_USERTAGS         @"user.com.apple.metadata:_kMDItemUserTags"
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
  NSData            *_userTagsData;     // raw _kMDItemUserTags plist
  NSString          *_quarantine;       // com.apple.quarantine record

  /* Cached parsed properties (invalidated when _finderInfo changes) */
  struct {
    BOOL valid;
    GSOType typeCode;
    GSOType creatorCode;
    uint16_t flags;
    NSPoint iconPosition;
    NSInteger labelNumber;
  } _parsed;

  /* Which of resource fork, comment, tags and quarantine a setter changed
   * (_modified) or that were read from disk (_loaded).  A write touches only
   * the modified ones, so a field nobody changed stays as it is on disk. */
  NSUInteger _modified;
  NSUInteger _loaded;

  /* Per FinderInfo byte, the bits a setter has set (value as set, 0
   * included).  A write patches exactly those over the bytes on disk. */
  uint8_t _fiTouched[32];

  /* Sidecar mode override */
  BOOL _forceSidecar;
}

/* =================================================================
 * Raw data access
 * ================================================================= */

/** Raw 32-byte FinderInfo data. */
@property (nonatomic, copy) NSData *finderInfo;

/** Raw resource fork data. */
@property (nonatomic, copy) NSData *resourceFork;

/** Finder/Spotlight comment (kMDItemFinderComment). */
@property (nonatomic, copy) NSString *finderComment;

/* =================================================================
 * Convenient parsed properties from FinderInfo
 * ================================================================= */

/** Mac OS type code (e.g. 'TEXT', 'APPL'). */
@property GSOType typeCode;

/** Mac OS creator code (e.g. 'MSWD', 'ttxt'). */
@property GSOType creatorCode;

/** Raw Finder flags (fdFlags). */
@property uint16_t finderFlags;

/** File is locked (name locked). */
@property (getter=isLocked) BOOL locked;

/** Finder.h kNameLocked; same bit as -isLocked, under the name Finder uses. */
@property (getter=isNameLocked) BOOL nameLocked;

/** Finder.h kExtensionIsHidden (fdFlags 0x0010): views show the name
 *  without its extension. */
@property (getter=isExtensionHidden) BOOL extensionHidden;

/** File has a custom icon (check resource fork for icns data). */
@property (getter=hasCustomIcon) BOOL customIcon;

/** File is invisible. */
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
 * Directory spatial view / window (FinderInfo DInfo)
 * -----------------------------------------------------------------
 * For a DIRECTORY the 32-byte FinderInfo is laid out as a `DInfo`
 * (not the file `FInfo`): bytes 0-7 are the window `frRect`
 * (top, left, bottom, right as big-endian int16), bytes 8-9 the
 * folder flags, bytes 10-13 the scroll point, and bytes 14-15 the
 * `frView` view-style code.  These accessors read/write that layout
 * and are only meaningful for folders; apply them to directory
 * metadata, never to file metadata.
 *
 * The `frView` numeric code maps to the same 4-character view code
 * used by `.DS_Store` `vstl` (icnv/Nlsv/clmv/Flwv/glyv) so the two
 * channels stay consistent.  On macOS 10.6 the browser-mode Finder
 * ignores these values (it keeps folder view/window state in its
 * private preferences); they are honoured by the classic/spatial
 * Finder and by newer macOS, and are used by Gershwin's own spatial
 * viewer.
 * ================================================================= */

/** Per-folder view style as a `.DS_Store` `vstl` 4-char code
 *  (icnv/Nlsv/clmv/Flwv/glyv), or nil when unset. */
- (NSString *)viewStyleCodeForDirectory;

/** Set the per-folder view style from a `vstl` 4-char code. */
- (void)setViewStyleCodeForDirectory:(NSString *)code;

/** Per-folder window bounds (frRect), or NSZeroRect when unset. */
- (NSRect)windowBoundsForDirectory;

/** Set the per-folder window bounds (frRect). */
- (void)setWindowBoundsForDirectory:(NSRect)bounds;

/**
 * User tags (_kMDItemUserTags), as an array of tag-name strings.
 * Tags live in com.apple.metadata:_kMDItemUserTags (a binary plist array of
 * strings); tags are never stored inside .DS_Store.  See Apple File System
 * Programming Guide:
 * https://developer.apple.com/library/archive/documentation/FileManagement/Conceptual/FileSystemProgrammingGuide/FileSystemOverview/FileSystemOverview.html
 * nil / empty means no tags.
 */
@property (copy) NSArray *userTags;

/** Raw _kMDItemUserTags xattr value (binary plist), or nil when unset. */
@property (nonatomic, copy) NSData *userTagsData;

/**
 * Quarantine record (com.apple.quarantine), e.g.
 * "0083;6a8c57fe;Safari;UUID".  Raw string form, exactly as stored;
 * nil when unset.  Note macOS sanitizes quarantine data that arrives
 * through AppleDouble ingestion (dot_clean/ditto) - untrusted records
 * are rewritten to "0000;00000000;;", so string equality only holds on
 * the pre-ingest bytes.
 */
@property (nonatomic, copy) NSString *quarantine;

/** The standard tag name for a label (e.g. GSFileLabelRed -> "Red"),
 *  or nil for GSFileLabelNone. */
+ (NSString *)tagNameForLabel:(GSFileLabel)label;

/** The label for a standard tag name, or GSFileLabelNone.  A tag with a
 *  colour number ("Red\n6", as later Finders write) is decided by the
 *  number, so localized names work too. */
+ (GSFileLabel)labelForTagName:(NSString *)tagName;

/** The label for a FinderInfo fdFlags colour field value (0-7, i.e.
 *  (fdFlags >> 1) & 7), which uses Finder's colour numbers (see above). */
+ (GSFileLabel)labelForFinderColor:(NSUInteger)color;

/** The fdFlags colour field value (0-7) Finder shows as `label`. */
+ (NSUInteger)finderColorForLabel:(GSFileLabel)label;

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

/* Classic Resource Manager forks (Inside Macintosh, More Macintosh Toolbox,
 * Resource Manager chapter).  Readers never trust an offset or size from the
 * fork: anything that points outside it makes the lookup return nil. */

/** Four-character code ("icns", "url ") as a GSOType; nil or a string that
 *  is not four MacRoman characters gives 0. */
+ (GSOType)osTypeFromString:(NSString *)string;

/** The data of resource `type`/`rid` in `fork`, or nil when absent or the
 *  fork is malformed.  An empty resource yields empty data. */
+ (NSData *)dataForResourceType:(GSOType)type
                     resourceID:(NSInteger)rid
                         inFork:(NSData *)fork;

/** The data of the resource of `type` with the lowest ID, or nil. */
+ (NSData *)firstDataForResourceType:(GSOType)type inFork:(NSData *)fork;

/** One entry for +resourceForkWithResources:. */
+ (NSDictionary *)resourceEntryWithType:(GSOType)type
                             resourceID:(NSInteger)rid
                                   data:(NSData *)data;

/** Builds a fork holding the given entries (from
 *  +resourceEntryWithType:resourceID:data:).  nil for no entries, an ID
 *  outside SInt16 or a fork the format cannot address (24 bit offsets). */
+ (NSData *)resourceForkWithResources:(NSArray *)entries;

/** Fork holding `icns` as the 'icns' resource -16455 (the custom icon). */
+ (NSData *)resourceForkWithICNS:(NSData *)icns;

/** The custom icon data of a fork: resource 'icns' -16455, or the data itself
 *  when it is a bare icns container (the form older versions stored). */
+ (NSData *)icnsDataFromResourceFork:(NSData *)fork;

/**
 * Set a custom icon from raw icns data.  Embeds the icns data in the
 * resource fork and sets the kHasCustomIcon FinderInfo flag - per TN1150 a
 * custom icon is not complete without the icon image in the fork:
 * https://developer.apple.com/library/archive/technotes/tn/tn1150.html
 */
- (void)setCustomIconData:(NSData *)icnsData;

/**
 * Remove a custom icon: clear the kHasCustomIcon flag and drop the
 * resource fork.
 */
- (void)clearCustomIcon;

/**
 * Extract custom icon as an NSImage for display.
 */
- (NSImage *)customIconAsImage;

/**
 * The icns custom icon of the item at `path`, nil when it has none.  For a
 * folder it is read from the invisible "Icon\r" file inside it, where Finder
 * keeps it, once the folder carries kHasCustomIcon; for anything else from
 * the item's own resource fork.
 */
+ (NSData *)customIconDataForPath:(NSString *)path;

/** The same icon decoded for display, nil when none or undecodable. */
+ (NSImage *)customIconImageForPath:(NSString *)path;

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
