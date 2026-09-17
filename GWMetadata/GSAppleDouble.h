/* GSAppleDouble.h
 *
 * AppleSingle/AppleDouble V2 format handler.
 *
 * AppleDouble is the interchange format used by macOS for storing
 * file metadata alongside the data fork:
 *   - Inside __MACOSX folders in zip archives
 *   - As ._ filename sidecar files on filesystems that lack xattrs
 *   - As entries in AppleDouble blobs attached to libarchive entries
 *
 * This class can parse and generate AppleDouble V2 binary blobs.
 *
 * Format summary:
 *   Magic:   0x00 0x05 0x16 0x07  (AppleDouble)
 *   Version: 0x00 0x02 0x00 0x00  (V2)
 *   Filler:  16 bytes of zeros
 *   Entries: 2-byte count, then per-entry:
 *              4-byte entry ID (big-endian)
 *              4-byte offset   (big-endian, absolute from file start)
 *              4-byte length   (big-endian)
 *   Body:    concatenated entry data blocks
 *
 * Relevant entry IDs:
 *   1  DataFork      - The file's data (rarely used in AppleDouble)
 *   2  ResourceFork   - Classic Mac resource fork data
 *   9  FinderInfo     - 32-byte Finder Info record
 *   10 IconColor      - Icon color table (rare)
 *
 * SPDX-License-Identifier: GPL-2.0-or-later OR BSD-2-Clause
 */

#ifndef GSAPPLEDOUBLE_H
#define GSAPPLEDOUBLE_H

#import <Foundation/Foundation.h>

/*
 * AppleDouble V2 header constants.
 * Header: magic(4) + version(4) + filler(16) + entryCount(2) = 26 bytes.
 * Entry descriptor: entryID(4) + offset(4) + length(4) = 12 bytes.
 */
#define APPLEDOUBLE_HEADER_SIZE   26
#define APPLEDOUBLE_ENTRY_SIZE    12

/* AppleDouble entry IDs */
typedef NS_ENUM(uint32_t, GSAppleDoubleEntryID) {
  GSAppleDoubleDataFork      = 1,
  GSAppleDoubleResourceFork  = 2,
  GSAppleDoubleRealName      = 3,
  GSAppleDoubleComment       = 7,
  GSAppleDoubleIconBW        = 8,
  GSAppleDoubleFinderInfo    = 9,
  GSAppleDoubleIconColor     = 10,
  /* Extended-attribute range used for _kMDItemUserTags on foreign
   * filesystems (fallback only; the primary store is the xattr). */
  GSAppleDoubleUserTags      = 0x9001,
};

/**
 * GSAppleDouble represents the parsed contents of an AppleDouble V2 blob.
 *
 * Usage - parsing:
 * @code
 *   GSAppleDouble *ad = [[GSAppleDouble alloc] initWithData: blobData];
 *   NSData *finderInfo = [ad finderInfo];
 *   NSData *resourceFork = [ad resourceFork];
 * @endcode
 *
 * Usage - generation:
 * @code
 *   GSAppleDouble *ad = [[GSAppleDouble alloc] init];
 *   [ad setFinderInfo: my32ByteData];
 *   [ad setResourceFork: rsrcData];
 *   NSData *blob = [ad appleDoubleData];
 * @endcode
 */
@interface GSAppleDouble : NSObject <NSCopying>
{
  NSMutableDictionary *_entries;  // NSNumber(entryID) -> NSData
  NSMutableDictionary *_xattrs;   // NSString(name) -> NSData, from the
                                  // Apple "ATTR" extended-attributes blob
                                  // that macOS embeds inside entry ID 9
                                  // when a file carries xattrs (e.g.
                                  // com.apple.metadata:_kMDItemUserTags).
}

/**
 * Designated initializer: parse an existing AppleDouble blob.
 * Returns nil if the data is not valid AppleDouble V2.
 */
- (instancetype)initWithData:(NSData *)data;

/**
 * Create an empty AppleDouble container (for generation).
 */
- (instancetype)init;

/**
 * Set an entry's data by entry ID.
 */
- (void)setEntry:(GSAppleDoubleEntryID)entryID data:(NSData *)data;

/**
 * Get an entry's data by entry ID, or nil if not present.
 */
- (NSData *)dataForEntry:(GSAppleDoubleEntryID)entryID;

/**
 * Convenience: Finder Info (entry ID 9), 32 bytes.
 */
@property (nonatomic, copy) NSData *finderInfo;

/**
 * Convenience: Resource Fork (entry ID 2).
 */
@property (nonatomic, copy) NSData *resourceFork;

/**
 * Convenience: whether Finder Info is present.
 */
@property (nonatomic, readonly) BOOL hasFinderInfo;

/**
 * Convenience: whether Resource Fork is present.
 */
@property (nonatomic, readonly) BOOL hasResourceFork;

/**
 * Serialize to an AppleDouble V2 binary blob suitable for:
 *   - Writing to ._ filename sidecar files
 *   - Attaching to libarchive entries via archive_entry_set_mac_metadata()
 *   - Storing in __MACOSX directory entries
 */
- (NSData *)appleDoubleData;

/**
 * Parse an AppleDouble blob and return the Finder Info bytes,
 * or nil if not present. Convenience for quick access.
 */
+ (NSData *)finderInfoFromAppleDoubleData:(NSData *)data;

/**
 * Parse an AppleDouble blob and return the Resource Fork bytes,
 * or nil if not present.
 */
+ (NSData *)resourceForkFromAppleDoubleData:(NSData *)data;

/**
 * Stage an extended attribute for emission.  When any xattr has been
 * staged, -appleDoubleData switches from the classic layout (entry 9 =
 * bare FinderInfo, entry 2 = resource fork) to the layout macOS writes
 * for files carrying xattrs: entry 9 extends past the 32 FinderInfo
 * bytes into an "ATTR" blob holding every staged xattr, which is what
 * makes tags/comments readable on a real Mac after dot_clean/ditto.
 *
 * Keys use the raw macOS names (e.g. "com.apple.metadata:_kMDItemUserTags").
 */
- (void)setXattr:(NSData *)value forKey:(NSString *)name;

/**
 * Extended attributes carried in the Apple "ATTR" blob (entry ID 9,
 * after the 32-byte FinderInfo + 2-byte padding) that macOS writes
 * for files with xattrs.  Keys are xattr names (e.g.
 * "com.apple.metadata:_kMDItemUserTags"); values are the raw xattr
 * data.  nil when the blob is absent or empty.  The returned dictionary
 * is a copy; mutate via -setXattr:forKey:.
 */
- (NSDictionary<NSString *, NSData *> *)extendedAttributes;

@end

#endif /* GSAPPLEDOUBLE_H */
